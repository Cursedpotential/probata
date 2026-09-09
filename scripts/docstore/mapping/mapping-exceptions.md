# Mapping exceptions — D-156 docs ingest

> _Byline: Claude Code (subagent) · Sonnet 5 · 2026-09-09_

Total exceptions: 48

| path | reason | proposed handling |
|---|---|---|
| docs/awaiting-verification/atomic-parse-driver-20260906/build/atomicparse-linux-amd64 | binary/non-text content (binary (NUL byte)) | leave in place |
| docs/planning/forensic-db-reconciliation/RECONCILED_SCHEMA.sql | excluded extension .sql | reference asset (leave in place / do not ingest as doc) |
| docs/planning/forensic-db-reconciliation/live-introspection/PG_live_schema.sql | excluded extension .sql | reference asset (leave in place / do not ingest as doc) |
| docs/planning/forensic-db-reconciliation/live-introspection/PG_pre_0005.sql | excluded extension .sql | reference asset (leave in place / do not ingest as doc) |
| docs/planning/forensic-db-reconciliation/migrations/0005_forensic_reconciliation.sql | excluded extension .sql | reference asset (leave in place / do not ingest as doc) |
| docs/planning/forensic-db-reconciliation/migrations/0006_behavior_seed.sql | excluded extension .sql | reference asset (leave in place / do not ingest as doc) |
| docs/planning/forensic-db-reconciliation/migrations/0007_behavior_seed_sweep.sql | excluded extension .sql | reference asset (leave in place / do not ingest as doc) |
| docs/planning/forensic-db-reconciliation/migrations/0008_behavior_seed_pattern_analyzer.sql | excluded extension .sql | reference asset (leave in place / do not ingest as doc) |
| docs/recovered/graphrag_comparison_activities.cpython-313.pyc | binary/non-text content (binary (NUL byte)) | leave in place |
| docs/recovered/graphrag_comparison_workflow.cpython-313.pyc | binary/non-text content (binary (NUL byte)) | leave in place |
| docs/recovered/graphrag_contracts.cpython-313.pyc | binary/non-text content (binary (NUL byte)) | leave in place |
| docs/recovered/graphrag_repository.cpython-313.pyc | binary/non-text content (binary (NUL byte)) | leave in place |
| docs/recovered/semantica_comparison_adapter.cpython-313.pyc | binary/non-text content (binary (NUL byte)) | leave in place |
| docs/research/integration-audit-2026-08-24/_raw_weaviate_8081_schema.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/_raw_weaviate_8082_schema.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/composed/validate-composed.py | excluded extension .py | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/composed/wf-classify-batch.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/composed/wf-error-handler.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/composed/wf-intake-dropdir.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/composed/wf-judge-gate.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/composed/wf-persist-results.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/extracted/awesome-hallucination-detection.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/extracted/awesome-multimodel-fallback.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/extracted/awesome-sentiment-analysis.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/extracted/template-12316-multi-model-council.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/extracted/template-1326-error-alert-skeleton.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/extracted/template-15229-confidence-gate-pattern.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/extracted/template-3297-dropbox-db-diff-intake-skeleton.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/extracted/template-7633-batch-classify.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/npm-community-node-catalog.jsonl | excluded extension .jsonl | reference asset (leave in place / do not ingest as doc) |
| docs/research/integration-audit-2026-08-24/npm-community-node-catalog.raw.jsonl | excluded extension .jsonl | reference asset (leave in place / do not ingest as doc) |
| docs/reviews/2026-08-23-cross-repo-evidence-audit/sibling-session-59068f99/state.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/reviews/2026-08-25-schema-audit/COMPREHENSIVE-PATH-REVIEW.html | excluded extension .html | reference asset (leave in place / do not ingest as doc) |
| docs/reviews/2026-08-25-schema-audit/GAP-019-live-receipt-2026-08-26.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/reviews/2026-08-25-schema-audit/SBV-GO-TEMPORAL-RUNTIME-BOUNDARY.html | excluded extension .html | reference asset (leave in place / do not ingest as doc) |
| docs/reviews/2026-08-29-production-workbench-intake-final.png | binary/non-text content (binary (NUL byte)) | leave in place |
| docs/reviews/2026-08-31-external-reviews/uncommitted-work-report-2026-08-31.html | excluded extension .html | reference asset (leave in place / do not ingest as doc) |
| docs/schema/ai-schema-reckoning.html | excluded extension .html | reference asset (leave in place / do not ingest as doc) |
| docs/schema/catalog.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/schema/three-message-shapes.html | excluded extension .html | reference asset (leave in place / do not ingest as doc) |
| docs/schemas/document-markdown-v1.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/schemas/variants/chronology-v1.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/schemas/variants/research-report-v1.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/schemas/variants/statute-extract-v1.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/schemas/variants/strategy-memo-v1.json | excluded extension .json | reference asset (leave in place / do not ingest as doc) |
| docs/semantica | git symlink (mode 120000) checked out on Windows as a plain-text path placeholder, not real content | leave in place; not a document (points into server/vendored/semantica/) |
| docs/semantica-benchmarks | git symlink (mode 120000) checked out on Windows as a plain-text path placeholder, not real content | leave in place; not a document (points into server/vendored/semantica/) |
| docs/visualizations/visit_locations_2023_map.html | excluded extension .html | reference asset (leave in place / do not ingest as doc) |


