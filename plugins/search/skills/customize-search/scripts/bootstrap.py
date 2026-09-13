#!/usr/bin/env python3
import argparse, datetime, hashlib, json, os, shutil, subprocess, sys
from pathlib import Path

EXCLUDE_DIRS={'.git','.venv','__pycache__','receipts','to_be_deleted'}
EXCLUDE_SUFFIXES={'.pyc','.duckdb','.wal','.db','.sqlite','.sqlite3'}
STORE_NAMES={'smart_explore','ccc','docstore','codex_memory','claude_memory','cnf','remember','memsearch'}
CODE_SETTINGS="""exclude_patterns:
- '**/.*'
- '**/__pycache__'
- '**/node_modules'
- '**/target'
- '**/dist'
- '**/docs/**'
- '**/doc/**'
- '**/documentation/**'
- '**/knowledge/**'
- '**/memory/**'
- '**/.remember/**'
- '**/.memories/**'
- '**/to_be_deleted/**'
include_patterns:
- '**/*.py'
- '**/*.pyi'
- '**/*.js'
- '**/*.jsx'
- '**/*.ts'
- '**/*.tsx'
- '**/*.mjs'
- '**/*.cjs'
- '**/*.rs'
- '**/*.go'
- '**/*.java'
- '**/*.c'
- '**/*.h'
- '**/*.cpp'
- '**/*.hpp'
- '**/*.cs'
- '**/*.sql'
- '**/*.sh'
- '**/*.lua'
- '**/*.rb'
- '**/*.swift'
- '**/*.kt'
- '**/*.svelte'
- '**/*.vue'
- '**/*.css'
- '**/*.scss'
- '**/*.json'
- '**/*.xml'
- '**/*.yaml'
"""

def emit(value):
    print(json.dumps(value,indent=2))

def package_files(source):
    for p in sorted(source.rglob('*')):
        rel=p.relative_to(source)
        if any(part in EXCLUDE_DIRS for part in rel.parts): continue
        if p.is_file() and p.suffix.lower() not in EXCLUDE_SUFFIXES: yield p,rel

def package_hash(source):
    h=hashlib.sha256()
    for p,rel in package_files(source):
        h.update(rel.as_posix().encode());h.update(b'\0');h.update(p.read_bytes());h.update(b'\0')
    return h.hexdigest().upper()

def git_state(source):
    rev=subprocess.run(['git','-C',str(source),'rev-parse','HEAD'],text=True,capture_output=True)
    status=subprocess.run(['git','-C',str(source),'status','--porcelain'],text=True,capture_output=True)
    return (rev.stdout.strip() if rev.returncode==0 else 'unversioned',
            bool(status.stdout.strip()) if status.returncode==0 else None)

def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',',':')).encode()

def load_json(path):
    return json.loads(path.read_text(encoding='utf-8'))

def preserve(path, quarantine):
    if not path.exists(): return None
    quarantine.mkdir(parents=True,exist_ok=True)
    dst=quarantine/path.name
    if dst.exists(): raise RuntimeError(f'quarantine collision: {dst}')
    shutil.move(str(path),str(dst))
    return str(dst)

def customize_instance(plugin, runtime_env):
    cmd=plugin/'search.cmd';text=cmd.read_text(encoding='utf-8')
    text=text.replace(r'E:\AI_Workspace\Projects\Propria\.runtime\search\env',str(runtime_env))
    cmd.write_text(text,encoding='utf-8')
    bash=plugin/'search';text=bash.read_text(encoding='utf-8')
    text=text.replace('/e/AI_Workspace/Projects/Propria/.runtime/search/env',str(runtime_env).replace('\\','/'))
    bash.write_text(text,encoding='utf-8')
    manifest=load_json(plugin/'.mcp.json')
    manifest['mcpServers']['propria-search']['env']['UV_PROJECT_ENVIRONMENT']=str(runtime_env)
    (plugin/'.mcp.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')

