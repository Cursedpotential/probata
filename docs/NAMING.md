# Naming Canon

> _Byline: Claude Code · Fable 5.1 · 2026-09-05._

This is the canonical naming register for the product rename ruled 2026-09-05
(D-137 through D-141). It is the single source of truth for old→new names across
this repository. When any other document asserts an old name as current canon,
it must carry a visible strike-through + dated correction pointing back here
(doc-drift rule, `AGENTS.md`).

**Execution status:** naming is RULED at the product and component tier. GitHub
repo rename (`Cursedpotential/mcp-platform-agno-mvp` → `Cursedpotential/probata`)
and Go module path rename (`github.com/Cursedpotential/probata/engine`) are
authorized per D-138/D-140 text and reflected in `docs/DECISION_LOG.md`'s git
status header; verify current repo/module state against live `git remote -v`
and `go.mod` before assuming the mechanical rename has executed everywhere —
this document owns naming intent, not a deployment attestation.

## 1. Product tier

| Full name | Short form | What it is | Decision | Identifier status |
|---|---|---|---|---|
| **propria** | `propria` | Umbrella product name, from *in propria persona* (the self-represented litigant speaking in their own person). Not a repository — a brand covering the whole family below. | D-137 | New; no legacy identifiers to migrate. |
| **Indicia Probata** | `probata` | The evidence-record product: ingest, sorting, custody, normalize. **This repository.** Latin "proven signs" (neuter plural noun + agreeing participle). | D-138 | GitHub repo `Cursedpotential/mcp-platform-agno-mvp` → `Cursedpotential/probata`; Go module → `github.com/Cursedpotential/probata/engine`; Coolify app prefix `probata-*`; tsnet service identities `probata-*`. |
| **Indagatio Veri** (proposed full form) | `indagatio` | The analysis engine: horizon walks, ignorant/hindsight agents, the delta, SurrealDB as its store (D-073/D-080). Splits off from `probata` as its own product with its own Go front end and its own tsnet identity (D-134). Full form from Cicero, *De Officiis* I.13: *propria veri inquisitio atque investigatio* — "the search and investigation of truth is proper to man" — ties the umbrella and this product in one attested sentence. | D-139 | Short form `indagatio` ruled; full form offered, not ruled. What moves out of `probata` and the boundary contract are a separate, not-yet-written plan — nothing has split yet. |
| **consignatio** | `consignatio` | The Vault / Case Bible system. Latin: the affixing of a seal; an attested document; written proof — the custody guarantee itself, not merely a storeroom. | D-141 (vacates and replaces the D-138 slot `vestigia`, which moved to geo under D-140) | 
| **advocatio** | `advocatio` | The legal workbench (`Legal-Workspace` repo). Twist on the rejected `advocatus` (collides with Advocatus Digital / AdvocatusMobile / advocatus.ro). | D-138 | `Legal-Workspace` repo itself is **not renamed yet** (see §3). |
| **vestigia** | `vestigia` | The geo product ("footprints, tracks"). Replaces `traceIQ` as the product name. | D-140 | `traceIQ` repo and its identifiers are **not renamed** by this entry (see §3). |

Chain of custody in one sentence (D-141): INFORMATION is deposited into
**consignatio**, proffered through **probata**, admitted into evidence,
investigated by **indagatio**, argued from **advocatio**, located by
**vestigia**.

## 2. Component tier

Component rule (standing, D-131/D-138): **lowercase functional names, never
brands.** A component's name describes what it does, not what product it
belongs to.

