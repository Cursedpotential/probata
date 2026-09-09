# Mapping validation — D-156 docs ingest
> _Byline: Claude Code (subagent) · Sonnet 5 · 2026-09-09_

Source CSV: `C:/Users/matts/.claude/jobs/68afe1c5/tmp/out\docs-ingest-mapping.csv`

Total rows: **503**

## Counts per doc_type

| doc_type | count |
|---|---|
| review | 167 |
| blueprint | 154 |
| decision | 65 |
| handoff | 63 |
| reference | 39 |
| todo | 12 |
| infrastructure | 3 |

## Counts per status

| status | count |
|---|---|
| active | 288 |
| superseded | 152 |
| unverified | 62 |
| proposed | 1 |

## Counts per domain (unnested from `|`-separated list)

| domain | count |
|---|---|
| docs | 178 |
| consignatio | 100 |
| proffer | 97 |
| indagatio | 49 |
| infra | 37 |
| memory | 35 |
| knowledge | 28 |
| workbench | 25 |
| vestigia | 22 |
| intake | 21 |
| advocatio | 19 |
| probata | 5 |

## Assertions

- **doc_type in ruled set**: PASS (0 violation(s))
- **status in ruled set**: PASS (0 violation(s))
- **domains in ruled set (all tokens)**: PASS (0 violation(s))
- **domains never empty**: PASS (0 violation(s))
- **no duplicate mirror_path**: PASS (0 duplicate group(s))
- **every supersedes_path exists on disk**: PASS (0 violation(s) out of 43 populated)
- **no duplicate source_path**: PASS (0 violation(s))
- **every source_path exists on disk**: PASS (0 violation(s))