def require_inputs(a):
    missing=[n for n in ('target','source','index_store','result_sink') if getattr(a,n) is None]
    if missing: raise RuntimeError(f'missing required inputs: {missing}')

def build_plan(a):
    require_inputs(a)
    target=a.target.resolve();source=a.source.resolve()
    if not (source/'smart_explore.py').is_file() or not (source/'uv.lock').is_file():
        raise RuntimeError('source is not a locked Search plugin')
    stores=[s.strip() for s in a.stores.split(',') if s.strip()]
    unknown=set(stores)-STORE_NAMES
    if unknown: raise RuntimeError(f'unknown stores: {sorted(unknown)}')
    commit,dirty=git_state(source)
    manifest=load_json(source/'.claude-plugin'/'plugin.json')
    uv=shutil.which('uv') or str(Path.home()/'.local'/'bin'/'uv.exe')
    installer='uv' if Path(uv).is_file() or shutil.which('uv') else 'venv-pip'
    plan={'schema':'smart-explore-bootstrap-plan/v1','target':str(target),'source':str(source),
      'plugin_target':str(target/'plugins'/'search'),'index_store':str(a.index_store.resolve()),
      'result_sink':str(a.result_sink.resolve()),'runtime_env':str(target/'.runtime'/'search'/'env'),
      'profile_registry':str(a.registry_home.resolve()/'profiles'),
      'name':a.name or ''.join(c if c.isalnum() or c in '-_' else '-' for c in target.name.lower()),
      'stores':stores,'installer':installer,'uv':uv if installer=='uv' else None,
      'source_commit':commit,'source_dirty':dirty,'source_version':manifest.get('version'),
      'source_package_sha256':package_hash(source),
      'actions':['copy pinned Search plugin','create ignored isolated runtime','write routing profile',
                 'write code-only CCC settings','smoke test imports/parser/DuckDB/CLI/MCP'],
      'update':a.update}
    plan['plan_id']=hashlib.sha256(canonical(plan)).hexdigest().upper()
    return plan

def validate_plan(plan):
    pid=plan.pop('plan_id',None)
    actual=hashlib.sha256(canonical(plan)).hexdigest().upper()
    plan['plan_id']=pid
    if pid!=actual: raise RuntimeError('plan file content does not match immutable plan ID')
    return pid

def scan(a):
    require_inputs(a)
    plan=build_plan(a)
    emit({'mode':'scan','target_exists':a.target.exists(),
          'plugin_exists':Path(plan['plugin_target']).exists(),
          'source_commit':plan['source_commit'],'source_dirty':plan['source_dirty'],
          'source_version':plan['source_version'],'source_package_sha256':plan['source_package_sha256'],
          'proposed_installer':plan['installer'],'proposed_runtime_env':plan['runtime_env']})

def plan_mode(a):
    if not a.plan_file: raise RuntimeError('--plan-file is required')
    plan=build_plan(a);a.plan_file.parent.mkdir(parents=True,exist_ok=True)
    a.plan_file.write_text(json.dumps(plan,indent=2)+'\n',encoding='utf-8')
    emit({'mode':'plan','plan_file':str(a.plan_file),'plan':plan,'next_action':'human reviews and explicitly runs approve with this exact plan_id'})

