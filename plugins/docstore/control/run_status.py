"""Read bounded worker execution receipts; never starts, cancels or verifies CDC."""
from __future__ import annotations

from datetime import datetime
import json
from pathlib import Path
import re

from fastmcp.exceptions import ToolError
from pydantic import Field
from typing import Annotated


NAME=re.compile(r'^([a-f0-9]{32})-(\d{3})\.json$')
RUN_ID=re.compile(r'^[a-f0-9]{32}$')
MAX_FILES=5000
MAX_RECEIPT_BYTES=65536


def load_receipt(path,run_id,sequence):
    try:
        info=path.stat()
        if path.is_symlink() or getattr(info,'st_file_attributes',0)&(0x400|0x1000|0x40000|0x400000):
            raise ToolError('Worker receipt must be a local regular file')
        if not path.is_file() or info.st_size>MAX_RECEIPT_BYTES:
            raise ToolError('Worker receipt missing or oversized')
        with path.open('rb') as handle: raw=handle.read(MAX_RECEIPT_BYTES+1)
        if len(raw)>MAX_RECEIPT_BYTES: raise ToolError('Worker receipt grew beyond limit')
        value=json.loads(raw)
    except ToolError: raise
    except (OSError,ValueError): raise ToolError('Worker receipt unreadable or invalid') from None
    if (not isinstance(value,dict) or value.get('receipt_kind')!='worker-execution-v1'
            or value.get('run_id')!=run_id or type(value.get('sequence')) is not int
            or value['sequence']!=sequence or type(value.get('cdc_verified')) is not bool
            or value.get('sync') not in {'running','failed','degraded','cancelled','execution_finished'}):
        raise ToolError('Worker receipt identity or schema invalid')
    attribution=value.get('cdc_attribution')
    proven=(value.get('sync')=='execution_finished' and isinstance(attribution,dict)
            and attribution.get('status')=='verified'
            and attribution.get('missing_count')==0
            and attribution.get('unexpected_count')==0
            and attribution.get('hash_mismatch_count')==0)
    if value.get('cdc_verified') != proven:
        raise ToolError('Worker receipt CDC attribution is inconsistent')
    try:
        at=datetime.fromisoformat(value['at'])
        if at.tzinfo is None: raise ValueError
    except (KeyError,TypeError,ValueError):
        raise ToolError('Worker receipt timestamp invalid') from None
    return value,at


def summarize(run_id,events):
    events.sort(key=lambda item:item[0])
    sequences=[x[0] for x in events]
    latest=events[-1][1]
    stages={}
    for stage in ('ingest','graph'):
        value=latest.get(stage)
        if isinstance(value,dict):
            stages[stage]={key:value.get(key) for key in
                ('exit_code','timed_out','log_truncated','output_bytes','retained_bytes','diagnostic_errors')}
    status=latest['sync']
    if status=='running': status='incomplete'
    elif status=='execution_finished': status='execution_finished_unverified'
    health=latest.get('health') if isinstance(latest.get('health'),dict) else None
    if health is not None:
        health={key:health.get(key) for key in ('document','chunk','links_to','cites','hnsw','orphan_chunks')}
    return {'run_id':run_id,'status':status,'receipt_count':len(events),
        'sequence_complete':sequences==list(range(sequences[-1]+1)),
        'latest_sequence':sequences[-1],'started_at':events[0][2].isoformat(),
        'latest_at':events[-1][2].isoformat(),'seconds':latest.get('seconds'),
        'error_type':latest.get('error_type'),'stages':stages,'health':health,
        'cdc_verified':latest.get('cdc_verified',False),
        'cdc_attribution':latest.get('cdc_attribution')}


def read_runs(config,run_id=None,limit=20):
    directory=config.worker_receipts_dir
    if directory is None:
        return {'configured':False,'available':False,'runs':[],'truncated':False,
            'worker_started':False,'indexing_triggered':False,
            'reason':'DOCSTORE_WORKER_RECEIPTS_DIR is not configured'}
    if run_id is not None and not RUN_ID.fullmatch(run_id):
        raise ToolError('Exact lowercase worker run ID required')
    if not directory.exists():
        return {'configured':True,'available':False,'runs':[],'truncated':False,
            'worker_started':False,'indexing_triggered':False,
            'reason':'Configured worker receipt directory does not exist'}
    try: directory_info=directory.stat()
    except OSError: raise ToolError('Worker receipt directory unavailable') from None
    if (directory.is_symlink() or getattr(directory_info,'st_file_attributes',0)&0x400
            or not directory.is_dir()):
        raise ToolError('Worker receipt location is not a local directory')
    groups={}
    matched=0
    try:
        for path in directory.iterdir():
            match=NAME.fullmatch(path.name)
            if not match or (run_id is not None and match.group(1)!=run_id): continue
            matched+=1
            if matched>MAX_FILES: raise ToolError('Too many worker receipts; request an exact run ID')
            sequence=int(match.group(2))
            value,at=load_receipt(path,match.group(1),sequence)
            groups.setdefault(match.group(1),[]).append((sequence,value,at))
    except OSError: raise ToolError('Worker receipt directory unavailable') from None
    runs=[summarize(key,events) for key,events in groups.items()]
    runs.sort(key=lambda row:row['latest_at'],reverse=True)
    return {'configured':True,'available':True,'runs':runs[:limit],
        'truncated':len(runs)>limit,'worker_started':False,'indexing_triggered':False,
        'execution_receipt_is_not_cdc_proof':True}


def register(mcp,config,read_annotations):
    @mcp.tool(annotations={**read_annotations,'title':'Read Docstore worker runs','openWorldHint':False})
    def docstore_cdc_runs(
        run_id: Annotated[str | None,Field(pattern=r'^[a-f0-9]{32}$')]=None,
        limit: Annotated[int,Field(ge=1,le=50)]=20) -> dict:
        """Read bounded append-only worker receipts; execution completion is not per-document CDC proof."""
        return read_runs(config,run_id,limit)
