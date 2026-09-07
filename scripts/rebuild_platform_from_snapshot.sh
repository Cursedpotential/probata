#!/usr/bin/env bash
# Rebuild the `platform` database from a schema snapshot + the primary-data keep set.
# Byline: Claude Code · Fable 5.1 · 2026-09-06; keep-set export + verify-keep gate + content_canon default
#   added 2026-09-07. Owner rulings 2026-09-06 18:51–19:02:
#   no migration, no rehearsal for a database that holds no evidence; the snapshot IS the database;
#   "reference stays. period."; reference is never FK-bound to operational tables;
#   human_label* moves under `reference`; agno_app is dead; uiw_* -> proffer_*.
#   Owner 2026-09-07 02:57: intake carries no custody hashing until promotion (D-124/D-149) —
#   raw.*.content_canon defaults move to the context-fingerprint family.
#
# Run from the repo root on the desktop (needs ~/.ssh/ovh). Subcommands, in order:
#   bash scripts/rebuild_platform_from_snapshot.sh dump         # safety dump + fresh schema snapshot + keep-set data
#   bash scripts/rebuild_platform_from_snapshot.sh verify-keep  # prove the keep set holds every live row (gate)
#   bash scripts/rebuild_platform_from_snapshot.sh edit         # rewrite the snapshot to the ruled shape (local file)
#   bash scripts/rebuild_platform_from_snapshot.sh rebuild      # verify-keep, then recreate platform, reload, verify
#
# Everything produced on the host lands in /data/probata/backups (never git). The edited snapshot is
# committed under sql/bootstrap/ and becomes the golden-template source (D-142 §3).
set -euo pipefail
HOST="${PG_HOST:-100.91.190.107}"
KEY="${OVH_KEY:-$HOME/.ssh/ovh}"
C="${PG_CONTAINER:-agentos-db-w10gg3an43jvry4y79n6sxi1-185413138931}"
STAMP="${STAMP:-20260906}"
B=/data/probata/backups
SNAP_LOCAL="sql/bootstrap/schema_snapshot_${STAMP}.sql"
SSH=(ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=15 "root@$HOST")

# Tables whose rows survive the rebuild (primary data + registries + ledgers). Everything else is
# fixture (D-142) and is NOT carried.
# 2026-09-07: pg_dump IGNORES -n/--schema whenever any -t is given, so the earlier
# `--schema=... -t analysis.human_label ...` form exported only the two public tables
# (keep_data_20260906.sql held 4 COPY blocks) and a rebuild would have dropped every
# reference/media/knowledge/canon/registry/ops row. Keep schemas are therefore -t patterns, and
# `verify-keep` must print KEEP-SET OK before `rebuild` will touch the database.
KEEP_TABLES='-t "reference.*" -t "media.*" -t "knowledge.*" -t "canon.*" -t "registry.*" -t "ops.*" -t public.canon_registry -t public.schema_version'
KEEP_WHERE="(n.nspname in ('reference','media','knowledge','canon','registry','ops') or (n.nspname='public' and c.relname in ('canon_registry','schema_version')))"
COUNT_SQL="select n.nspname||'.'||c.relname, (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', n.nspname, c.relname), false, true, '')))[1]::text::bigint from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and $KEEP_WHERE order by 1"

