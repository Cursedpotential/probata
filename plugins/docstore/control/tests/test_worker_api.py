"""HTTP worker-control contract without launching CocoIndex or touching a store."""
import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

fastapi=pytest.importorskip('fastapi')
from fastapi.testclient import TestClient


PIPELINE=Path(__file__).resolve().parents[4]/'scripts/docstore'
sys.path.insert(0,str(PIPELINE))
spec=importlib.util.spec_from_file_location('docstore_worker_api_test',PIPELINE/'api.py')
api=importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)


class Process:
    def __init__(self,*args,**kwargs):
        self.args=args
        self.kwargs=kwargs
        self.returncode=None
        self.terminated=False
    def poll(self): return self.returncode
    def terminate(self): self.terminated=True


def test_selected_request_runs_complete_source_and_can_cancel(tmp_path,monkeypatch):
    api._jobs.clear()
    monkeypatch.setattr(api,'RUN_RECEIPTS',tmp_path/'runs')
    monkeypatch.setattr(api.subprocess,'Popen',Process)
    client=TestClient(api.app)
    response=client.post('/runs',json={'scope':'selected','paths':['docs/note.md']})
    assert response.status_code==202
    value=response.json()
    assert value['full_source_reconciliation'] is True
    assert value['selected_paths_are_verification_targets'] is True
    process=api._jobs[value['run_id']]
    assert process.kwargs['env']['DOCSTORE_REQUESTED_PATHS']=='docs/note.md'
    assert client.delete('/runs/'+value['run_id']).status_code==202
    assert process.terminated is True


def test_unsafe_selected_requests_fail_before_launch(monkeypatch):
    api._jobs.clear()
    monkeypatch.setattr(api.subprocess,'Popen',lambda *a,**k: (_ for _ in ()).throw(AssertionError('launched')))
    client=TestClient(api.app)
    for paths in ([],['../secret.md'],['docs/a.md','docs/a.md']):
        response=client.post('/runs',json={'scope':'selected','paths':paths})
        assert response.status_code==400
