#!/usr/bin/env python3
"""Dependency-free MCP stdio facade for the canonical Propria Search engine."""
from __future__ import annotations
import json, os, subprocess, sys
from pathlib import Path

ROOT=Path(__file__).resolve().parent
CLI=ROOT/"smart_explore.py"
PY=sys.executable

def tool(name,description,properties,required=None):
 return {"name":name,"description":description,"inputSchema":{"type":"object","properties":properties,"required":required or [],"additionalProperties":False}}

STR={"type":"string"}; INT={"type":"integer","minimum":0}; STORES={"type":"array","items":{"type":"string","enum":["smart_explore","ccc","docstore","codex_memory","claude_memory","cnf","remember","memsearch"]}}
TOOLS=[
 tool("structural_search","Tree-sitter structural symbol search backed by the Smart Explore DuckDB index.",{"query":STR,"path":STR,"max":INT},["query","path"]),
 tool("semantic_code_search","Natural-language CCC code search with language/path filters and pagination.",{"query":STR,"path":STR,"lang":{"type":"array","items":STR},"file_path":STR,"offset":INT,"limit":INT},["query","path"]),
 tool("code_index_refresh","Run the separate project-local CCC code index refresh.",{"path":STR},["path"]),
 tool("code_index_status","Read project-local CCC code index status.",{"path":STR},["path"]),
 tool("code_index_doctor","Run CCC health diagnostics.",{"path":STR},["path"]),
 tool("structural_grep","Run CCC structural grep by example.",{"query":STR,"path":STR},["query","path"]),
 tool("selected_store_recall","Query optional structural, semantic, docs and memory stores with per-store provenance.",{"query":STR,"path":STR,"mode":{"type":"string","enum":["auto","all","selected"]},"stores":STORES,"limit":INT},["query","path"]),
 tool("conflict_discovery","Discover conflicting cross-store statements and provenance.",{"query":STR,"path":STR,"mode":{"type":"string","enum":["auto","all","selected"]},"stores":STORES,"limit":INT},["query","path"]),
 tool("decisions_final_contracts","Find governing decisions and final/canonical contracts across selected stores.",{"query":STR,"path":STR,"mode":{"type":"string","enum":["auto","all","selected"]},"stores":STORES,"limit":INT},["query","path"]),
 tool("reconcile_run","Persist a provenance-rich adjudication packet and agent repair loop.",{"query":STR,"path":STR,"mode":{"type":"string","enum":["auto","all","selected"]},"stores":STORES,"limit":INT,"output_dir":STR},["query","path"]),
 tool("reconcile_repair","Trigger a bounded agent repair packet when attribution or conflicts are dirty.",{"query":STR,"path":STR,"mode":{"type":"string","enum":["auto","all","selected"]},"stores":STORES,"limit":INT,"output_dir":STR},["query","path"]),
 tool("reconcile_status","Read a persisted reconciliation packet status.",{"packet":STR},["packet"]),
 tool("reconcile_export","Export a packet as JSON or Markdown.",{"packet":STR,"format":{"type":"string","enum":["json","md"]},"output":STR},["packet"]),
 tool("store_inventory","Report requested/available adapter identity for every selectable store.",{"path":STR},["path"]),
]

def run_cli(args,cwd=None):
 cp=subprocess.run([PY,str(CLI),*args],cwd=cwd or str(ROOT),text=True,capture_output=True,encoding="utf-8",errors="replace",timeout=300)
 if cp.returncode: raise RuntimeError(cp.stderr.strip() or cp.stdout.strip() or f"exit {cp.returncode}")
 try:return json.loads(cp.stdout)
 except json.JSONDecodeError:return {"text":cp.stdout}

def call(name,a):
 path=a.get("path",os.getcwd()); limit=str(a.get("limit",20)); mode=a.get("mode","auto"); stores=a.get("stores",[])
 if name=="structural_search": return run_cli(["search",a["query"],"--path",path,"--max",str(a.get("max",20)),"--json"],path)
 if name=="semantic_code_search":
  args=["semantic",a["query"],"--path",path,"--offset",str(a.get("offset",0)),"--limit",str(a.get("limit",10))]
  for lang in a.get("lang",[]):args += ["--lang",lang]
  if a.get("file_path"):args += ["--file-path",a["file_path"]]
  return run_cli(args,path)
 if name in {"code_index_refresh","code_index_status","code_index_doctor"}: return run_cli([{"code_index_refresh":"ccc-index","code_index_status":"ccc-status","code_index_doctor":"ccc-doctor"}[name],"--path",path],path)
 if name=="structural_grep": return run_cli(["ccc-grep","--path",path,"--query",a["query"]],path)
 if name=="store_inventory": return run_cli(["stores","--path",path,"--json"],path)
 command={"selected_store_recall":"recall","conflict_discovery":"conflicts","decisions_final_contracts":"decisions"}.get(name)
 if command:
  args=[command,a["query"],"--path",path,"--mode",mode,"--limit",limit]
  for s in stores:args += ["--stores",s]
  return run_cli(args,path)
 if name in {"reconcile_run","reconcile_repair"}:
  args=["reconcile","repair" if name=="reconcile_repair" else "run",a["query"],"--path",path,"--mode",mode,"--limit",limit]
  for s in stores:args += ["--stores",s]
  if a.get("output_dir"):args += ["--output-dir",a["output_dir"]]
  return run_cli(args,path)
 if name=="reconcile_status": return run_cli(["reconcile","status",a["packet"]])
 if name=="reconcile_export":
  args=["export",a["packet"],"--format",a.get("format","md")]
  if a.get("output"):args += ["--output",a["output"]]
  return run_cli(args)
 raise ValueError(f"unknown tool: {name}")

def send(obj):
 raw=json.dumps(obj,separators=(",",":"),ensure_ascii=False).encode(); sys.stdout.buffer.write(f"Content-Length: {len(raw)}\r\n\r\n".encode()+raw);sys.stdout.buffer.flush()

def main():
 while True:
  headers={}
  while True:
   line=sys.stdin.buffer.readline()
   if not line:return
   if line in (b"\r\n",b"\n"):break
   k,v=line.decode().split(":",1);headers[k.lower()]=v.strip()
  msg=json.loads(sys.stdin.buffer.read(int(headers.get("content-length","0"))))
  mid=msg.get("id"); method=msg.get("method")
  if mid is None:continue
  try:
   if method=="initialize":result={"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"propria-search","version":"1.0.0"}}
   elif method=="tools/list":result={"tools":TOOLS}
   elif method=="tools/call":
    value=call(msg["params"]["name"],msg["params"].get("arguments",{}));result={"content":[{"type":"text","text":json.dumps(value,indent=2)}],"structuredContent":value}
   else:raise ValueError(f"unsupported method: {method}")
   send({"jsonrpc":"2.0","id":mid,"result":result})
  except Exception as exc:send({"jsonrpc":"2.0","id":mid,"error":{"code":-32000,"message":f"{type(exc).__name__}: {exc}"}})
if __name__=="__main__":main()
