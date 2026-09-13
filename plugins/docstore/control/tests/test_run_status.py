"""Worker receipt status is bounded, local and never promoted to CDC proof."""
from dataclasses import dataclass
from datetime import datetime,timezone,timedelta
import json

import pytest
from fastmcp.exceptions import ToolError

from run_status import read_runs


@dataclass
class Config:
    worker_receipts_dir: object=None


def receipt(directory,run_id,sequence,sync,**extra):
    value=dict(run_id=run_id,sequence=sequence,sync=sync,
        at=(datetime(2026,9,12,tzinfo=timezone.utc)+timedelta(seconds=sequence)).isoformat(),
        cdc_verified=False,receipt_kind='worker-execution-v1',**extra)
    (directory/f'{run_id}-{sequence:03d}.json').write_text(json.dumps(value))


def test_unconfigured_status_is_explicit_and_does_not_start_worker():
    result=read_runs(Config())
    assert result['configured'] is False and result['available'] is False
    assert result['worker_started'] is False and result['indexing_triggered'] is False


def test_complete_execution_is_still_unverified(tmp_path):
    run='a'*32
    receipt(tmp_path,run,0,'running')
    receipt(tmp_path,run,1,'running',ingest={'exit_code':0,'timed_out':False,
        'log_truncated':False,'output_bytes':20,'retained_bytes':20,'diagnostic_errors':[]})
    receipt(tmp_path,run,2,'execution_finished',seconds=4,
        ingest={'exit_code':0,'timed_out':False,'log_truncated':False,'output_bytes':20,'retained_bytes':20,'diagnostic_errors':[]},
        graph={'exit_code':0,'timed_out':False,'log_truncated':False,'output_bytes':10,'retained_bytes':10,'diagnostic_errors':[]},
        health={'document':3,'chunk':6,'links_to':0,'cites':0,'hnsw':'ready','orphan_chunks':0})
    result=read_runs(Config(tmp_path))
    row=result['runs'][0]
    assert row['status']=='execution_finished_unverified'
    assert row['sequence_complete'] is True and row['cdc_verified'] is False
    assert result['execution_receipt_is_not_cdc_proof'] is True
    assert row['stages']['ingest']['exit_code']==0
    assert 'log_path' not in str(result) and 'receipt_path' not in str(result)


def test_exact_attribution_is_reported_as_verified(tmp_path):
    run='e'*32
    proof={'status':'verified','missing_count':0,'unexpected_count':0,
           'hash_mismatch_count':0,'expected_documents':3,'observed_documents':3}
    receipt(tmp_path,run,0,'running')
    receipt(tmp_path,run,1,'execution_finished',cdc_attribution=proof)
    path=tmp_path/f'{run}-001.json'
    value=json.loads(path.read_text())
    value['cdc_verified']=True
    path.write_text(json.dumps(value))
    row=read_runs(Config(tmp_path),run_id=run)['runs'][0]
    assert row['cdc_verified'] is True
    assert row['cdc_attribution']['status']=='verified'


def test_running_receipt_is_incomplete(tmp_path):
    receipt(tmp_path,'b'*32,0,'running')
    assert read_runs(Config(tmp_path))['runs'][0]['status']=='incomplete'


def test_sequence_gap_is_reported(tmp_path):
    run='c'*32
    receipt(tmp_path,run,0,'running')
    receipt(tmp_path,run,2,'failed',error_type='SyntheticError')
    row=read_runs(Config(tmp_path),run_id=run)['runs'][0]
    assert row['sequence_complete'] is False and row['status']=='failed'


@pytest.mark.parametrize('change',[
    {'cdc_verified':True},{'receipt_kind':'wrong'},{'run_id':'f'*32},
    {'sequence':9},{'sync':'success'},{'at':'not-a-date'}])
def test_invalid_receipt_fails_closed(tmp_path,change):
    run='d'*32
    value=dict(run_id=run,sequence=0,sync='running',at=datetime.now(timezone.utc).isoformat(),
               cdc_verified=False,receipt_kind='worker-execution-v1')
    value.update(change)
    (tmp_path/f'{run}-000.json').write_text(json.dumps(value))
    with pytest.raises(ToolError): read_runs(Config(tmp_path))


def test_nonmatching_files_are_ignored(tmp_path):
    (tmp_path/'not-a-receipt.txt').write_text('untrusted')
    result=read_runs(Config(tmp_path))
    assert result['available'] is True and result['runs']==[]
