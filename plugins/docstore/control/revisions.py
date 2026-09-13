"""Durable logical identities/history/approval; never writes the search projection."""
import hashlib
import json
import re
from pathlib import PurePosixPath
from typing import Annotated
from pydantic import BaseModel, ConfigDict, Field, field_validator
from fastmcp.exceptions import ToolError
from governance import query
from verification import fingerprint

KEY_PATTERN = r'^(document|adr|note):[A-Za-z0-9_-]{1,128}$'

class CaptureRevision(BaseModel):
    model_config = ConfigDict(extra='forbid')
    document_key: str = Field(pattern=KEY_PATTERN)
    source_path: str = Field(min_length=1, max_length=1000)
    title: str = Field(min_length=1, max_length=300)
    body: str = Field(max_length=1024*1024)
    expected_generation: int = Field(ge=0)
    actor: str = Field(min_length=1, max_length=100)
    source_ref: str = Field(min_length=1, max_length=1000)

    @field_validator('body')
    @classmethod
    def bounded_utf8(cls, value):
        if len(value.encode('utf-8')) > 1024*1024:
            raise ValueError('Body exceeds 1 MiB UTF-8')
        return value

    @field_validator('source_path')
    @classmethod
    def canonical_path(cls, value):
        path = PurePosixPath(value)
        if path.is_absolute() or '\\' in value or ':' in value or '..' in path.parts or value != path.as_posix() or not value.startswith('docs/'):
            raise ValueError('Use a canonical relative docs/ source path')
        return value

class ApproveRevision(BaseModel):
    model_config = ConfigDict(extra='forbid')
    document_key: str = Field(pattern=KEY_PATTERN)
    revision_number: int = Field(ge=1)
    raw_sha256: str = Field(pattern=r'^[a-f0-9]{64}$')
    expected_generation: int = Field(ge=1)
    actor: str = Field(min_length=1, max_length=100)
    rationale: str = Field(min_length=1, max_length=2000)
    source_ref: str = Field(min_length=1, max_length=1000)
    request_key: str = Field(pattern=r'^[A-Za-z0-9_-]{1,128}$')

def object_result(value):
    if isinstance(value,list) and len(value)==1:
        value=value[0]
    if not isinstance(value,dict):
        raise ToolError('Unexpected revision operation response; read back before retrying')
    return value

def document_id(key):
    return 'docstore_document:' + hashlib.sha256(key.encode()).hexdigest()

def revision_id(key, number):
    return 'docstore_revision:' + hashlib.sha256(key.encode()).hexdigest() + '_' + str(number)

def verified_head(head, key):
    if (not isinstance(head, dict) or head.get('id') != document_id(key)
        or head.get('document_key') != key
        or type(head.get('generation')) is not int or head['generation'] < 1
        or type(head.get('latest_number')) is not int or head['latest_number'] < 1
        or head.get('current_revision') != revision_id(key, head['latest_number'])
        or not isinstance(head.get('current_hash'), str)
        or not re.fullmatch(r'[a-f0-9]{64}', head['current_hash'])):
        raise ToolError('Invalid revision head; independently read back before retrying')
    return head

async def capture(config, item: CaptureRevision, execute=query):
    params={'key':item.document_key,'path':item.source_path,'title':item.title,'body':item.body,
            'projection_hash':fingerprint(item.body.encode('utf-8')),'expected':item.expected_generation,
            'actor':item.actor,'source_ref':item.source_ref}
    result=object_result(await execute(config,
        'BEGIN TRANSACTION; RETURN fn::docstore_capture_revision($key,$path,$title,$body,$projection_hash,$expected,$actor,$source_ref); COMMIT TRANSACTION;',params))
    head=verified_head(result.get('head'),item.document_key)
    if (head.get('current_hash')!=hashlib.sha256(item.body.encode('utf-8')).hexdigest()
        or head.get('source_path')!=item.source_path or head.get('title')!=item.title
        or type(result.get('unchanged')) is not bool
        or (not result['unchanged'] and head['generation'] != item.expected_generation + 1)):
        raise ToolError('Revision capture could not be verified; inspect state')
    return {**result,'indexing_triggered':False,'search_projection_updated':False}

