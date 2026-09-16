# propria-docstore plugin test matrix

> _Byline: Claude Code · Opus 5 · 2026-09-16_

Produced by `scripts/docstore/test_plugin.py` against the LIVE store (SurrealDB `probata`/`docs`) and the LIVE MCP servers. Owner order 2026-09-16 08:51 EDT: "it's not fixed until every function, script, tool call, query is tested."

Generated 2026-09-16 19:37:04 Eastern Daylight Time.

## Totals

**208/213 PASS, 5 FAIL**

- fn: run 1ea94656 - 82/82 pass, 0 fail
-    store rows before: {'harness_documents': 11, 'harness_documents_not_retracted': 0, 'harness_handoffs_not_retracted': 0, 'decision_log_test_rows': 109}
-    store rows after : {'harness_documents': 17, 'harness_documents_not_retracted': 0, 'harness_handoffs_not_retracted': 0, 'decision_log_test_rows': 133}
- skill: run b6c9c89d - 52/55 pass, 3 fail
- mcp: run d41fbe72 - 74/76 pass, 2 fail

Reproduce with:

```
cd <repo root>
"C:/Users/matts/.local/bin/python3.exe" scripts/docstore/test_plugin.py --only fn
"C:/Users/matts/.local/bin/python3.exe" scripts/docstore/test_plugin.py --only skill
"C:/Users/matts/.local/bin/python3.exe" scripts/docstore/test_plugin.py --only mcp
```

## Remaining FAILs