| Component | Name | What it is | Decision |
|---|---|---|---|
| Backend/Go monorepo module | `engine` | The Go engine under `modules/engine/` (own `go.mod`) | D-131 |
| Product UI + API shell | `workbench` | `modules/workbench/` (FastAPI + Next.js) | D-131 |
| Parser execution surface | `parser-runtime` | Tool-gateway-adjacent parser execution | D-131 |
| Cross-domain tool registry | `tool-gateway` | `server/tools/` gateway | D-131 |
| Format decoder library | `decode` | SBV-donor-derived decoder set, destined for `modules/engine/decode/` | D-131 |
| Import lane (was `uiw`) | `proffer` | Custody-preserving ingest lane — Go package `proffer`, worker binary `proffer-worker`, starter binary `proffer-starter`, Temporal task queue `proffer-v1`, workflow type `ProfferWorkflow`, Python package `server/proffer/` | D-140 |
| Operator client (desktop ingest) | `intake` | The D-123 desktop ingest client | ruled D-150 (2026-09-06)|
| Promotion activity family | `admit` | The activity family that promotes proffered records into `evidence.*` (evidence is *admitted* into the record) | Proposed, not yet ruled |

## 3. Old → new glossary

| Old | New | Scope of change | Notes |
|---|---|---|---|
| `Agno-MCP-Platform` (as a product name) / "Temporal Evidence and Agent Experience Platform" | **Indicia Probata** / `probata` | Product name, README title, repo | The local checkout directory name (`Agno-MCP-Platform/`) and the GitHub repo `Cursedpotential/mcp-platform-agno-mvp` are the same underlying identifier being renamed to `probata`; the local folder path HAS BEEN CHANGED |
| `mcp-platform-agno-mvp` (GitHub repo) | `probata` (`Cursedpotential/probata`) | Repo identifier, Coolify remotes, parent gitlink | D-138 |
| UIW / Universal Import Workflow / `uiw` / `uiwworker` / `universal-import-worker` / `universal-import-starter` / task queue `universal-import-v1` / Python `server/ingest/` | **proffer** — package `proffer`, binaries `proffer-worker` / `proffer-starter`, queue `proffer-v1`, workflow type `ProfferWorkflow`, Python `server/proffer/` | Go packages, binaries, Temporal queue name, workflow type, Python package | D-140 |
| `traceIQ` (product name) | **vestigia** (product name only) | Product/brand name | D-140. traceIQ's repo, `modules/traceIQ/`, and its internal identifiers are **NOT renamed** — this is a naming-tier change only, not an execution order. |
| Case Bible / Vault (product name) | **consignatio** (product name only) | Product/brand name | D-141. `casebible-*` R2 buckets, the `casebible` database / `ai.casebible_*` table prefix (not a PG schema), the `cb-*` command family, and the catalog skill are **NOT renamed** — same reservation as D-138 item 2, restated in D-141. |
| `Legal-Workspace` (product name) | **advocatio** (product name only) | Product/brand name | D-138. The `Legal-Workspace` repository itself is **NOT renamed yet.** |
| (analysis engine, previously undifferentiated inside this repo) | **Indagatio Veri** / `indagatio` | New product identity, split-off pending | D-139. Nothing has physically split out of this repo yet; see §1. |

## 4. Rejected names, with collision reasons

Copied verbatim from `docs/DECISION_LOG.md` D-138/D-140/D-141 (2026-09-05
collision checks). Do not re-propose these without new information.

**Evidence-record product / umbrella slot (D-138):**
`openspine` (owner: grotesque); `indicia` alone (`indicia.app`, live OSINT
forensics platform — same field); `indica` (cannabis connotation); `indicium`
(Thinkwise app tier, INDICIUM DM suite, Indicium AI); `tessera` (Tessera Data,
criminal-records vendor); `mosaic` (Mosaic Legal Ops); `advocatus` (Advocatus
Digital, AdvocatusMobile, advocatus.ro); `indicata` (Italian analytics firm);
`horizon`, `antecedent`, `priora`, `testimonium`, `palimpsest`, `sequela`,
`ordo`, `firsthand`, `verbatim` (owner: did not like).

