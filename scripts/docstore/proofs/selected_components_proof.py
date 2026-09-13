"""Real CocoIndex/SQLite proof, tiny synthetic rows only; never imports flow_docs.

Run each phase in a separate process with the SAME explicit proof directory.
No corpus, model, network database, drops, or cleanup operations. Retains proof DBs.
"""
import argparse
import asyncio
import json
import pathlib
import sqlite3
import sys
from dataclasses import dataclass

import cocoindex as coco
from cocoindex.connectors import sqlite

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from selected_identity import SelectedBootstrapIdentity
from selected_components import SelectedComponentUpdates, CommittedSelectedComponentUpdates

DB=coco.ContextKey[sqlite.ManagedConnection]('docstore_synthetic_selected_target')
BOOTSTRAP_CALLS=0
PROCESSED_KEYS=[]
GATE_BEFORE_COMMIT=False
PROOF_MARKER=SelectedBootstrapIdentity(app='DocstoreSelectedProof',environment='docstore-selected-proof',
    topology='synthetic-documents-chunks-v1',source='synthetic-three-rows-v1',
    tracking='isolated-proof-tracking-directory-v1',
    target='isolated-sqlite-synthetic-rows-chunks-v1',processing_profile='synthetic-no-model-v1').digest()


@dataclass
class Row:
    id: str
    text: str


@coco.fn(memo=True)
async def process_file(row: Row, table, chunks=None):
    PROCESSED_KEYS.append(row.id)
    if row.text=='FAIL': raise ValueError('Synthetic failed transform')
    table.declare_row(row=row)
    if chunks is not None:
        for index,text in enumerate(chunk_texts(row.text)):
            chunks.declare_row(row=Row(f'{row.id}:{index}',text))
    if GATE_BEFORE_COMMIT and row.id=='alpha' and row.text=='updated-alpha':
        print('DOCSTORE_SYNTHETIC_BEFORE_COMMIT',flush=True)
        await asyncio.Event().wait()


def chunk_texts(text):
    return [text,'second-original-chunk'] if text.startswith('original-') else [text]


async def strict(exc,ctx): raise exc


class BootstrappedUpdates(SelectedComponentUpdates):
    """Proof-only complete bootstrap; never treats selected items as a snapshot."""
    async def process(self):
        global BOOTSTRAP_CALLS
        BOOTSTRAP_CALLS+=1
        for key in ('alpha','beta','gamma'):
            handle=await coco.mount(coco.component_subpath(key),self.processor,
                Row(key,'original-'+key),*self.args)
            await handle.ready()

    async def process_live(self,operator):
        if await operator.read_committed_state('proof-bootstrap') != PROOF_MARKER:
            await operator.update_full()
        await operator.mark_ready()
        await operator.write_committed_state('proof-bootstrap',PROOF_MARKER)
        for key,value in self.items:
            handle=await operator.update(coco.component_subpath(key),self.processor,value,*self.args)
            await handle.ready()


@coco.fn
async def root(phase: str, with_chunks: bool):
    table=await sqlite.mount_table_target(DB,'synthetic_rows',
        await sqlite.TableSchema.from_class(Row,primary_key=['id']))
    chunks=(await sqlite.mount_table_target(DB,'synthetic_chunks',
        await sqlite.TableSchema.from_class(Row,primary_key=['id']))) if with_chunks else None
    async with coco.exception_handler(strict):
        guarded=phase.startswith('guard-')
        phase=phase.replace('guard-','boot-')
        if phase=='seed':
            h=await coco.mount_each(process_file,[(key,Row(key,'original-'+key)) for key in ('alpha','beta','gamma')],table,chunks)
        else:
            key='beta' if phase in ('second','boot-second') else 'alpha'
            text='FAIL' if phase in ('failure','boot-failure') else 'updated-'+key
            items=([(key,Row(key,'original-'+key)) for key in ('alpha','beta','gamma')]
                   if phase in ('live-seed','bootstrap') else [(key,Row(key,text))])
            if guarded:
                h=await coco.mount(coco.component_subpath(coco.Symbol('process_file')),
                    CommittedSelectedComponentUpdates,
                    'missing-bootstrap' if phase=='boot-missing' else 'proof-bootstrap',
                    ('0'*64) if phase=='boot-mismatch' else PROOF_MARKER,
                    process_file,items,table,chunks)
            else:
                h=await coco.mount(coco.component_subpath(coco.Symbol('process_file')),
                    BootstrappedUpdates if phase.startswith('boot') else SelectedComponentUpdates,
                    process_file,items,table,chunks)
        await h.ready()


