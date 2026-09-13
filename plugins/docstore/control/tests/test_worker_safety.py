"""Worker safety without importing CocoIndex, reading corpus or contacting a store."""
import ast
import importlib.util
import json
import os
import sys
from pathlib import Path
from types import SimpleNamespace
from contextlib import asynccontextmanager

import pytest

PIPELINE = Path(__file__).resolve().parents[4] / 'scripts/docstore'
sys.path.insert(0, str(PIPELINE))
import run_support

spec=importlib.util.spec_from_file_location('docstore_worker_safety',PIPELINE/'worker_sync.py')
worker=importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


def test_lock_persists_and_can_be_reacquired(tmp_path):
    path=tmp_path/'sync.lock'
    with run_support.worker_lock(path):
        with pytest.raises(run_support.WorkerBusy):
            with run_support.worker_lock(path):
                pytest.fail('Overlap was allowed')
    assert path.read_bytes()==run_support.LOCK_MARKER
    with run_support.worker_lock(path):
        pass
    assert path.exists()


def test_legacy_lock_never_stolen_even_when_old(tmp_path):
    path=tmp_path/'sync.lock'
    path.write_bytes(b'')
    os.utime(path,(1,1))
    with pytest.raises(run_support.WorkerBusy):
        with run_support.worker_lock(path):
            pytest.fail('Legacy lock stolen')
    assert path.read_bytes()==b''


def test_receipts_append_never_overwrite_or_claim_cdc(tmp_path):
    p=run_support.write_receipt(tmp_path,'synthetic',0,{'sync':'running','cdc_verified':True})
    assert json.loads(p.read_text())['cdc_verified'] is False
    with pytest.raises(FileExistsError):
        run_support.write_receipt(tmp_path,'synthetic',0,{'sync':'done'})
    assert json.loads(p.read_text())['sync']=='running'


def test_current_status_is_atomic_bounded_and_never_claims_cdc(tmp_path):
    path=tmp_path/'latest-run.json'
    run_support.write_current_status(path,{'sync':'running','cdc_verified':True})
    first=json.loads(path.read_text())
    assert first['status_kind']==run_support.STATUS_KIND
    assert first['cdc_verified'] is False
    assert run_support.read_current_status(path)==first
    run_support.write_current_status(path,{'sync':'failed','error_type':'Synthetic'})
    assert json.loads(path.read_text())['sync']=='failed'
    assert not list(tmp_path.glob('*.tmp'))
    with pytest.raises(ValueError):
        run_support.write_current_status(path,{'sync':'failed','reason':'x'*65536})


@pytest.mark.parametrize('value',[
    {}, {'status_kind':run_support.STATUS_KIND,'sync':'success','cdc_verified':False},
    {'status_kind':run_support.STATUS_KIND,'sync':'failed','cdc_verified':True},
])
def test_current_status_invalid_schema_fails_closed(tmp_path,value):
    path=tmp_path/'latest-run.json'
    path.write_text(json.dumps(value))
    with pytest.raises(ValueError):
        run_support.read_current_status(path)


def test_child_log_is_bounded_and_retained(tmp_path,monkeypatch):
    monkeypatch.setattr(run_support,'MAX_LOG_BYTES',64)
    log=tmp_path/'child.log'
    result=run_support.run_child([sys.executable,'-c',"print('x'*200)"],dict(os.environ),10,log)
    assert result['exit_code']==0
    assert result['log_truncated'] is True
    assert log.stat().st_size==64
    assert not result['diagnostic_errors']


def test_child_timeout_is_not_success(tmp_path):
    result=run_support.run_child([sys.executable,'-c','import time; time.sleep(5)'],
                                dict(os.environ),0.05,tmp_path/'timeout.log')
    assert result['timed_out'] is True
    assert result['exit_code'] != 0


def setup_worker(tmp_path,monkeypatch):
    monkeypatch.delenv('DOCSTORE_ONLY_FILES',raising=False)
    monkeypatch.delenv('DOCSTORE_RUN_ID',raising=False)
    monkeypatch.delenv('DOCSTORE_REQUESTED_PATHS',raising=False)
    monkeypatch.setattr(worker,'LOCK',tmp_path/'sync.lock')
    monkeypatch.setattr(worker,'RECEIPTS',tmp_path/'runs')
    monkeypatch.setattr(worker,'STATUS',tmp_path/'latest-run.json')
    monkeypatch.setattr(worker,'snapshot_sources',lambda: ((SimpleNamespace(source_path='docs/note.md'),),'a'*64))
    async def verified(_snapshot):
        return {'status':'verified','missing_count':0,'unexpected_count':0,
                'hash_mismatch_count':0,'expected_documents':1,'observed_documents':1}
    monkeypatch.setattr(worker,'verify_projection',verified)


def test_partial_request_never_launches_worker(tmp_path,monkeypatch):
    setup_worker(tmp_path,monkeypatch)
    monkeypatch.setenv('DOCSTORE_ONLY_FILES','docs/one.md')
    monkeypatch.setattr(worker,'_run',lambda *a: pytest.fail('worker launched'))
    assert worker.main()==2
    assert not worker.LOCK.exists()