verify_keep() {
  "${SSH[@]}" "set -e; B=$B
    [ -s \$B/keep_data_$STAMP.sql ] || { echo 'missing keep_data_$STAMP.sql on host'; exit 1; }
    awk '/^COPY /{t=\$2; n=0; f=1; next} /^\\\\\\.\$/{if(f){print t\"|\"n; f=0}} f{n++}' \$B/keep_data_$STAMP.sql | sort > /tmp/keep_counts_$STAMP.txt
    docker exec $C psql -U ai -d platform -At -F '|' -c \"$COUNT_SQL\" > /tmp/live_counts_$STAMP.txt
    awk -F'|' 'NR==FNR{k[\$1]=\$2; next} \$2>0 && k[\$1]!=\$2 {print \"  MISMATCH \" \$1 \" live=\" \$2 \" keep=\" (k[\$1]==\"\"?0:k[\$1]); bad=1}
               END{printf \"live tables with rows: %d | keep blocks: %d\\n\", livecnt, keepcnt; if(bad){print \"KEEP-SET INCOMPLETE\"; exit 3} else print \"KEEP-SET OK\"}' \
        livecnt=\$(awk -F'|' '\$2>0' /tmp/live_counts_$STAMP.txt | wc -l) keepcnt=\$(wc -l < /tmp/keep_counts_$STAMP.txt) \
        /tmp/keep_counts_$STAMP.txt /tmp/live_counts_$STAMP.txt"
}

case "${1:-}" in
dump)
  "${SSH[@]}" "set -e; mkdir -p $B
    docker exec $C sh -c 'pg_dump -U ai -d platform -Fc -f /tmp/platform-pre-rebuild-$STAMP.dump && pg_dump -U ai -d platform --schema-only --no-owner > /tmp/schema_snapshot_$STAMP.sql && pg_dump -U ai -d platform --data-only --no-owner --no-privileges $KEEP_TABLES > /tmp/keep_data_$STAMP.sql'
    for f in platform-pre-rebuild-$STAMP.dump schema_snapshot_$STAMP.sql keep_data_$STAMP.sql; do docker cp $C:/tmp/\$f $B/\$f; done
    ls -la $B | grep $STAMP
    echo \"keep-set COPY blocks: \$(grep -c '^COPY ' $B/keep_data_$STAMP.sql || true)\"
    echo \"agno_app refs in snapshot: \$(grep -c -E '\\bagno_app\\b' $B/schema_snapshot_$STAMP.sql || true)\"
    echo \"uiw_ refs in snapshot:     \$(grep -c -E '\\buiw_' $B/schema_snapshot_$STAMP.sql || true)\"
    grep -oE 'CREATE EXTENSION IF NOT EXISTS [a-z_]+' $B/schema_snapshot_$STAMP.sql | sort -u | tr '\n' ' '; echo"
  scp -q -i "$KEY" "root@$HOST:$B/schema_snapshot_$STAMP.sql" "$SNAP_LOCAL"
  echo "snapshot pulled to $SNAP_LOCAL ($(wc -l < "$SNAP_LOCAL") lines)"
  ;;
verify-keep)
  verify_keep
  ;;
edit)
  python3 - "$SNAP_LOCAL" "$STAMP" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1]); stamp = sys.argv[2]; s = p.read_text(encoding="utf-8")
before = s
# 1. lane rename: every uiw_* identifier -> proffer_* (tables, constraints, indexes, triggers, functions)
s = re.sub(r"\buiw_", "proffer_", s)
s = re.sub(r"_uiw_", "_proffer_", s)
# 2. agno_app is dead: drop every GRANT/REVOKE/ALTER DEFAULT PRIVILEGES line naming it
s = "\n".join(ln for ln in s.split("\n") if not re.search(r"\bagno_app\b", ln))
# 3. human labels are reference data: move both tables (and their indexes/constraints) under reference
s = s.replace("analysis.human_label_gold", "reference.human_label_gold").replace("analysis.human_label", "reference.human_label")
# 4. reference never carries an FK to an operational table
s = re.sub(r"ALTER TABLE ONLY reference\.\w+\n\s+ADD CONSTRAINT \w+ FOREIGN KEY \([^)]*\) REFERENCES (?!reference\.)[^;]+;\n", "", s)
# 5. intake carries context fingerprints, never custody H-names (D-124, D-149 item 1; owner 2026-09-07 02:57):
#    raw.<format>.content_canon default moves off the custody tag into the sql/0048 fingerprint family
n_default = s.count("content_canon text DEFAULT 'h2-rawelement-v1'::text NOT NULL")
s = s.replace("content_canon text DEFAULT 'h2-rawelement-v1'::text NOT NULL", "content_canon text DEFAULT 'context-rawrecord-fingerprint-v1'::text NOT NULL")
hdr = ("-- schema_snapshot_%s.sql — THE DATABASE. Edited by scripts/rebuild_platform_from_snapshot.sh edit.\n"
       "-- Byline: Claude Code · Fable 5.1 · 2026-09-06 (edit step 5 added 2026-09-07). Source: pg_dump --schema-only of live platform,\n"
       "-- then: uiw_* -> proffer_* (D-140); agno_app removed (owner 2026-09-06); analysis.human_label* -> reference.*\n"
       "-- (owner 2026-09-06: reference is what evidence is compared against); no FK from reference.* to\n"
       "-- operational tables; raw.*.content_canon DEFAULT 'context-rawrecord-fingerprint-v1' (D-124/D-149: intake =\n"
       "-- fingerprints, custody H1/H2/H3 at promotion). Rebuild: DROP/CREATE platform, apply this file, load the keep set.\n\n" % stamp)