async def main(directory,phase,expect_bootstrap,with_chunks):
    directory.mkdir(parents=True,exist_ok=True)
    target=directory/'target.sqlite'
    if phase in ('seed','live-seed','bootstrap') and target.exists():
        raise RuntimeError('Seed requires a fresh proof directory; never overwrite prior proof')
    if phase not in ('seed','live-seed','bootstrap') and not target.exists():
        raise RuntimeError('Seed proof must exist')
    env=coco.Environment(coco.Settings.from_env(db_path=directory/'tracking'),name='docstore-selected-proof')
    connection=sqlite.connect(target,load_vec=False)
    env.context_provider.provide(DB,connection)
    app=coco.App(coco.AppConfig(name='DocstoreSelectedProof',environment=env,max_inflight_components=1),root,phase=phase,with_chunks=with_chunks)
    h=app.update(live=phase.startswith(('boot','guard-')))
    phase=phase.replace('guard-','boot-')
    rejected=False
    try: await asyncio.wait_for(h.result(),30)
    except TimeoutError:
        raise RuntimeError('Proof exceeded its 30 second execution bound') from None
    except Exception:
        if phase not in ('failure','boot-failure','boot-missing','boot-mismatch'): raise
        rejected=True
    stats=h.stats()
    assert stats is not None
    # Live failures after readiness can be reported in statistics without
    # propagating from result(). A finished await is not a success receipt.
    rejected=rejected or stats.total.num_errors > 0
    assert rejected==(phase in ('failure','boot-failure','boot-missing','boot-mismatch'))
    if not rejected: assert stats.total.num_errors==0 and stats.total.num_in_progress==0
    connection.close()
    with sqlite3.connect(f'file:{target.as_posix()}?mode=ro',uri=True) as db:
        rows=dict(db.execute('SELECT id,text FROM synthetic_rows ORDER BY id'))
        chunk_rows=dict(db.execute('SELECT id,text FROM synthetic_chunks ORDER BY id')) if with_chunks else None
    expected={'alpha':'original-alpha','beta':'original-beta','gamma':'original-gamma'}
    if phase not in ('seed','live-seed','bootstrap'): expected['alpha']='updated-alpha'
    if phase in ('second','failure','retry','boot-second','boot-failure','boot-retry','boot-missing','boot-mismatch'): expected['beta']='updated-beta'
    print(json.dumps({'phase':phase,'rows':rows,'errors':stats.total.num_errors,
        'deletes':stats.total.num_deletes,'proof_directory':str(directory),'source_files':0,'model_calls':0,
        'bootstrap_calls':BOOTSTRAP_CALLS,'processed_keys':PROCESSED_KEYS,'chunk_rows':chunk_rows}))
    assert rows==expected,(phase,rows,expected)
    if with_chunks:
        expected_chunks={f'{key}:{i}':chunk for key,text in expected.items()
                         for i,chunk in enumerate(chunk_texts(text))}
        assert chunk_rows==expected_chunks,(chunk_rows,expected_chunks)
    assert BOOTSTRAP_CALLS==expect_bootstrap,(BOOTSTRAP_CALLS,expect_bootstrap)
    if phase.startswith('boot-') and expect_bootstrap==0:
        allowed={'beta'} if phase=='boot-second' else {'alpha'}
        assert set(PROCESSED_KEYS)<=allowed,PROCESSED_KEYS


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('directory',type=pathlib.Path)
    p.add_argument('phase',choices=['seed','live-seed','first','second','failure','retry',
        'bootstrap','boot-first','boot-second','boot-failure','boot-retry',
        'guard-first','guard-second','guard-failure','guard-retry','guard-missing','guard-mismatch'])
    p.add_argument('--expect-bootstrap',type=int,choices=[0,1],default=0)
    p.add_argument('--with-chunks',action='store_true')
    p.add_argument('--gate-before-commit',action='store_true',help='Synthetic supervisor test only')
    a=p.parse_args()
    GATE_BEFORE_COMMIT=a.gate_before_commit
    asyncio.run(main(a.directory,a.phase,a.expect_bootstrap,a.with_chunks))