async def approve(config, item: ApproveRevision, execute=query):
    canonical=item.model_dump(exclude={'expected_generation'})
    params={'key':item.document_key,'number':item.revision_number,'hash':item.raw_sha256,
            'expected':item.expected_generation,'actor':item.actor,'rationale':item.rationale,
            'source_ref':item.source_ref,'request_key':item.request_key,
            'request_hash':hashlib.sha256(json.dumps(canonical,sort_keys=True).encode()).hexdigest()}
    result=object_result(await execute(config,
        'BEGIN TRANSACTION; RETURN fn::docstore_approve_revision($key,$number,$hash,$expected,$actor,$rationale,$source_ref,$request_key,$request_hash); COMMIT TRANSACTION;',params))
    row=result.get('approval')
    expected={'id':'docstore_approval:'+hashlib.sha256((item.document_key+':'+item.request_key).encode()).hexdigest(),
        'document':document_id(item.document_key), 'revision':revision_id(item.document_key,item.revision_number),
        'raw_sha256':item.raw_sha256, 'request_hash':params['request_hash'],
        'actor':item.actor, 'rationale':item.rationale, 'source_ref':item.source_ref}
    if not isinstance(row,dict) or any(row.get(k)!=v for k,v in expected.items()):
        raise ToolError('Approval could not be verified; inspect state')
    return {**result,'indexing_triggered':False,'approval_scope':'exact content revision, not title/path metadata'}

async def state(config, document_key, execute=query):
    if not re.fullmatch(KEY_PATTERN,document_key):
        raise ToolError('Invalid document key')
    rid=document_id(document_key)
    result=object_result(await execute(config,"""RETURN {
      head: (SELECT * FROM ONLY type::record($rid)),
      revisions: (SELECT id,number,raw_sha256,projection_sha256,projection_profile,source_path,actor,at FROM docstore_revision WHERE document=type::record($rid) ORDER BY number DESC LIMIT 21),
      approvals: (SELECT * FROM docstore_approval WHERE document=type::record($rid) ORDER BY at DESC LIMIT 21),
      aliases: (SELECT source_path FROM docstore_source_alias WHERE document=type::record($rid) LIMIT 21),
      events: (SELECT * FROM docstore_revision_event WHERE document=type::record($rid) ORDER BY generation DESC LIMIT 21),
      approved_content: (SELECT id,document,number,raw_sha256 FROM ONLY (SELECT * FROM ONLY type::record($rid)).approved_revision)
    };""",{'rid':rid}))
    head=result.get('head')
    if head is not None:
        verified_head(head,document_key)
    for key in ('revisions','approvals','aliases','events'):
        rows=result.get(key)
        if not isinstance(rows,list): raise ToolError('Invalid revision-state result')
        result[key+'_truncated']=len(rows)>20
        result[key]=rows[:20]
    status='unapproved' if head else 'document_missing'
    if head and head.get('approved_revision'):
        approved=result.get('approved_content')
        if (not isinstance(approved,dict) or approved.get('document')!=rid
            or type(approved.get('number')) is not int or approved['number'] < 1
            or approved['number'] > head['latest_number']
            or approved.get('id')!=head['approved_revision']
            or approved['id']!=revision_id(document_key,approved['number'])
            or (approved['id']==head['current_revision'] and approved.get('raw_sha256')!=head['current_hash'])):
            raise ToolError('Invalid approval linkage; inspect revision state')
        status='approved_current' if head['approved_revision']==head['current_revision'] else 'changed_since_approval'
    return {**result,'approval_status':status,'projection_status':'unverified','cdc_execution':'unproven'}

def register(mcp, config, read_annotations):
    write={**read_annotations,'readOnlyHint':False,'destructiveHint':False,'idempotentHint':True}
    @mcp.tool(annotations=write)
    async def docstore_capture_revision(revision: CaptureRevision) -> dict:
        """Capture bounded document content/history under a stable logical key; metadata-only rename retains revision. Does not run indexing."""
        return await capture(config,revision)
    @mcp.tool(annotations=write)
    async def docstore_approve_revision(approval: ApproveRevision) -> dict:
        """Record explicitly authorized approval of exact current content revision/hash; never infer approval from active status."""
        return await approve(config,approval)
    @mcp.tool(annotations=read_annotations)
    async def docstore_revision_state(document_key: Annotated[str,Field(pattern=KEY_PATTERN)]) -> dict:
        """Read current logical identity, revision metadata, approvals and path aliases; distinguishes changed-since-approval from indexing status."""
        return await state(config,document_key)