s = re.sub(r"\A(-- schema_snapshot_\d+\.sql — THE DATABASE\..*?\n\n)", "", s, count=1, flags=re.S)  # idempotent re-edit
p.write_text(hdr + s, encoding="utf-8", newline="\n")
print("edited", p, "changed:", before != s)
print("remaining uiw_:", len(re.findall(r"\buiw_", s)), "| agno_app:", len(re.findall(r"\bagno_app\b", s)), "| analysis.human_label:", s.count("analysis.human_label"),
      "| reference FKs outward:", len(re.findall(r"ALTER TABLE ONLY reference\.\w+\n\s+ADD CONSTRAINT \w+ FOREIGN KEY \([^)]*\) REFERENCES (?!reference\.)", s)),
      "| content_canon defaults moved:", n_default, "| custody-tag defaults left:", s.count("DEFAULT 'h2-rawelement-v1'"))
PY
  ;;
rebuild)
  [ -s "$SNAP_LOCAL" ] || { echo "missing $SNAP_LOCAL"; exit 1; }
  verify_keep | tee /dev/stderr | grep -q '^KEEP-SET OK$' || { echo "refusing to rebuild: keep set does not match live"; exit 3; }
  scp -q -i "$KEY" "$SNAP_LOCAL" "root@$HOST:$B/schema_snapshot_${STAMP}.edited.sql"
  "${SSH[@]}" "set -e
    docker cp $B/schema_snapshot_$STAMP.edited.sql $C:/tmp/snap.sql
    # keep-set rows dumped from an older human_label location are retargeted to reference.* (no-op once live)
    sed -e 's/analysis\.human_label_gold/reference.human_label_gold/g' -e 's/analysis\.human_label\b/reference.human_label/g' $B/keep_data_$STAMP.sql > $B/keep_data_$STAMP.edited.sql
    docker cp $B/keep_data_$STAMP.edited.sql $C:/tmp/keep.sql
    echo '--- terminate sessions and recreate platform ---'
    docker exec $C psql -U ai -d postgres -v ON_ERROR_STOP=1 -Atc \"select pg_terminate_backend(pid) from pg_stat_activity where datname='platform' and pid<>pg_backend_pid();\" >/dev/null
    docker exec $C psql -U ai -d postgres -v ON_ERROR_STOP=1 -c 'DROP DATABASE platform;' -c 'CREATE DATABASE platform OWNER ai;'
    echo '--- apply snapshot ---'
    docker exec $C psql -U ai -d platform -v ON_ERROR_STOP=1 -q -f /tmp/snap.sql
    echo '--- load keep set ---'
    docker exec $C psql -U ai -d platform -v ON_ERROR_STOP=1 -1 -q -f /tmp/keep.sql
    echo '--- verify: keep-set row counts after reload ---'
    docker exec $C psql -U ai -d platform -At -F '|' -c \"$COUNT_SQL\" | awk -F'|' '\$2>0'
    echo '--- verify: shape ---'
    docker exec $C psql -U ai -d platform -At -F '|' \
      -c \"select 'tables_total', count(*) from pg_tables where schemaname not in ('pg_catalog','information_schema')\" \
      -c \"select 'proffer_tables', count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='context' and c.relname like 'proffer%' and c.relkind='r'\" \
      -c \"select 'uiw_named_objects', (select count(*) from pg_class where relname like '%uiw%')+(select count(*) from pg_constraint where conname like '%uiw%')\" \
      -c \"select 'fks_leaving_reference', count(*) from pg_constraint where contype='f' and conrelid::regclass::text like 'reference.%' and confrelid::regclass::text not like 'reference.%'\" \
      -c \"select 'analysis_human_label_tables', count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='analysis' and c.relname like 'human_label%'\" \
      -c \"select 'raw_content_canon_defaults', string_agg(distinct column_default, ' / ') from information_schema.columns where table_schema='raw' and column_name='content_canon'\""
  ;;
*) echo "usage: $0 dump|verify-keep|edit|rebuild"; exit 2;;
esac