def approve(a):
    if not a.plan_file or not a.approval_file or not a.plan_id or not a.approve:
        raise RuntimeError('approve requires --plan-file --approval-file --plan-id and --approve')
    plan=load_json(a.plan_file);pid=validate_plan(plan)
    if a.plan_id.upper()!=pid: raise RuntimeError('typed plan ID does not match plan')
    approval={'schema':'smart-explore-bootstrap-approval/v1','approved':True,'plan_id':pid,
      'target':plan['target'],'source_package_sha256':plan['source_package_sha256'],
      'approved_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    a.approval_file.parent.mkdir(parents=True,exist_ok=True)
    a.approval_file.write_text(json.dumps(approval,indent=2)+'\n',encoding='utf-8')
    emit({'mode':'approve','approval_file':str(a.approval_file),'plan_id':pid})

def verify_install(plan):
    plugin=Path(plan['plugin_target']);env=Path(plan['runtime_env'])
    py=env/'Scripts'/'python.exe' if os.name=='nt' else env/'bin'/'python'
    checks={}
    cp=subprocess.run([str(py),'-c','import duckdb,tree_sitter_language_pack;print(duckdb.__version__)'],text=True,capture_output=True,timeout=60)
    checks['isolated_imports']={'ok':cp.returncode==0,'output':cp.stdout.strip() or cp.stderr.strip()}
    runenv=dict(os.environ,UV_PROJECT_ENVIRONMENT=str(env))
    cp=subprocess.run([str(plugin/'search.cmd'),'--help'],cwd=plugin,env=runenv,text=True,capture_output=True,timeout=120)
    checks['cli_help']={'ok':cp.returncode==0,'output':(cp.stdout or cp.stderr)[:200]}
    probe=plugin/'smart_explore.py'
    cp=subprocess.run([str(plugin/'search.cmd'),'search','central store','--path',str(plugin),'--max','3','--json','--db',str(Path(plan['index_store'])/'verify.duckdb')],cwd=plugin,env=runenv,text=True,capture_output=True,timeout=180)
    checks['tree_sitter_duckdb_query']={'ok':cp.returncode==0 and 'central_store' in cp.stdout,'output':(cp.stdout or cp.stderr)[:300]}
    request=json.dumps({'jsonrpc':'2.0','id':1,'method':'initialize','params':{}}).encode()
    frame=f'Content-Length: {len(request)}\r\n\r\n'.encode()+request
    mcp=subprocess.run([str(py),str(plugin/'mcp_server.py')],input=frame,capture_output=True,timeout=60)
    output=mcp.stdout.decode('utf-8','replace')
    checks['mcp_initialize']={'ok':mcp.returncode==0 and 'propria-search' in output,'output':output[:300] or mcp.stderr.decode('utf-8','replace')[:300]}
    settings=(Path(plan['target'])/'.cocoindex_code'/'settings.yml').read_text(encoding='utf-8')
    checks['docs_exclusion']={'ok':all(x in settings for x in ('**/docs/**','**/*.py')) and '**/*.md' not in settings}
    checks['ok']=all(v.get('ok',False) for v in checks.values() if isinstance(v,dict))
    return checks

def apply(a):
    if not a.plan_file or not a.approval_file: raise RuntimeError('apply requires --plan-file and --approval-file')
    plan=load_json(a.plan_file);pid=validate_plan(plan);approval=load_json(a.approval_file)
    required=(approval.get('approved') is True and approval.get('plan_id')==pid
      and approval.get('target')==plan['target']
      and approval.get('source_package_sha256')==plan['source_package_sha256'])
    if not required: raise RuntimeError('approval is not bound to exact plan, target, and source hash')
    source=Path(plan['source']);target=Path(plan['target']);plugin=Path(plan['plugin_target'])
    if package_hash(source)!=plan['source_package_sha256']: raise RuntimeError('source changed after approval')
    stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    quarantine=target/'to_be_deleted'/f'search-bootstrap-{stamp}'
    if plugin.exists() and not plan['update']: raise RuntimeError('target plugin exists and approved plan is not update')
    if plugin.exists(): preserve(plugin,quarantine)
    stage=target/'plugins'/f'.search-stage-{stamp}';stage.mkdir(parents=True)
    for src,rel in package_files(source):
        dst=stage/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
    stage.rename(plugin)
    customize_instance(plugin,Path(plan['runtime_env']))
    target.mkdir(parents=True,exist_ok=True)
    ignore=target/'.gitignore'
    current=ignore.read_text(encoding='utf-8') if ignore.exists() else ''
    if '/.runtime/' not in current.splitlines():
        ignore.write_text(current+('' if not current or current.endswith('\n') else '\n')+'/.runtime/\n',encoding='utf-8')
    cfg=target/'.cocoindex_code'/'settings.yml';cfg.parent.mkdir(parents=True,exist_ok=True)
    if cfg.exists() and cfg.read_text(encoding='utf-8')!=CODE_SETTINGS: preserve(cfg,quarantine/'cocoindex')
    if not cfg.exists(): cfg.write_text(CODE_SETTINGS,encoding='utf-8')
    Path(plan['index_store']).mkdir(parents=True,exist_ok=True);Path(plan['result_sink']).mkdir(parents=True,exist_ok=True)
    env=Path(plan['runtime_env']);env.parent.mkdir(parents=True,exist_ok=True)
    if plan['installer']=='uv':
        runenv=dict(os.environ,UV_PROJECT_ENVIRONMENT=str(env))
        cp=subprocess.run([plan['uv'],'sync','--project',str(plugin),'--locked'],env=runenv,text=True,capture_output=True,timeout=300)
    else:
        cp=subprocess.run([sys.executable,'-m','venv',str(env)],text=True,capture_output=True,timeout=180)
        if cp.returncode==0:
            py=env/'Scripts'/'python.exe' if os.name=='nt' else env/'bin'/'python'
            cp=subprocess.run([str(py),'-m','pip','install','-r',str(plugin/'requirements.txt')],text=True,capture_output=True,timeout=300)
    if cp.returncode: raise RuntimeError(cp.stderr or cp.stdout)
    profile={k:plan[k] for k in ('name','target','index_store','result_sink','stores','plugin_target','source_commit','source_dirty','source_version','source_package_sha256')}
    profile.update(schema='smart-explore-project-profile/v1',root=profile.pop('target'),plugin_path=profile.pop('plugin_target'),installed_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    profile_file=Path(plan['profile_registry'])/(plan['name']+'.json');profile_file.parent.mkdir(parents=True,exist_ok=True)
    if profile_file.exists(): preserve(profile_file,Path.home()/'.smart-explore'/'to_be_deleted'/f'profile-{stamp}')
    profile_file.write_text(json.dumps(profile,indent=2)+'\n',encoding='utf-8')
    (target/'.search-profile.json').write_text(json.dumps(profile,indent=2)+'\n',encoding='utf-8')
    checks=verify_install(plan)
    if not checks['ok']: raise RuntimeError('verification failed: '+json.dumps(checks))
    receipt=Path(plan['result_sink'])/f'bootstrap-{pid}.json'
    receipt.write_text(json.dumps({'plan':plan,'approval':approval,'checks':checks},indent=2)+'\n',encoding='utf-8')
    emit({'mode':'apply','plan_id':pid,'receipt':str(receipt),'checks':checks})

def verify_mode(a):
    if not a.plan_file: raise RuntimeError('verify requires --plan-file')
    plan=load_json(a.plan_file);validate_plan(plan);emit({'mode':'verify','plan_id':plan['plan_id'],'checks':verify_install(plan)})

def report(a):
    if not a.plan_file: raise RuntimeError('report requires --plan-file')
    plan=load_json(a.plan_file);validate_plan(plan)
    profile=Path(plan['profile_registry'])/(plan['name']+'.json')
    emit({'mode':'report','plan_id':plan['plan_id'],'profile':load_json(profile) if profile.exists() else None})

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('mode',choices=['scan','plan','approve','apply','verify','report'])
    ap.add_argument('--target',type=Path);ap.add_argument('--source',type=Path)
    ap.add_argument('--index-store',type=Path);ap.add_argument('--result-sink',type=Path)
    ap.add_argument('--stores',default='smart_explore,ccc');ap.add_argument('--name')
    ap.add_argument('--registry-home',type=Path,default=Path.home()/'.smart-explore')
    ap.add_argument('--plan-file',type=Path);ap.add_argument('--approval-file',type=Path)
    ap.add_argument('--plan-id');ap.add_argument('--approve',action='store_true');ap.add_argument('--update',action='store_true')
    a=ap.parse_args()
    {'scan':scan,'plan':plan_mode,'approve':approve,'apply':apply,'verify':verify_mode,'report':report}[a.mode](a)
if __name__=='__main__': main()
