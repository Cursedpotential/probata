"""Terminate only a synthetic child; verify retained SQLite targets and retry.

Run under the installed Docstore uv environment with a NEW E-drive proof directory.
No source corpus, network, models, infrastructure, file removals or live target.
"""
import argparse
import json
import os
from pathlib import Path
import queue
import sqlite3
import subprocess
import sys
import threading
import time


def snapshot(directory):
    target=directory/'target.sqlite'
    with sqlite3.connect(f'file:{target.as_posix()}?mode=ro',uri=True) as db:
        return {name:dict(db.execute(f'SELECT id,text FROM {name} ORDER BY id'))
                for name in ('synthetic_rows','synthetic_chunks')}


def main(directory):
    if directory.exists():
        raise RuntimeError('Require a new proof directory; never overwrite or clean one')
    if os.name=='nt' and directory.drive.upper()!='E:':
        raise RuntimeError('Synthetic proof output must be on E:')
    proof=Path(__file__).with_name('selected_components_proof.py')
    base=[sys.executable,str(proof),str(directory)]
    flags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0
    def run(phase,*extra):
        result=subprocess.run(base+[phase,'--with-chunks',*extra],
            capture_output=True,text=True,timeout=60,creationflags=flags)
        if result.returncode:
            raise RuntimeError(f'Synthetic {phase} failed with exit {result.returncode}')
        return result.stdout
    baseline_output=run('bootstrap','--expect-bootstrap','1')
    baseline=snapshot(directory)
    child=subprocess.Popen(base+['guard-first','--with-chunks','--gate-before-commit'],
        stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,creationflags=flags)
    lines=queue.Queue(maxsize=128)
    def drain():
        for line in child.stdout:
            try: lines.put_nowait(line[:4096])
            except queue.Full: pass
    reader=threading.Thread(target=drain,daemon=True)
    reader.start()
    transcript=[]
    gate=False
    deadline=time.monotonic()+45
    try:
        while time.monotonic()<deadline:
            try: line=lines.get(timeout=0.25)
            except queue.Empty:
                if child.poll() is not None: break
                continue
            transcript.append(line)
            if line.strip()=='DOCSTORE_SYNTHETIC_BEFORE_COMMIT':
                gate=True
                break
    finally:
        if child.poll() is None:
            child.kill()  # Only the subprocess created above, never other workers.
        child.wait(timeout=10)
        reader.join(timeout=5)
        if not reader.is_alive(): child.stdout.close()
    if not gate:
        raise RuntimeError('Synthetic gate was not reached; cancellation proof inconclusive')
    after_interrupt=snapshot(directory)
    if after_interrupt!=baseline:
        raise AssertionError('Interrupted component changed targets; inspect retained proof database')
    retry_output=run('guard-first')
    final=snapshot(directory)
    report=dict(status='synthetic_interruption_retention_and_retry_passed',
        interrupted_run_status='interrupted_not_success',baseline=baseline,
        after_interrupt=after_interrupt,after_retry=final,
        bootstrap_output=baseline_output,child_gate_output=transcript,retry_output=retry_output,
        source_files=0,model_calls=0,cdc_verified=False)
    with (directory/'interruption-receipt.json').open('x',encoding='utf-8') as out:
        json.dump(report,out,indent=2)
    print(json.dumps({'status':report['status'],'proof_directory':str(directory),'cdc_verified':False}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path)
    args=parser.parse_args()
    main(args.directory.resolve())