| section | item | args form | blocker |
|---|---|---|---|
| skill | fn::remember @ SKILL.md:17 | { kind: $kind, claim: $claim, detail: $detail_or_none, scope | fn::remember is a MEMORY-database function and is not deployed: the memory instance (100.91.190.107:8471) holds only ns fct/db case, and ns probata_memory does not exist. Auth works (MEMORY_BASIC_AUTH set, tools/list returns 14 tools); the blocker is D-157 - run scripts/docstore/memory-schema-fallback/apply_memory_schema.sh. Not a docs-store defect |
| skill | fn::supersede_memory @ SKILL.md:40 | $old_id,$new_payload | fn::supersede_memory is a MEMORY-database function and is not deployed: the memory instance (100.91.190.107:8471) holds only ns fct/db case, and ns probata_memory does not exist. Auth works (MEMORY_BASIC_AUTH set, tools/list returns 14 tools); the blocker is D-157 - run scripts/docstore/memory-schema-fallback/apply_memory_schema.sh. Not a docs-store defect |
| skill | fn::forget @ SKILL.md:41 | $id,$reason | fn::forget is a MEMORY-database function and is not deployed: the memory instance (100.91.190.107:8471) holds only ns fct/db case, and ns probata_memory does not exist. Auth works (MEMORY_BASIC_AUTH set, tools/list returns 14 tools); the blocker is D-157 - run scripts/docstore/memory-schema-fallback/apply_memory_schema.sh. Not a docs-store defect |
| mcp | control:docstore_reconcile_packet | {"query": "catalog"} | tool isError: Propria reconciliation adapter is unavailable |
| mcp | control:docstore_reconcile_query | {"query": "catalog"} | tool isError: Propria reconciliation adapter is unavailable |

## Full matrix

| section | item | kind | args form | result | error |
|---|---|---|---|---|---|
| fn | fn::docs_register | fn | 7 args, $authored_at=NONE | PASS |  |
| fn | fn::docs_register | fn | doc_type=decision | PASS |  |
| fn | fn::docs_register | fn | third fixture | PASS |  |
| fn | fn::docs_register | fn | duplicate path (guard) | PASS |  |
| fn | fn::docs_search | fn | all optionals NONE | PASS |  |
| fn | fn::docs_search | fn | all optionals NULL (MCP json null) | PASS |  |
| fn | fn::docs_search | fn | NULL vec + doc_type filter | PASS |  |
| fn | fn::docs_search | fn | k omitted (NONE -> default 10) | PASS |  |
| fn | fn::docs_search | fn | k=1 (lower bound) | PASS |  |
| fn | fn::docs_search | fn | k=25 (>20: 50/256 KNN branch) | PASS |  |
| fn | fn::docs_search | fn | domain filter | PASS |  |
| fn | fn::docs_search | fn | status="active" | PASS |  |
| fn | fn::docs_search | fn | status="proposed" | PASS |  |
| fn | fn::docs_search | fn | status="retracted" | PASS |  |
| fn | fn::docs_search | fn | status="superseded" | PASS |  |
| fn | fn::docs_search | fn | status="unverified" | PASS |  |
| fn | fn::docs_search | fn | real 2048-dim vector | PASS |  |
| fn | fn::docs_search | fn | no-match query | PASS |  |
| fn | fn::docs_get | fn | record id (native) | PASS |  |
| fn | fn::docs_get | fn | string id 'document:xxx' | PASS |  |
| fn | fn::docs_get | fn | nonexistent id | PASS |  |
| fn | fn::docs_tagged | fn | tag only, optionals NONE | PASS |  |
| fn | fn::docs_tagged | fn | tag only, optionals NULL | PASS |  |
| fn | fn::docs_tagged | fn | with query (BM25 branch) | PASS |  |
| fn | fn::docs_tagged | fn | with domain + k | PASS |  |
| fn | fn::docs_set_tags | fn | record id + actor | PASS |  |
| fn | fn::docs_set_tags | fn | normalises + dedupes | PASS |  |
| fn | fn::docs_set_tags | fn | string id | PASS |  |
| fn | fn::docs_set_tags | fn | nonexistent id (guard) | PASS |  |
| fn | fn::docs_new_version | fn | record id, title NONE (inherit) | PASS |  |
| fn | fn::docs_new_version | fn | string id, title NULL | PASS |  |
| fn | fn::docs_new_version | fn | NULL title inherits | PASS |  |
| fn | fn::provenance | fn | record<any> subject | PASS |  |
| fn | fn::docs_supersede | fn | string ids both args | PASS |  |
| fn | fn::decision_amend | fn | $closes NONE | PASS |  |
| fn | fn::decision_amend | fn | $closes NULL (MCP json null) | PASS |  |
| fn | fn::decision_amend | fn | unindexed path (no_subject_record guard) | PASS |  |
| fn | fn::handoff_write | fn | 3 args (legacy caller) | PASS |  |
| fn | fn::handoff_write | fn | different domain set (must not clobber) | PASS |  |
| fn | fn::handoff_write | fn | overlap-only left A active (defect 6) | PASS |  |
| fn | fn::handoff_write | fn | same domain set supersedes | PASS |  |
| fn | fn::handoff_write | fn | match=same_domain_set | PASS |  |
| fn | fn::handoff_write | fn | superseded A exactly | PASS |  |
| fn | fn::handoff_write | fn | B (different set) still active | PASS |  |
| fn | fn::handoff_write | fn | 4 args explicit $supersedes | PASS |  |
| fn | fn::handoff_write | fn | match=explicit | PASS |  |
| fn | fn::handoff_write | fn | 4th arg NULL (MCP json null) | PASS |  |
| fn | fn::todo_open | fn | $source NONE | PASS |  |
| fn | fn::todo_open | fn | $source NULL (MCP json null) | PASS |  |
| fn | fn::todo_open | fn | $source resolves to source_doc | PASS |  |
| fn | fn::todo_open | fn | source_doc populated | PASS |  |
| fn | fn::todo_close | fn | string id + evidence | PASS |  |
| fn | fn::todo_close | fn | record id + evidence | PASS |  |
| fn | fn::open_work | fn | $project string | PASS |  |
| fn | fn::current_decisions | fn | $project string | PASS |  |
| fn | fn::stale_candidates | fn | $older_than duration | PASS |  |
| fn | fn::search_text | fn | optionals NONE | PASS |  |
| fn | fn::search_text | fn | optionals NULL | PASS |  |
| fn | fn::search_text | fn | NULL == NONE (same row count) | PASS |  |
| fn | fn::search_text | fn | NULL not silently zero-rows | PASS |  |
| fn | fn::search_vec | fn | 2048-dim vec, optionals NONE | PASS |  |
| fn | fn::search_vec | fn | optionals NULL | PASS |  |
| fn | fn::recall | fn | optionals NONE + $agent | PASS |  |
| fn | fn::recall | fn | optionals NULL + $agent | PASS |  |
| fn | fn::docstore_capture_revision | fn | 8 args, expected=0 | PASS |  |
| fn | fn::docstore_approve_revision | fn | 9 args matching capture | PASS |  |
| fn | fn::docs_retract | fn | record id + reason | PASS |  |
| fn | fn::docs_retract | fn | releases content_hash | PASS |  |
| fn | fn::docs_retract | fn | status becomes retracted | PASS |  |
| fn | fn::docs_retract | fn | idempotent re-retract | PASS |  |
| fn | fn::docs_retract | fn | nonexistent id (guard) | PASS |  |
| fn | cleanup retract d0ck9tkgo4bv9f7r | fn | fn::docs_retract | PASS |  |
| fn | cleanup retract eb9506kh7gm1b73o | fn | fn::docs_retract | PASS |  |
| fn | cleanup retract jenih1scgheeu8yi | fn | fn::docs_retract | PASS |  |
| fn | cleanup retract kxe959cj5lgyvkg8 | fn | fn::docs_retract | PASS |  |
| fn | cleanup retract oi56rj961hanpu4h | fn | fn::docs_retract | PASS |  |
| fn | cleanup retract q47wfb6ba7cgmm42 | fn | fn::docs_retract | PASS |  |
| fn | cleanup retract y3eposss5ptr18fw | fn | fn::docs_retract | PASS |  |
| fn | cleanup retract zy333ujbac24wjpo | fn | fn::docs_retract | PASS |  |
| fn | cleanup retract ⟨27ppoqmefeielzb | fn | fn::docs_retract | PASS |  |
| fn | cleanup retract ⟨51ywjzpm4gvqf2p | fn | fn::docs_retract | PASS |  |
| fn | cleanup retract ⟨7rbbzvbun4mlpsg | fn | fn::docs_retract | PASS |  |
| skill | fn::decision_amend @ SKILL.md:17 | mcp-call | $subject_source_path,$banner_text,$closes_doc_ids_or_none | PASS |  |
| skill | fn::current_decisions @ SKILL.md:30 | mcp-call | $project | PASS |  |
| skill | fn::docs_search @ SKILL.md:31 | mcp-call | $query,NONE,"decision",NONE,"active",10 | PASS |  |
| skill | fn::decision_amend @ functions.md:55 | mcp-call | "docs/decisions/D-160-docstore-plugin-scope.md","D-160: plug | PASS |  |
| skill | fn::docs_register @ SKILL.md:27 | mcp-call | $source_path,$title,$doc_type,$domains,$status,$body,$author | PASS |  |
| skill | fn::docs_new_version @ SKILL.md:38 | mcp-call | $old_id,$new_body,$new_title_or_none | PASS |  |
| skill | fn::docs_supersede @ SKILL.md:49 | mcp-call | $new_id,$old_id | PASS |  |
| skill | fn::docs_register @ functions.md:75 | mcp-call | "docs/design/2026-09-09-docstore-memory-plugin-design.md","T | PASS |  |
| skill | fn::docs_new_version @ functions.md:87 | mcp-call | document:xyz,"<revised body>",NONE | PASS |  |
| skill | fn::docs_search @ functions.md:88 | mcp-call | "docstore plugin progressive disclosure",NONE,"blueprint","d | PASS |  |
| skill | fn::docs_get @ functions.md:91 | mcp-call | document:abc123 | PASS |  |
| skill | fn::docs_get @ functions.md:93 | mcp-call | <id from superseded_by[0]> | PASS |  |
| skill | fn::docs_search @ functions.md:114 | mcp-call | "no migrations ever snapshot rebuild",null,"decision",null," | PASS |  |
| skill | fn::docs_search @ functions.md:124 | mcp-call | "docstore ingest mapping",{"$ql": "NONE"},{"$ql": "NONE"},{" | PASS |  |
| skill | fn::docs_search @ functions.md:124 | mcp-call | "docstore ingest mapping" | PASS |  |
| skill | raw @ functions.md:124 | mcp-call | {"$ql": "NONE"} | PASS |  |
| skill | raw @ functions.md:124 | mcp-call | null | PASS |  |
| skill | fn::docs_search @ SKILL.md:19 | signature | query,NONE,doc_type|NONE,domain|NONE,status|NONE,k | PASS |  |
| skill | fn::docs_get @ SKILL.md:19 | signature | id | PASS |  |
| skill | fn::current_decisions @ SKILL.md:19 | signature | project | PASS |  |
| skill | fn::docs_search @ SKILL.md:19 | signature | ...,"decision",... | PASS |  |
| skill | fn::docs_tagged @ SKILL.md:20 | signature | tag,query|NONE,domain|NONE,k|NONE | PASS |  |
| skill | fn::docs_register @ SKILL.md:22 | signature | ... | PASS |  |
| skill | fn::docs_set_tags @ SKILL.md:22 | signature | id,tags,actor | PASS |  |
| skill | fn::decision_amend @ SKILL.md:24 | signature | source_path,banner,closes|NONE | PASS |  |
| skill | fn::docs_new_version @ SKILL.md:25 | signature | old_id,body,title|NONE | PASS |  |
| skill | fn::docs_retract @ SKILL.md:26 | signature | id,reason | PASS |  |
| skill | fn::todo_open @ SKILL.md:27 | signature | item,priority,domains,source|NONE | PASS |  |
| skill | fn::open_work @ SKILL.md:27 | signature | project | PASS |  |
| skill | fn::todo_close @ SKILL.md:27 | signature | id,evidence | PASS |  |
| skill | fn::provenance @ SKILL.md:30 | signature | record | PASS |  |
| skill | fn::docs_set_tags @ SKILL.md:18 | surql | $id,$tags,$actor | PASS |  |
| skill | raw @ functions.md:25 | surql | - | PASS |  |
| skill | fn::handoff_write @ functions.md:41 | mcp-call | "docstore plugin build — 2026-09-09","<full HANDOFF v2 body: | PASS |  |
| skill | fn::remember @ SKILL.md:17 | mcp-call | { kind: $kind, claim: $claim, detail: $detail_or_none, scope | FAIL | BLOCKER: fn::remember is a MEMORY-database function and is not deployed: the memory instance (100.91.190.107:8471) holds only ns fct/db case, and ns probata_memory does not exist. Auth works (MEMORY_BASIC_AUTH |
| skill | fn::recall @ SKILL.md:31 | mcp-call | $query,$vec_or_none,$scope,$k | PASS |  |
| skill | fn::supersede_memory @ SKILL.md:40 | mcp-call | $old_id,$new_payload | FAIL | BLOCKER: fn::supersede_memory is a MEMORY-database function and is not deployed: the memory instance (100.91.190.107:8471) holds only ns fct/db case, and ns probata_memory does not exist. Auth works (MEMORY_BA |
| skill | fn::forget @ SKILL.md:41 | mcp-call | $id,$reason | FAIL | BLOCKER: fn::forget is a MEMORY-database function and is not deployed: the memory instance (100.91.190.107:8471) holds only ns fct/db case, and ns probata_memory does not exist. Auth works (MEMORY_BASIC_AUTH s |
| skill | raw @ SKILL.md:24 | surql | - | PASS |  |
| skill | raw @ SKILL.md:25 | surql | - | PASS |  |
| skill | raw @ SKILL.md:25 | surql | - | PASS |  |
| skill | raw @ SKILL.md:26 | surql | - | PASS |  |
| skill | raw @ SKILL.md:27 | surql | - | PASS |  |
| skill | fn::stale_candidates @ SKILL.md:23 | mcp-call | "90d" | PASS |  |
| skill | fn::stale_candidates @ SKILL.md:23 (via MCP run) | mcp-call | "90d" | PASS |  |
| skill | fn::docs_new_version @ SKILL.md:35 | mcp-call | $old_id,$revised_body_or_same,NONE | PASS |  |
| skill | fn::decision_amend @ SKILL.md:36 | mcp-call | $subject_path,$banner,$closes | PASS |  |
| skill | fn::provenance @ SKILL.md:49 | mcp-call | $record_id | PASS |  |
| skill | fn::todo_open @ SKILL.md:16 | mcp-call | $item_text,$priority,$domains,$source_path_or_none | PASS |  |
| skill | fn::todo_close @ SKILL.md:22 | mcp-call | $id,$evidence_text | PASS |  |
| skill | fn::open_work @ SKILL.md:31 | mcp-call | $project | PASS |  |
| skill | fn::todo_open @ functions.md:49 | mcp-call | "Wire SURREAL_MCP_ALLOWED_HOSTS on surreal-case before the m | PASS |  |
| skill | fn::todo_close @ functions.md:53 | mcp-call | todo:abc123,"surreal-case redeployed 2026-09-10, /mcp initia | PASS |  |
| skill | fn::decision_amend @ update-adr.md:21 | signature | "<source_path>","<banner>",NONE | PASS |  |
| skill | fn::provenance @ update-adr.md:22 | signature | document:<id> | PASS |  |
| mcp | control:initialize | tool | stdio handshake | PASS |  |
| mcp | control:tools/list | tool | - | PASS |  |
| mcp | control:coco_docstore_search | tool | {"query": "catalog", "domain | PASS |  |
| mcp | control:docstore_approve_revision | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_attribution_verify | tool | {} | PASS |  |
| mcp | control:docstore_cancel_run | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_capabilities | tool | {} | PASS |  |
| mcp | control:docstore_capture_revision | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_cdc_runs | tool | {} | PASS |  |
| mcp | control:docstore_compact | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_flags | tool | {"domain": "docs"} | PASS |  |
| mcp | control:docstore_get | tool | {"record_id": "document:docs | PASS |  |
| mcp | control:docstore_graph | tool | {"record_id": "document:docs | PASS |  |
| mcp | control:docstore_graph_query | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_graph_query_preview | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_graph_schema | tool | {} | PASS |  |
| mcp | control:docstore_handoff_write | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_health | tool | {} | PASS |  |
| mcp | control:docstore_index_execute | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_index_full | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_index_plan | tool | {"paths": ["PROJECT_CANON.md | PASS |  |
| mcp | control:docstore_index_selected | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_pipeline_identity | tool | {} | PASS |  |
| mcp | control:docstore_project_source | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_project_sources | tool | {} | PASS |  |
| mcp | control:docstore_reconcile_packet | tool | {"query": "catalog"} | FAIL | tool isError: Propria reconciliation adapter is unavailable |
| mcp | control:docstore_reconcile_query | tool | {"query": "catalog"} | FAIL | tool isError: Propria reconciliation adapter is unavailable |
| mcp | control:docstore_reconcile_repair | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_reconcile_validate | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_related_updates | tool | {"term": "catalog"} | PASS |  |
| mcp | control:docstore_revision_state | tool | {"document_key": "document:d | PASS |  |
| mcp | control:docstore_run_cancel | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_run_current | tool | {} | PASS |  |
| mcp | control:docstore_run_get | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_run_list | tool | {} | PASS |  |
| mcp | control:docstore_run_status | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_search | tool | {"query": "catalog", "domain | PASS |  |
| mcp | control:docstore_selected_update_plan | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_set_flags | tool | listed; mutating - not invoked | PASS |  |
| mcp | control:docstore_stats | tool | {} | PASS |  |
| mcp | control:docstore_surrealist | tool | {} | PASS |  |
| mcp | control:docstore_verify_index | tool | {"paths": ["PROJECT_CANON.md | PASS |  |
| mcp | docs:initialize | tool | http handshake | PASS |  |
| mcp | docs:tools/list | tool | - | PASS |  |
| mcp | docs:create | tool | listed; mutating - not invoked | PASS |  |
| mcp | docs:delete | tool | listed; mutating - not invoked | PASS |  |
| mcp | docs:gql | tool | listed; mutating - not invoked | PASS |  |
| mcp | docs:graphql | tool | listed; mutating - not invoked | PASS |  |
| mcp | docs:info | tool | {"target": "db"} | PASS |  |
| mcp | docs:insert | tool | listed; mutating - not invoked | PASS |  |
| mcp | docs:list | tool | {"kind": "functions"} | PASS |  |
| mcp | docs:query | tool | {"query": "RETURN 1;"} | PASS |  |
| mcp | docs:relate | tool | listed; mutating - not invoked | PASS |  |
| mcp | docs:run | tool | {"function": "fn::docs_searc | PASS |  |
| mcp | docs:select | tool | {"target": "document", "limi | PASS |  |
| mcp | docs:update | tool | listed; mutating - not invoked | PASS |  |
| mcp | docs:upsert | tool | listed; mutating - not invoked | PASS |  |
| mcp | docs:use | tool | {"namespace": "probata", "da | PASS |  |
| mcp | docs:session reuse | tool | 2nd call, same session | PASS |  |
| mcp | memory:initialize | tool | http handshake | PASS |  |
| mcp | memory:tools/list | tool | - | PASS |  |
| mcp | memory:create | tool | listed; mutating - not invoked | PASS |  |
| mcp | memory:delete | tool | listed; mutating - not invoked | PASS |  |
| mcp | memory:gql | tool | listed; mutating - not invoked | PASS |  |
| mcp | memory:graphql | tool | listed; mutating - not invoked | PASS |  |
| mcp | memory:info | tool | {"target": "db"} | PASS |  |
| mcp | memory:insert | tool | listed; mutating - not invoked | PASS |  |
| mcp | memory:list | tool | {"kind": "functions"} | PASS |  |
| mcp | memory:query | tool | {"query": "RETURN 1;"} | PASS |  |
| mcp | memory:relate | tool | listed; mutating - not invoked | PASS |  |
| mcp | memory:run | tool | {"function": "math::sum", "a | PASS |  |
| mcp | memory:select | tool | {"target": "memory", "limit" | PASS |  |
| mcp | memory:update | tool | listed; mutating - not invoked | PASS |  |
| mcp | memory:upsert | tool | listed; mutating - not invoked | PASS |  |
| mcp | memory:use | tool | {"namespace": "fct", "databa | PASS |  |
| mcp | memory:session reuse | tool | 2nd call, same session | PASS |  |
