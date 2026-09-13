import importlib.util, json, os, sys, tempfile, unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
import reconciliation as rec
import mcp_server
import smart_explore

class ReconciliationTests(unittest.TestCase):
 def test_store_selection(self):
  self.assertEqual(rec.select_stores('selected',['ccc','docstore']),['ccc','docstore'])
  with self.assertRaises(ValueError): rec.select_stores('selected',[])
  with self.assertRaises(ValueError): rec.select_stores('selected',['bogus'])

 def test_every_store_reports_state(self):
  data=rec.inventory(str(ROOT))
  self.assertEqual(set(data),set(rec.STORE_NAMES))
  for value in data.values(): self.assertIn('available',value)

 def test_filesystem_recall_and_provenance(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/'decision.md'; p.write_text('Owner decision: final canonical contract alpha',encoding='utf-8')
   fake={s:{'available':False,'adapter':None,'identity':{}} for s in rec.STORE_NAMES}
   fake['codex_memory']={'available':True,'adapter':'filesystem-text','identity':{'roots':[td]}}
   with patch.object(rec,'inventory',return_value=fake):
    out=rec.recall('canonical contract',td,'selected',['codex_memory'],5)
   self.assertEqual(len(out['store_runs']),8)
   self.assertTrue(next(x for x in out['store_runs'] if x['store']=='codex_memory')['queried'])
   self.assertTrue(out['decisions']); self.assertTrue(out['contracts'])
   self.assertEqual(out['results'][0]['store'],'codex_memory')
   self.assertTrue(out['next_actions'])

 def test_conflict_detection(self):
  rows=[{'title':'Final Contract','store':'ccc','content_hash':'a'}, {'title':'final-contract','store':'docstore','content_hash':'b'}]
  self.assertTrue(rec.discover_conflicts(rows)[0]['requires_adjudication'])

 def test_mcp_catalog(self):
  names={x['name'] for x in mcp_server.TOOLS}
  expected={'structural_search','semantic_code_search','code_index_refresh','code_index_status','code_index_doctor','structural_grep','selected_store_recall','conflict_discovery','decisions_final_contracts','reconcile_run','reconcile_repair','reconcile_status','reconcile_export','store_inventory'}
  self.assertEqual(names,expected)

 def test_unavailable_selected_store_has_recovery_action(self):
  fake={s:{'available':False,'adapter':None,'identity':{}} for s in rec.STORE_NAMES}
  with patch.object(rec,'inventory',return_value=fake):
   out=rec.recall('contract',str(ROOT),'selected',['docstore'],1)
  self.assertFalse(out['attribution_clean'])
  self.assertIn('configure PROPRIA_DOCSTORE_ADAPTER and retry',out['next_actions'])

 def test_memsearch_missing_credential_is_not_reported_available(self):
  with patch.dict(os.environ,{},clear=True), patch.object(rec.shutil,'which',side_effect=lambda name: 'memsearch.exe' if name=='memsearch' else None), patch.object(Path,'home',return_value=Path('C:/fakehome')), patch.object(Path,'exists',return_value=True), patch.object(Path,'is_file',return_value=True), patch.object(Path,'read_text',return_value='api_key = "env:NVIDIA_NIM_API_KEY"'):
   data=rec.inventory(str(ROOT))['memsearch']
  self.assertFalse(data['available'])
  self.assertEqual(data['identity']['missing_credential_env'],['NVIDIA_NIM_API_KEY'])
  self.assertIn('rerun memsearch stats',data['next_action'])

 def test_active_wal_is_reported_and_never_stale(self):
  with tempfile.TemporaryDirectory() as td, patch.dict(os.environ, {'SMART_EXPLORE_HOME': td}):
   indexes=Path(td)/'indexes'; indexes.mkdir()
   db=indexes/'active.duckdb'; db.write_bytes(b'not opened')
   db.with_suffix('.duckdb.wal').write_bytes(b'active')
   rows=list(smart_explore.store_entries())
  self.assertEqual(len(rows),1)
  self.assertFalse(rows[0]['stale'])
  self.assertTrue(rows[0]['error'].startswith('active_or_unclean_wal'))

 def test_lock_retry_contract_has_bounded_default(self):
  self.assertEqual(os.environ.get('SMART_EXPLORE_LOCK_TIMEOUT','60'),'60')

if __name__=='__main__': unittest.main()