**Vault / Case Bible product slot (D-140, D-141):**
`tabularium` DEAD (Tabularium AI — official records/deeds platform; plus a PDF
evidence-numbering tool and five others); `custodia` DEAD (Custodia
Technology — regulated data capture with WORM/integrity archiving, same
space); `scrinium` (Roman document chest — fintech, a reading tracker, a text
tool; none legal); `archa` (homophone of `arca.legal`, a funded legal-AI
platform — unsafe when spoken aloud in court); `cella` (three unrelated
companies; reads as "storeroom"); `horreum` (Hyperfoil's results-repository
service + Horreum Apps); `reconditorium` (UK security firm); `thesaurus` /
`firmamentum` (modern meanings dominate); `crypta` (tone); `depositum` /
`arca` / `armarium` (clean, not chosen).

## 5. Rules

1. **Products get proper names.** A product (something a person outside the
   engineering team would refer to by name) gets a real word or Latin-derived
   name, collision-checked against live products/companies in the same field
   before it is ruled — see §4 for the rejection process this repo actually
   uses.
2. **Components get functional lowercase names, never brands.** `engine`,
   `workbench`, `proffer`, `intake`, `admit`, `decode`, `tool-gateway`,
   `parser-runtime` — none of these are proper nouns, and none should ever
   become one.
3. **Forks keep the upstream name.** A fork tracks upstream, rebases, and may
   contribute back — it keeps the name the upstream project uses (D-131).

   PER OWNER--
   WE WILL NOT BE CONTRIBUTING BACK. MOST OF OUR FORKS ARE HEAVILY MODIFIED OR STRUPPED THAT THEY END UP DONORS 
4. **Donors are named for what they are now.** A donor has had its guts
   extracted, permanently diverged, and has no rebase path — it is named for
   its current function with provenance credited in-file, not for its origin
   (D-131; e.g. the SBV donor becomes `modules/engine/decode/` with
   `UPSTREAM.md` carrying attribution to lowcarbdev).
5. **One conce/pt, one name.** A renamed concept does not keep its old name as
   a synonym in new writing. Old names survive only as glossary entries (this
   file) and inside historical documents that are explicitly not rewritten
   (see the doc-drift rule in `AGENTS.md` and `docs/DECISION_LOG.md`).

## 6. Identifiers intentionally NOT renamed

Renaming a product's marketing/brand name is a different decision from
renaming its technical identifiers, and the owner has repeatedly kept these
separate to avoid needless churn across buckets, schemas, and tooling that
already work. The following are **intentionally frozen** even though their
parent product has a new name:

- `casebible-*` R2 buckets, the `casebible` database, `ai.casebible_*` table prefix, and Weaviate 
  namespace (an earlier revision of this line said "schema" — no such PG schema exists; live schemas are 
  ai, analysis, archive, canon, context, duckdb, evidence, ext, ops, public, raw, reference, registry, 
  timeline, working), the catalog skill, and every `cb-*` command (`cb-status`, `cb-sync`, `cb-custody`, …) 
  — even though the product is now **consignatio** (D-141, restating D-138 item 2). 
- The `traceIQ` repository and its internal module/identifier names — even
  though the product is now **vestigia** (D-140). traceIQ's repo is not
  renamed by any entry through D-141.
- The `Legal-Workspace` repository name — even though the product is now
  **advocatio** (D-138). Not renamed yet.
- `modules/forks/sbv` and `modules/forks/timesketch` — these are forks OR DONORS, so per
  rule 3 above they correctly keep their upstream names and are NOT CURRENTLY
  subject to this rename at all.


## 7. Related decisions

`docs/DECISION_LOG.md`: D-131 (donor/fork distinction, component rule),
D-134 (indagatio's own tsnet identity), D-137 (`propria` umbrella), D-138
(product naming canon, rejected names), D-139 (`indagatio` / *Indagatio
Veri*), D-140 (`proffer`, `vestigia` moves to geo), D-141 (`consignatio`,
naming canon complete at product tier). See also `docs/adr/` for any ADR
that references component names directly (never rewritten by this sweep —
ADRs are append-only signed records).


OWNER REVISED 9/8/26
