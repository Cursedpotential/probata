"""Selected-update planning is revision-bound and never executes indexing."""
import hashlib
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastmcp.exceptions import ToolError

from admission import SelectedFile, SelectedUpdatePlan, plan, worker_document_id
from revisions import document_id, revision_id
from verification import fingerprint


def request(content,**changes):
    raw=hashlib.sha256(content).hexdigest()
    item=dict(document_key='note:synthetic',source_path='docs/note.md',
              expected_generation=1,expected_revision_number=1,expected_raw_sha256=raw)
    item.update(changes)
    return SelectedUpdatePlan(files=[SelectedFile(**item)])


def config(tmp_path,content=b'# Synthetic\n'):
    root=tmp_path/'docs'
    root.mkdir()
    (root/'note.md').write_bytes(content)
    return SimpleNamespace(source_root=root,instance='docstore-test'),content


def executor(content,**head_changes):
    raw=hashlib.sha256(content).hexdigest()
    projected=fingerprint(content)
    head=dict(id=document_id('note:synthetic'),document_key='note:synthetic',
              source_path='docs/note.md',title='Synthetic',generation=1,latest_number=1,
              current_revision=revision_id('note:synthetic',1),current_hash=raw,
              approved_revision=None)
    head.update(head_changes)
    revision=dict(id=revision_id('note:synthetic',1),number=1,raw_sha256=raw,
                  projection_sha256=projected,projection_profile='docstore-fold-non-bmp-v1',
                  source_path='docs/note.md')
    async def execute(_config,_sql,_params):
        return dict(head=head,revisions=[revision],approvals=[],aliases=[],events=[],approved_content=None)
    return execute


@pytest.mark.asyncio
async def test_plan_passes_checks_but_never_claims_execution_or_bootstrap(tmp_path):
    cfg,content=config(tmp_path)
    result=await plan(cfg,request(content),execute=executor(content))
    assert result['state']=='source_revision_checks_passed'
    assert result['files'][0]['eligible'] is True
    assert result['files'][0]['approval_status']=='unapproved'
    assert result['approval_required_for_indexing'] is False
    assert result['execution_available'] is False
    assert result['bootstrap_observed'] is False
    assert result['indexing_triggered'] is False
    assert result['worker_started'] is False
    assert len(result['manifest_sha256'])==64
    assert result['worker_identity']['candidate_only'] is True
    assert 'body' not in str(result)


@pytest.mark.asyncio
async def test_stale_generation_is_explicit_rejection(tmp_path):
    cfg,content=config(tmp_path)
    result=await plan(cfg,request(content,expected_generation=2),execute=executor(content))
    assert result['state']=='rejected'
    assert result['files'][0]['issues']==['generation_mismatch']


@pytest.mark.asyncio
async def test_source_hash_change_is_rejected(tmp_path):
    cfg,content=config(tmp_path)
    old=b'# Older\n'
    result=await plan(cfg,request(old),execute=executor(old))
    assert result['state']=='rejected'
    assert 'source_raw_hash_mismatch' in result['files'][0]['issues']


@pytest.mark.asyncio
async def test_missing_logical_document_reports_root_cause_only(tmp_path):
    cfg,content=config(tmp_path)
    async def execute(_config,_sql,_params):
        return dict(head=None,revisions=[],approvals=[],aliases=[],events=[],approved_content=None)
    result=await plan(cfg,request(content),execute=execute)
    assert result['files'][0]['issues']==['logical_document_missing']


@pytest.mark.parametrize('path',['docs/private/a.md','docs/to_be_deleted/a.md',
                                  'docs/a/to_be_deleted/b.md','docs/a.txt','docs/../a.md'])
def test_worker_exclusions_and_noncanonical_paths_rejected(path):
    with pytest.raises(Exception):
        SelectedFile(document_key='note:x',source_path=path,expected_generation=1,
                     expected_revision_number=1,expected_raw_sha256='0'*64)


@pytest.mark.asyncio
async def test_duplicate_keys_rejected_before_read(tmp_path):
    cfg,content=config(tmp_path)
    item=request(content).files[0]
    with pytest.raises(ToolError,match='Duplicate'):
        await plan(cfg,SelectedUpdatePlan(files=[item,item]),execute=executor(content))


@pytest.mark.asyncio
async def test_selected_worker_id_collision_rejected_before_read(tmp_path):
    cfg,content=config(tmp_path)
    stem='a'*121
    first=SelectedFile(document_key='note:first',source_path='docs/'+stem+'1.md',
        expected_generation=1,expected_revision_number=1,expected_raw_sha256='0'*64)
    second=SelectedFile(document_key='note:second',source_path='docs/'+stem+'2.md',
        expected_generation=1,expected_revision_number=1,expected_raw_sha256='0'*64)
    with pytest.raises(ToolError,match='colliding selected worker_document_id'):
        await plan(cfg,SelectedUpdatePlan(files=[first,second]),execute=executor(content))


def test_worker_document_id_matches_current_slug_contract():
    assert worker_document_id('docs/A B.md')=='document:docs_a_b_md'
