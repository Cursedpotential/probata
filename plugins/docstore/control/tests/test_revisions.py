"""Bounded revision tool contracts; injected executor, no database or indexing."""
import hashlib

import pytest
from fastmcp.exceptions import ToolError
from pydantic import ValidationError

from revisions import CaptureRevision, ApproveRevision, capture, approve, state, document_id, revision_id
from verification import fingerprint


def revision(**changes):
    return CaptureRevision(**dict(dict(document_key='adr:synthetic', source_path='docs/test.md',
        title='Synthetic', body='A\r\n😀', expected_generation=0,
        actor='test', source_ref='synthetic://test'), **changes))


def approval(**changes):
    return ApproveRevision(**dict(dict(document_key='adr:synthetic', revision_number=1,
        raw_sha256='a'*64, expected_generation=1, actor='test', rationale='Synthetic only',
        source_ref='synthetic://test', request_key='test-request'), **changes))


def head(**changes):
    item = revision()
    return dict(dict(id=document_id(item.document_key),document_key=item.document_key,
        source_path=item.source_path,title=item.title,generation=1,latest_number=1,
        current_revision=revision_id(item.document_key,1),
        current_hash=hashlib.sha256(item.body.encode()).hexdigest()), **changes)


def approval_row(params):
    return {'id':'docstore_approval:'+hashlib.sha256((params['key']+':'+params['request_key']).encode()).hexdigest(),
        'document':document_id(params['key']), 'revision':revision_id(params['key'],params['number']),
        'raw_sha256':params['hash'],'request_hash':params['request_hash'],
        'actor':params['actor'],'rationale':params['rationale'],'source_ref':params['source_ref']}


@pytest.mark.parametrize('path', ['/docs/a.md', 'docs/../a.md', 'docs//a.md',
    'docs/./a.md', 'docs\\a.md', 'other/a.md', 'docs/a.md:stream'])
def test_capture_rejects_noncanonical_paths(path):
    with pytest.raises(ValidationError):
        revision(source_path=path)


def test_capture_bounds_utf8_bytes_not_only_characters():
    with pytest.raises(ValidationError):
        revision(body='😀' * (1024*1024//4+1))
    assert revision(body='').body == ''


async def test_capture_bound_query_and_distinct_hash_profiles():
    item = revision(body="quoted '; THROW 'x';\r\n😀")
    async def execute(config, sql, params):
        assert item.body not in sql
        assert 'BEGIN TRANSACTION' in sql and 'COMMIT TRANSACTION' in sql
        assert params['projection_hash'] == fingerprint(item.body.encode())
        assert params['projection_hash'] != hashlib.sha256(item.body.encode()).hexdigest()
        return {'head': head(current_hash=hashlib.sha256(item.body.encode()).hexdigest()), 'unchanged': False}
    result = await capture(None, item, execute)
    assert result['indexing_triggered'] is False
    assert result['search_projection_updated'] is False


async def test_capture_rejects_unverified_response():
    async def execute(*args):
        return {'head': {'document_key': 'adr:other'}}
    with pytest.raises(ToolError):
        await capture(None, revision(), execute)


async def test_approval_retry_fingerprint_excludes_generation():
    hashes = []
    async def execute(config, sql, params):
        assert 'fn::docstore_approve_revision' in sql
        hashes.append(params['request_hash'])
        return {'approval': approval_row(params)}
    await approve(None, approval(), execute)
    await approve(None, approval(expected_generation=3), execute)
    await approve(None, approval(rationale='Different request payload'), execute)
    assert hashes[0] == hashes[1] != hashes[2]


@pytest.mark.parametrize('current,status', [
    (None, 'document_missing'), (head(), 'unapproved'),
    (head(approved_revision=revision_id('adr:synthetic',1)), 'approved_current'),
    (head(latest_number=2,current_revision=revision_id('adr:synthetic',2),
          approved_revision=revision_id('adr:synthetic',1)), 'changed_since_approval'),
])
async def test_state_separates_approval_from_index_freshness(current, status):
    async def execute(config, sql, params):
        assert 'LIMIT 21' in sql
        return {'head':current, 'revisions':[{'number':n} for n in range(21)],
                'approvals':[], 'aliases':[], 'events':[], 'approved_content':{
                    'document':document_id('adr:synthetic'),'id':revision_id('adr:synthetic',1),
                    'number':1,'raw_sha256':head()['current_hash']}}
    result = await state(None, 'adr:synthetic', execute)
    assert result['approval_status'] == status
    assert result['projection_status'] == 'unverified'
    assert result['cdc_execution'] == 'unproven'
    assert result['revisions_truncated'] is True
    assert len(result['revisions']) == 20


async def test_state_rejects_malformed_collections():
    async def execute(*args):
        return {'head':None,'revisions':None}
    with pytest.raises(ToolError):
        await state(None,'adr:synthetic',execute)


@pytest.mark.parametrize('bad', [None, [], 'bad', head(title='Wrong title'), head(id='docstore_document:wrong'), head(generation=True)])
async def test_capture_fails_closed_on_malformed_or_wrong_identity(bad):
    async def execute(*args):
        return {'head':bad,'unchanged':False}
    with pytest.raises(ToolError):
        await capture(None,revision(),execute)


@pytest.mark.parametrize('field', ['id','document','revision','actor','rationale','source_ref'])
async def test_approval_rejects_wrong_fields_even_with_matching_digest(field):
    async def execute(config,sql,params):
        row=approval_row(params)
        row[field]='wrong'
        return {'approval':row}
    with pytest.raises(ToolError):
        await approve(None,approval(),execute)


async def test_state_rejects_wrong_identity():
    async def execute(*args):
        return {'head':head(document_key='adr:other')}
    with pytest.raises(ToolError):
        await state(None,'adr:synthetic',execute)
