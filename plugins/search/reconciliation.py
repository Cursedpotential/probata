"""Selectable cross-store retrieval and conflict packet engine for Propria Search."""
from __future__ import annotations
import hashlib, json, os, re, shutil, subprocess, time, uuid
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

SCHEMA = "propria-search-reconcile/v1"
STORE_NAMES = ("smart_explore","ccc","docstore","codex_memory","claude_memory","cnf","remember","memsearch")
TEXT_SUFFIXES = {".md", ".txt", ".json", ".jsonl", ".yaml", ".yml"}

@dataclass
class StoreRun:
    store: str; requested: bool; available: bool; queried: bool=False
    skipped: str|None=None; error: str|None=None; adapter: str|None=None
    identity: Any=None; duration_ms: int=0; result_count: int=0

def _roots() -> dict[str,list[Path]]:
    home=Path.home(); ws=Path(os.getenv("AI_WORKSPACE_ROOT", r"E:\AI_Workspace"))
    return {
      "codex_memory":[home/".codex"/"memories"],
      "claude_memory":[home/".claude"/"projects"],
      "cnf":list((home/".claude"/"plugins"/"data").glob("claude-never-forgets-*")),
      "remember":[home/".claude"/".remember", ws/"Projects"/"Propria"/"Probata"/"probata"/".remember"],
      "memsearch":[home/".memsearch"/"memory", ws/".memories"/".memsearch"],
    }

def inventory(project_root: str|None=None) -> dict[str,dict[str,Any]]:
    root=str(Path(project_root or os.getcwd()).resolve()); roots=_roots(); se=Path(__file__).with_name("smart_explore.py").resolve()
    ccc=shutil.which("ccc"); doc_cmd=os.getenv("PROPRIA_DOCSTORE_ADAPTER")
    data={
      "smart_explore":{"available":True,"adapter":"native","identity":{"engine":str(se),"project_root":root}},
      "ccc":{"available":bool(ccc and (Path(root)/".cocoindex_code"/"settings.yml").exists()),"adapter":ccc,"identity":{"project_root":root,"settings":str(Path(root)/".cocoindex_code"/"settings.yml"),"index":str(Path(root)/".cocoindex_code"/"target_sqlite.db")}},
      "docstore":{"available":bool(doc_cmd),"adapter":doc_cmd,"identity":{"transport":"json-stdio","command_config":"PROPRIA_DOCSTORE_ADAPTER"}},
    }
    for name in ("codex_memory","claude_memory","cnf","remember","memsearch"):
      existing=[str(p) for p in roots[name] if p.exists()]
      data[name]={"available":bool(existing),"adapter":"filesystem-text" if name!="memsearch" else (shutil.which("memsearch") or "filesystem-text"),"identity":{"roots":existing}}
    return data

def select_stores(mode:str, stores:list[str]|None)->list[str]:
    stores=stores or []
    bad=[s for s in stores if s not in STORE_NAMES]
    if bad: raise ValueError(f"unknown stores: {', '.join(bad)}")
    if mode=="selected":
      if not stores: raise ValueError("selected mode requires --stores")
      return list(dict.fromkeys(stores))
    if mode=="all": return list(STORE_NAMES)
    if mode!="auto": raise ValueError("mode must be auto, all, or selected")
    return list(dict.fromkeys(stores or ["smart_explore","ccc","docstore","codex_memory","claude_memory","cnf","remember","memsearch"]))

def _run(command:list[str], cwd:str, timeout:int=90, stdin:dict|None=None):
    return subprocess.run(command,cwd=cwd,input=json.dumps(stdin) if stdin else None,text=True,capture_output=True,timeout=timeout,encoding="utf-8",errors="replace")

def _normalize(store:str,item:dict)->dict:
    text=str(item.get("excerpt") or item.get("content") or item.get("text") or item.get("code") or "")
    path=str(item.get("path") or item.get("file") or item.get("source") or "")
    title=str(item.get("title") or item.get("name") or (Path(path).name if path else store))
    raw=json.dumps(item,sort_keys=True,default=str).encode()
    timestamps=re.findall(r"20\d\d-\d\d-\d\d(?:T[0-9:.+-]+Z?)?",text[:4000])[:5]
    session_ids=re.findall(r"(?:session|thread)(?:_id)?[:=\s`]+([0-9a-zA-Z_-]{8,})",text[:4000],re.I)[:5]
    return {"store":store,"kind":item.get("kind","result"),"title":title,"source_uri":item.get("source_uri") or path,"path":path,"line_start":item.get("line_start") or item.get("start_line") or item.get("line"),"line_end":item.get("line_end") or item.get("end_line"),"revision":item.get("revision"),"content_hash":item.get("content_hash") or hashlib.sha256(raw).hexdigest(),"score":item.get("score"),"excerpt":text[:1200],"timestamps":timestamps,"session_ids":session_ids,"provenance":item.get("provenance") or {"adapter":store}}

