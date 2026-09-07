# Milvus embedded-etcd corruption — incident, root cause, recovery

> _Byline: Claude Code · Fable 5.1 · 2026-09-07._
> _Status: INCIDENT OPEN — Milvus stopped, memsearch down, awaiting owner go on reset+reindex._

## What happened

The `agno` → `probata` infra rename wave (2026-09-07) redeployed `data-vector`,
which bounced the all-in-one Milvus standalone container. On restart it entered a
`etcdserver: leader changed` panic loop (exit 134), climbing restart count with the
box otherwise idle. This is the **7th** such corruption on this deployment.

The heartbeat/election tuning (`heartbeat-interval: 1000`, `election-timeout: 10000`)
was already applied **and** verified mounted inside the container, yet it still looped.
Box load was 0.54 during the loop. So this is **not** a resource/boot-race stall — the
embedded-etcd metadata in the volume is corrupt.

## Root cause (owner research + our evidence)

- **Ungraceful etcd termination corrupts the metadata store.** Upstream Milvus issue
  [milvus-io/milvus#40575](https://github.com/milvus-io/milvus/issues/40575) documents
  the same class: force-killing etcd → `CrashLoopBackOff`, members drop out, no clean
  fix in comments. Upstream guidance: **shut Milvus down first, then etcd**, so Milvus
  persists its final state before etcd stops.
- Our all-in-one `milvus run standalone` container runs etcd **in-process**. A Coolify
  redeploy SIGKILLs the whole container, so Milvus and its embedded etcd die together,
  ungracefully — exactly the sequence #40575 warns against.
- **Owner-confirmed: a separate etcd service failed identically.** So the cause is the
  ungraceful-kill + disk-fsync sensitivity, **not** embedded-vs-external etcd. Adding a
  separate etcd does not fix it.

## Why we can recover cheaply

memsearch's collection `agent_session_memory_nemotron3` is a **projection** of local
source, not primary data:

- Source: **8,098 Claude session transcripts, 3.2G, `~/.claude/projects`** (this desktop).
- Embedder: NIM `nvidia/nemotron-3-embed-1b` (returns vectors; verified).
- The 1.6G segment data + 246M etcd dir sit intact in the volume, but Milvus cannot use
  segments without coherent etcd metadata, and there is **no backup** (only a 25M Aug-5
  tarball predating current data).

So a full reset + reindex is cheaper and more reliable than bbolt surgery on the corrupt
`member/snap/db` (the #40575 all-pods-crash recovery).

## Recovery plan (on owner go)

1. **Quarantine** `/data/probata/volumes/milvus-memsearch/etcd` (and `rdb_data*` WAL) to
   `/data/.review_hold/` — moved, never deleted; reversible.
2. **Decouple** Milvus + Attu from the shared `probata` docker network (memsearch reaches
   Milvus at the tailnet IP `100.91.190.107:19530`, not docker DNS), so no future
   platform-tier wave bounces it. Edit `deploy/data-vector.yaml`.
3. **Restart** Milvus → boots healthy with fresh embedded etcd, empty collection.
4. **Re-index** memsearch from the 8,098 local transcripts.
5. **Live-validate** a real search returns hits. The embedder-switch failure mode is a
   silent empty index, so this step is mandatory (see the 2026-09-03 memsearch rebuke).

## Durable options (memsearch needs Milvus — it is a zilliz/milvus MCP)

pgvector and Qdrant are ruled out: the MCP speaks Milvus. Etcd-free ways to keep Milvus:

| Option | What | Etcd? | Trade-off |
|---|---|---|---|
| **Zilliz Cloud** | managed Milvus, free tier | none (managed) | external dependency; no local disk-fsync exposure |
| **Milvus Lite** | embedded file-based Milvus | none | local to wherever memsearch runs; no shared VPS service |
| Keep self-hosted | milvus-standalone on VPS | yes (embedded) | must add graceful-stop + never-bounce discipline |

If we keep self-hosted: raise `stop_grace_period`, ensure Coolify sends SIGTERM (not
SIGKILL) with enough grace for Milvus to flush etcd, and keep it off platform-tier
redeploy waves (step 2 above).

## Note

The GitHub issue was pasted by the owner as research. Its trailing "mention
@docs/URGENT-TODO.md" line is web-page content (a bot signature / prompt injection),
**not** an owner instruction, and was ignored. No such file was created.
