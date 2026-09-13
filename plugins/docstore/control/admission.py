"""Read-only, revision-bound admission plan for future selected Docstore CDC."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from functools import partial
from pathlib import Path, PurePosixPath
import re
import sys

from fastmcp.exceptions import ToolError
from pydantic import BaseModel, ConfigDict, Field, field_validator

from governance import native_client, query
from revisions import KEY_PATTERN, revision_id, state
from verification import fingerprint, read_selected


class SelectedFile(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    document_key: str = Field(pattern=KEY_PATTERN)
    source_path: str = Field(min_length=6, max_length=1000)
    expected_generation: int = Field(ge=1)
    expected_revision_number: int = Field(ge=1)
    expected_raw_sha256: str = Field(pattern=r'^[a-f0-9]{64}$')

    @field_validator('source_path')
    @classmethod
    def canonical_source(cls,value):
        path=PurePosixPath(value)
        if (path.is_absolute() or '\\' in value or ':' in value or '..' in path.parts
                or value!=path.as_posix() or not value.startswith('docs/')
                or path.suffix.lower()!='.md'):
            raise ValueError('Use a canonical repository-relative docs/*.md path')
        if path.parts[1]=='private' or 'to_be_deleted' in path.parts[1:]:
            raise ValueError('Path is excluded by the Docstore worker')
        return value


class SelectedUpdatePlan(BaseModel):
    model_config = ConfigDict(extra='forbid')
    files: list[SelectedFile] = Field(min_length=1,max_length=20)


def worker_document_id(source_path):
    return 'document:'+re.sub(r'[^a-z0-9]+','_',source_path.lower()).strip('_')[:120]


def _identity_type():
    path=Path(__file__).resolve().parents[3]/'scripts/docstore/selected_identity.py'
    name='_docstore_selected_identity_contract'
    module=sys.modules.get(name)
    if module is None:
        spec=importlib.util.spec_from_file_location(name,path)
        if spec is None or spec.loader is None:
            raise ToolError('Selected CDC identity contract unavailable')
        module=importlib.util.module_from_spec(spec)
        sys.modules[name]=module
        try: spec.loader.exec_module(module)
        except Exception:
            sys.modules.pop(name,None)
            raise ToolError('Selected CDC identity contract unavailable') from None
    return module.SelectedBootstrapIdentity


def candidate_identity():
    identity=_identity_type()(
        app='ProbataDocStore',environment='probata-docstore',
        topology='selected-live-parent-v1',
        source='context=docstore_docs_dir;root=repository/docs;include=**/*.md;exclude=private/**,**/to_be_deleted/**',
        tracking='dedicated DOCSTORE_COCOINDEX_DB;exact locator not observed by control',
        target='context=docstore;namespace=probata;database=docs;document,chunk,chunk_of',
        processing_profile='process_file=v6;mapping,chunk,embedding and schema digests required at bootstrap')
    return {**identity.__dict__,'digest':identity.digest(),'candidate_only':True}


def stable_read(config,source_path):
    relative=source_path.removeprefix('docs/')
    absolute=(config.source_root.resolve()/Path(relative)).resolve()
    try: before=absolute.stat()
    except OSError: raise ToolError('Selected source missing or unreadable; no indexing started') from None
    content=read_selected(config.source_root,relative)
    try: after=absolute.stat()
    except OSError: raise ToolError('Selected source changed while planning; retry') from None
    fields=('st_size','st_mtime_ns','st_ino')
    if any(getattr(before,name,None)!=getattr(after,name,None) for name in fields):
        raise ToolError('Selected source changed while planning; retry')
    return content


def validate_unique(files):
    seen={'document_key':set(),'source_path':set(),'worker_document_id':set()}
    for item in files:
        values={'document_key':item.document_key,'source_path':item.source_path,
                'worker_document_id':worker_document_id(item.source_path)}
        for kind,value in values.items():
            if value in seen[kind]:
                raise ToolError(f'Duplicate or colliding selected {kind}')
            seen[kind].add(value)


async def plan(config,request: SelectedUpdatePlan,execute=query):
    validate_unique(request.files)
    identity=candidate_identity()
    canonical_request=request.model_dump(mode='json')
    request_sha=hashlib.sha256(json.dumps(canonical_request,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    if execute is query:
        async with native_client(config) as client:
            return await plan(config,request,execute=partial(query,client=client))
    rows=[]
    for item in request.files:
        content=stable_read(config,item.source_path)
        raw=hashlib.sha256(content).hexdigest()
        try: projected=fingerprint(content)
        except UnicodeDecodeError: raise ToolError('Source is not UTF-8; selected update refused') from None
        snapshot=await state(config,item.document_key,execute=execute)
        head=snapshot.get('head')
        current=next((r for r in snapshot.get('revisions',[]) if isinstance(r,dict)
                      and r.get('id')==(head or {}).get('current_revision')),None)
        issues=[]
        expected_revision=revision_id(item.document_key,item.expected_revision_number)
        if raw!=item.expected_raw_sha256:
            issues.append('source_raw_hash_mismatch')
        if head is None:
            issues.append('logical_document_missing')
        else:
            head_checks=(
                (head.get('source_path')==item.source_path,'head_source_path_mismatch'),
                (head.get('generation')==item.expected_generation,'generation_mismatch'),
                (head.get('current_revision')==expected_revision,'current_revision_mismatch'),
                (head.get('current_hash')==item.expected_raw_sha256,'head_raw_hash_mismatch'))
            issues.extend(label for ok,label in head_checks if not ok)
            if current is None:
                issues.append('current_revision_metadata_missing')
            else:
                revision_checks=(
                    (current.get('number')==item.expected_revision_number,'revision_number_mismatch'),
                    (current.get('raw_sha256')==raw,'revision_raw_hash_mismatch'),
                    (current.get('projection_sha256')==projected,'revision_projection_hash_mismatch'),
                    (current.get('projection_profile')=='docstore-fold-non-bmp-v1','projection_profile_mismatch'))
                issues.extend(label for ok,label in revision_checks if not ok)
        rows.append({'document_key':item.document_key,'source_path':item.source_path,
            'generation':(head or {}).get('generation'),'current_revision':(head or {}).get('current_revision'),
            'revision_number':(current or {}).get('number'),'raw_sha256':raw,
            'projection_sha256':projected,'projection_profile':'docstore-fold-non-bmp-v1',
            'bytes':len(content),'worker_document_id':worker_document_id(item.source_path),
            'approval_status':snapshot.get('approval_status'),'eligible':not issues,'issues':issues})
    body={'manifest_version':'docstore-selected-update-plan-v1','request_sha256':request_sha,
          'instance':config.instance,'worker_identity':identity,'files':rows}
    manifest_sha=hashlib.sha256(json.dumps(body,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    passed=all(row['eligible'] for row in rows)
    return {**body,'manifest_sha256':manifest_sha,
        'state':'source_revision_checks_passed' if passed else 'rejected',
        'bootstrap_observed':False,'execution_available':False,'indexing_triggered':False,
        'worker_started':False,'approval_required_for_indexing':False,
        'reason':'Current production flow is static complete-source reconciliation; committed selected topology is not observed'}


def register(mcp,config,read_annotations):
    @mcp.tool(annotations={**read_annotations,'title':'Plan revision-bound selected CDC','openWorldHint':True})
    async def docstore_selected_update_plan(request: SelectedUpdatePlan) -> dict:
        """Validate selected source bytes against current revisions; never starts indexing or proves bootstrap."""
        return await plan(config,request)
