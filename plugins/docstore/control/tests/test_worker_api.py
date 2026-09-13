"""HTTP worker-control contract without launching CocoIndex or touching a store."""
import importlib.util
import json
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
    assert value['full_reprocess'] is False
    process=api._jobs[value['run_id']]
    assert process.kwargs['env']['DOCSTORE_REQUESTED_PATHS']=='docs/note.md'
    assert client.delete('/runs/'+value['run_id']).status_code==202
    assert process.terminated is True


def test_explicit_drift_repair_enables_cocoindex_full_reprocess(tmp_path,monkeypatch):
    api._jobs.clear()
    monkeypatch.setattr(api,'RUN_RECEIPTS',tmp_path/'runs')
    monkeypatch.setattr(api.subprocess,'Popen',Process)
    client=TestClient(api.app)
    response=client.post('/runs',json={'scope':'full','paths':[],'full_reprocess':True})
    assert response.status_code==202
    value=response.json()
    assert value['full_reprocess'] is True
    assert api._jobs[value['run_id']].kwargs['env']['DOCSTORE_FULL_REPROCESS']=='1'


def test_unsafe_selected_requests_fail_before_launch(monkeypatch):
    api._jobs.clear()
    monkeypatch.setattr(api.subprocess,'Popen',lambda *a,**k: (_ for _ in ()).throw(AssertionError('launched')))
    client=TestClient(api.app)
    for paths in ([],['../secret.md'],['docs/a.md','docs/a.md']):
        response=client.post('/runs',json={'scope':'selected','paths':paths})
        assert response.status_code==400


def test_run_history_returns_latest_valid_receipt_per_run(tmp_path,monkeypatch):
    run_a='a'*32
    run_b='b'*32
    monkeypatch.setattr(api,'RUN_RECEIPTS',tmp_path/'runs')
    api.RUN_RECEIPTS.mkdir()
    base={'receipt_kind':'worker-execution-v1','sync':'execution_finished','cdc_verified':False}
    (api.RUN_RECEIPTS/f'{run_a}-000.json').write_text(json.dumps({**base,'run_id':run_a,'at':'2026-01-01'}))
    (api.RUN_RECEIPTS/f'{run_a}-001.json').write_text(json.dumps({**base,'run_id':run_a,'at':'2026-01-03'}))
    (api.RUN_RECEIPTS/f'{run_b}-000.json').write_text(json.dumps({**base,'run_id':run_b,'at':'2026-01-02'}))
    value=TestClient(api.app).get('/runs?limit=2').json()
    assert [row['run_id'] for row in value['runs']]==[run_a,run_b]


def test_fresh_attribution_is_exposed_read_only(monkeypatch):
    source=(SimpleNamespace(source_path='docs/note.md'),)
    monkeypatch.setattr(api,'snapshot_sources',lambda:(source,'d'*64))
    async def verified(_source):
        return {'status':'verified','expected_documents':1,'observed_documents':1,
                'missing_count':0,'unexpected_count':0,'hash_mismatch_count':0}
    monkeypatch.setattr(api,'verify_projection',verified)
    value=TestClient(api.app).get('/attribution').json()
    assert value['cdc_verified'] is True
    assert value['source_digest']=='d'*64


def test_graph_preview_is_bounded_and_does_not_query_store():
    client=TestClient(api.app)
    value=client.get('/graph-query',params={'ref':'ADR-0001','relations':'cites',
                     'direction':'both','limit':7,'depth':1,'format':'graphml','preview':'true'}).json()
    assert value['executed'] is False
    assert value['preview']['maximum_edges_returned']==14
    assert value['preview']['read_only'] is True
    assert client.get('/graph-query',params={'ref':'x','relations':'delete','preview':'true'}).status_code==400
    assert client.get('/graph-query',params={'ref':'x','depth':2,'preview':'true'}).status_code==422


def test_graph_inline_exports_cover_json_csv_graphml_and_mermaid():
    doc={'source_path':'docs/a.md','title':'A'}
    edges=[{'edge':'cites','dir':'out','detail':'adr','path':'docs/b.md','title':'B','observed_at':None}]
    assert api.graph_query.export_graph(doc,edges,'json')['edges'][0]['edge']=='cites'
    csv_value=api.graph_query.export_graph(doc,edges,'csv')
    assert 'docs/a.md' in csv_value['nodes_csv'] and 'cites' in csv_value['edges_csv']
    assert '<graphml' in api.graph_query.export_graph(doc,edges,'graphml')['graphml']
    assert 'graph LR' in api.graph_query.export_graph(doc,edges,'mermaid')['mermaid']