def _dedupe(results:list[dict])->list[dict]:
    unique={}
    for row in results:
      key=hashlib.sha256(re.sub(r"\s+"," ",row["excerpt"].strip().lower()).encode()).hexdigest()
      if key not in unique:
        row["occurrences"]=[{"store":row["store"],"source_uri":row["source_uri"],"provenance":row["provenance"]}]
        unique[key]=row
      else:
        unique[key]["occurrences"].append({"store":row["store"],"source_uri":row["source_uri"],"provenance":row["provenance"]})
    return list(unique.values())

def _filesystem_search(store:str, query:str, roots:list[str], limit:int)->list[dict]:
    terms=[t.lower() for t in re.findall(r"[A-Za-z0-9_-]+",query) if len(t)>2]
    rows=[]
    for root in map(Path,roots):
      for p in root.rglob("*"):
        if len(rows)>=limit: break
        if not p.is_file() or p.suffix.lower() not in TEXT_SUFFIXES: continue
        try:
          text=p.read_text(encoding="utf-8",errors="ignore")
        except OSError: continue
        low=text.lower(); hits=sum(low.count(t) for t in terms)
        if not hits: continue
        pos=min((low.find(t) for t in terms if t in low),default=0); start=max(0,pos-240)
        rows.append(_normalize(store,{"kind":"memory","title":p.name,"path":str(p),"score":hits,"excerpt":text[start:start+900],"provenance":{"root":str(root),"mtime_ns":p.stat().st_mtime_ns}}))
    return sorted(rows,key=lambda x:x.get("score") or 0,reverse=True)[:limit]

def _query_store(store:str, query:str, root:str, limit:int, ident:dict)->list[dict]:
    if store=="smart_explore":
      cp=_run([os.fspath(Path(os.sys.executable)),str(Path(__file__).with_name("smart_explore.py")),"search",query,"--path",root,"--max",str(limit),"--json"],root,120)
      if cp.returncode: raise RuntimeError(cp.stderr.strip() or f"exit {cp.returncode}")
      obj=json.loads(cp.stdout); items=obj.get("symbols") or obj.get("results") or []
      return [_normalize(store,x) for x in items]
    if store=="ccc":
      cp=_run([ident[store]["adapter"],"search","--limit",str(limit),"--json",query],root,180)
      if cp.returncode: raise RuntimeError(cp.stderr.strip() or f"exit {cp.returncode}")
      obj=json.loads(cp.stdout); items=obj if isinstance(obj,list) else obj.get("results",[])
      return [_normalize(store,x) for x in items]
    if store=="docstore":
      request={"schema":SCHEMA,"operation":"query","query":query,"limit":limit}
      cp=_run([ident[store]["adapter"]],root,120,request)
      if cp.returncode: raise RuntimeError(cp.stderr.strip() or f"exit {cp.returncode}")
      obj=json.loads(cp.stdout); return [_normalize(store,x) for x in obj.get("results",[])]
    return _filesystem_search(store,query,ident[store]["identity"].get("roots",[]),limit)

def discover_conflicts(results:list[dict])->list[dict]:
    groups={}
    for r in results:
      key=re.sub(r"[^a-z0-9]+"," ",r["title"].lower()).strip()
      if key: groups.setdefault(key,[]).append(r)
    out=[]
    for key,items in groups.items():
      stores={x["store"] for x in items}; hashes={x["content_hash"] for x in items}
      if len(stores)>1 and len(hashes)>1:
        out.append({"key":key,"stores":sorted(stores),"content_hashes":sorted(hashes),"items":items,"requires_adjudication":True})
    return out