@pytest.mark.parametrize('mode',['ok','exit_error','timeout','log_error','unhealthy','exception'])
def test_worker_receipts_fail_closed(tmp_path,monkeypatch,mode):
    setup_worker(tmp_path,monkeypatch)
    calls=[]
    def run(script,timeout,log):
        calls.append(script)
        assert len(list(worker.RECEIPTS.glob('*.json'))) >= 1
        if mode=='exception': raise RuntimeError('private detail must not reach receipt')
        return {'exit_code':1 if mode=='exit_error' else 0,'timed_out':mode=='timeout',
                'diagnostic_errors':['capture'] if mode=='log_error' else [],'log_path':str(log)}
    async def health():
        return {'hnsw':'building' if mode=='unhealthy' else 'ready','orphan_chunks':0}
    monkeypatch.setattr(worker,'_run',run)
    monkeypatch.setattr(worker,'_health',health)
    assert worker.main()==(0 if mode=='ok' else 1)
    records=[json.loads(p.read_text()) for p in sorted(worker.RECEIPTS.glob('*.json'))]
    assert records[0]['sync']=='running'
    assert records[-1]['sync']==('execution_finished' if mode=='ok' else 'degraded' if mode=='unhealthy' else 'failed')
    assert all(r['cdc_verified'] is False for r in records[:-1])
    assert records[-1]['cdc_verified'] is (mode=='ok')
    current=json.loads(worker.STATUS.read_text())
    assert current['sync']==records[-1]['sync']
    assert current['cdc_verified'] is (mode=='ok')
    assert 'private detail' not in json.dumps(records)
    assert worker.LOCK.exists()
    if mode in {'exit_error','timeout','log_error','exception'}:
        assert calls==['flow_docs.py']


def test_receipt_failure_prevents_child_launch(tmp_path,monkeypatch):
    setup_worker(tmp_path,monkeypatch)
    def fail(*a): raise OSError('disk full')
    monkeypatch.setattr(worker,'write_receipt',fail)
    monkeypatch.setattr(worker,'_run',lambda *a:pytest.fail('child launched'))
    assert worker.main()==1


def test_status_failure_prevents_child_and_terminal_receipt_is_retained(tmp_path,monkeypatch):
    setup_worker(tmp_path,monkeypatch)
    monkeypatch.setattr(worker,'write_current_status',lambda *a: (_ for _ in ()).throw(OSError('disk full')))
    monkeypatch.setattr(worker,'_run',lambda *a:pytest.fail('child launched'))
    assert worker.main()==1
    records=[json.loads(p.read_text()) for p in sorted(worker.RECEIPTS.glob('*.json'))]
    assert [row['sync'] for row in records]==['running','failed']


def test_container_uses_python_supervisor_and_health_checks_body():
    root=PIPELINE.parents[1]
    dockerfile=(root/'deploy/docker/docstore-worker/Dockerfile').read_text(encoding='utf-8')
    compose=(root/'deploy/docstore-worker.yaml').read_text(encoding='utf-8')
    assert 'CMD ["python", "scripts/docstore/container_entrypoint.py"]' in dockerfile
    assert 'worker_sync.py & exec uvicorn' not in dockerfile
    assert "value.get('ok') is True" in compose
    assert 'DOCSTORE_RUN_STATUS: /data/state/latest-run.json' in compose
    assert ':8072:8000' in compose
    assert ':8474:8000' in compose
    assert ':8473:8000' not in compose
    assert 'wss://surreal-docs.tilapia-skilift.ts.net' in compose
    assert 'ws://100.91.190.107:8472' not in compose


def flow_function(name,globals):
    tree=ast.parse((PIPELINE/'flow_docs.py').read_text(encoding='utf-8'))
    node=next(n for n in tree.body if isinstance(n,ast.AsyncFunctionDef) and n.name==name)
    node.decorator_list=[]
    module=ast.Module(body=[ast.ImportFrom(module='__future__',names=[ast.alias(name='annotations')],level=0),node],type_ignores=[])
    ast.fix_missing_locations(module)
    exec(compile(module,'<isolated-flow-function>','exec'),globals)
    return globals[name]


@pytest.mark.parametrize('errors,progress,missing',[(0,0,False),(1,0,False),(0,1,False),(0,0,True)])
async def test_final_flow_stats_must_show_finished_without_errors(errors,progress,missing):
    @asynccontextmanager
    async def runtime(): yield
    async def result(): return None
    stats=None if missing else SimpleNamespace(total=SimpleNamespace(num_errors=errors,num_in_progress=progress))
    handle=SimpleNamespace(result=result,stats=lambda:stats)
    fn=flow_function('_run_checked',{'os':os, 'coco':SimpleNamespace(runtime=runtime),'app':SimpleNamespace(update=lambda **_kwargs:handle)})
    if missing or errors or progress:
        with pytest.raises(RuntimeError): await fn()
    else:
        await fn()


async def test_component_error_handler_propagates():
    fn=flow_function('_raise_component_error',{'sys':sys})
    with pytest.raises(ValueError): await fn(ValueError('synthetic'),None)


async def test_health_timeout_is_explicit(monkeypatch):
    async def health(): return {}
    async def timeout(coro, timeout):
        assert timeout==60
        coro.close()
        raise TimeoutError('synthetic')
    monkeypatch.setattr(worker,'_health',health)
    monkeypatch.setattr(worker.asyncio,'wait_for',timeout)
    with pytest.raises(TimeoutError): await worker._bounded_health()


def test_scope_guard_precedes_heavy_imports_and_children_are_awaited():
    text=(PIPELINE/'flow_docs.py').read_text(encoding='utf-8')
    assert text.index('if os.environ.get("DOCSTORE_ONLY_FILES"') < text.index('import cocoindex as coco')
    tree=ast.parse(text)
    main=next(n for n in tree.body if isinstance(n,ast.AsyncFunctionDef) and n.name=='app_main')
    assert 'await handle.ready()' in ast.unparse(main)
    assert 'coco.exception_handler(_raise_component_error)' in ast.unparse(main)
    checked=next(n for n in tree.body if isinstance(n,ast.AsyncFunctionDef) and n.name=='_run_checked')
    assert 'coco.runtime' not in ast.unparse(checked)