Note: 15 files already quarantined under `probata/to_be_deleted/docs-junk-20260909/` (all 15 inventory rows whose proposed status was `not ingested; owner deletes`) are excluded entirely from both the mapping CSV and this exceptions list, per job instructions.

## Non-markdown rows kept in the mapping but never declared by the flow (found 2026-09-09 08:01 EDT)

`flow_docs.py` (`load_doc_metas`) declares only `.md` source paths. These 14 rows carry a doc_type in the CSV yet cannot be ingested until the owner rules on them; run 4 (07:52) confirmed they are the non-swallowed part of the 29 missing.

| source_path | mapped type | recommendation |
|---|---|---|
| docs/awaiting-verification/atomic-parse-driver-20260906/go.mod | blueprint | code, exclude |
| docs/awaiting-verification/atomic-parse-driver-20260906/go.sum | blueprint | code, exclude |
| docs/awaiting-verification/atomic-parse-driver-20260906/main.go | blueprint | code, exclude |
| docs/planning/forensic-db-reconciliation/live-introspection/MILVUS_live.txt | blueprint | introspection dump, exclude |
| docs/planning/forensic-db-reconciliation/live-introspection/NEO4J_live.txt | blueprint | introspection dump, exclude |
| docs/planning/forensic-db-reconciliation/live-introspection/PG_dump.err | blueprint | empty error file, exclude |
| docs/planning/forensic-db-reconciliation/live-introspection/PG_live_summary.txt | blueprint | introspection dump, exclude |
| docs/planning/forensic-db-reconciliation/live-introspection/PG_live_types.txt | blueprint | introspection dump, exclude |
| docs/planning/forensic-db-reconciliation/live-introspection/SURREAL_live.txt | blueprint | introspection dump, exclude |
| docs/planning/forensic-db-reconciliation/migrations/0005_acceptance.txt | blueprint | migration log, exclude |
| docs/planning/forensic-db-reconciliation/migrations/0005_apply_log.txt | blueprint | migration log, exclude |
| docs/planning/forensic-db-reconciliation/migrations/0006_apply_log.txt | blueprint | empty log, exclude |
| docs/recovered/GRAPHRAG-RECOVERED-FROM-BYTECODE.txt | reference | ingest as reference if wanted (allow `.txt` for this row) |
| docs/schemas/platform-intake-job-contract-v1.openapi.yaml | reference | ingest as reference if wanted (allow `.yaml` for this row) |