def recall(query:str, project_root:str|None=None, mode:str="auto", stores:list[str]|None=None, limit:int=20)->dict:
    root=str(Path(project_root or os.getcwd()).resolve()); selected=select_stores(mode,stores); ident=inventory(root)
    runs=[]; results=[]
    for store in STORE_NAMES:
      requested=store in selected; meta=ident[store]; run=StoreRun(store,requested,bool(meta["available"]),adapter=meta.get("adapter"),identity=meta.get("identity"))
      if not requested: run.skipped="not selected"
      elif not run.available: run.skipped="unavailable"
      else:
        start=time.monotonic()
        try: rows=_query_store(store,query,root,limit,ident); results.extend(rows); run.queried=True; run.result_count=len(rows)
        except Exception as exc: run.error=f"{type(exc).__name__}: {exc}"
        run.duration_ms=int((time.monotonic()-start)*1000)
      runs.append(asdict(run))
    results=_dedupe(results)
    decisions=[r for r in results if re.search(r"\b(decision|adr|ruling|approved|owner)\b",(r["title"]+" "+r["excerpt"]),re.I)]
    contracts=[r for r in results if re.search(r"\b(contract|final|canonical|must|shall)\b",(r["title"]+" "+r["excerpt"]),re.I)]
    conflicts=discover_conflicts(results)
    next_actions=[]
    for run in runs:
      if run["requested"] and not run["available"]:
        next_actions.append("configure PROPRIA_DOCSTORE_ADAPTER and retry" if run["store"]=="docstore" else f"make the {run['store']} adapter available and retry")
      elif run["requested"] and run["error"]:
        next_actions.append(f"inspect the {run['store']} error and retry that selected store")
    if conflicts: next_actions.append("run reconcile repair to create a provenance-rich agent action packet")
    if not results: next_actions.append("verify selected index freshness or choose another explicit store")
    if results and not conflicts: next_actions.append("inspect result provenance before accepting a governing decision or contract")
    return {"schema":SCHEMA,"operation":"recall","query":query,"mode":mode,"project_root":root,"store_runs":runs,"results":results,"decisions":decisions,"contracts":contracts,"conflicts":conflicts,"attribution_clean":not conflicts and not any(x["requested"] and (x["error"] or not x["available"]) for x in runs),"errors":[x for x in runs if x["error"]],"next_actions":list(dict.fromkeys(next_actions))}

def persist_packet(packet:dict, output_dir:str|None=None)->dict:
    root=Path(output_dir or (Path(packet["project_root"])/".search-reconcile"/"packets")); root.mkdir(parents=True,exist_ok=True)
    run_id=packet.get("run_id") or f"{time.strftime('%Y%m%dT%H%M%SZ',time.gmtime())}-{uuid.uuid4().hex[:8]}"; packet["run_id"]=run_id
    packet["agent_loop"]={"status":"clean" if packet["attribution_clean"] else "requires_agent_repair","steps":["inspect responsible pipeline/config/source registration with smart_explore","find semantic code neighbors with ccc","recover governing decisions and final contracts from selected memories and docstore","adjudicate conflicts with provenance","apply bounded repair in owning repository","validate and reindex the affected store","require clean attribution before completion"]}
    nodes=[]; edges=[]
    for i,row in enumerate(packet["results"]):
      rid=f"result:{i}"; nodes.append({"id":rid,"type":row["kind"],"label":row["title"],"store":row["store"],"source_uri":row["source_uri"],"timestamps":row.get("timestamps",[]),"session_ids":row.get("session_ids",[])})
      edges.append({"from":f"store:{row['store']}","to":rid,"type":"returned"})
      if row in packet["decisions"]: edges.append({"from":rid,"to":"governance:decision","type":"supports"})
      if row in packet["contracts"]: edges.append({"from":rid,"to":"governance:contract","type":"supports"})
      if re.search(r"supersed|retired|replaced",row["excerpt"],re.I): edges.append({"from":rid,"to":"governance:supersession","type":"mentions"})
    for store in STORE_NAMES:nodes.append({"id":f"store:{store}","type":"store","label":store})
    nodes.extend([{"id":"governance:decision","type":"classification","label":"governing decisions"},{"id":"governance:contract","type":"classification","label":"final contracts"},{"id":"governance:supersession","type":"classification","label":"supersession"}])
    packet["graph"]={"nodes":nodes,"edges":edges}
    packet["actionable_backlog"]=[{"priority":"critical","item":"Resolve each provenance conflict before relying on completion claims"}] if packet["conflicts"] else []
    jp=root/f"{run_id}.json"; mp=root/f"{run_id}.md"; jp.write_text(json.dumps(packet,indent=2,default=str),encoding="utf-8")
    mp.write_text(f"# Reconciliation packet {run_id}\n\nQuery: {packet['query']}\n\nAttribution clean: **{packet['attribution_clean']}**\n\nStores: {', '.join(x['store'] for x in packet['store_runs'] if x['queried'])}\n\nConflicts: {len(packet['conflicts'])}\nDecisions: {len(packet['decisions'])}\nContracts: {len(packet['contracts'])}\n",encoding="utf-8")
    packet["packet_path"]=str(jp); packet["packet_markdown_path"]=str(mp); jp.write_text(json.dumps(packet,indent=2,default=str),encoding="utf-8")
    return packet
