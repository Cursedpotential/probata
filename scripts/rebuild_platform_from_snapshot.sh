#!/usr/bin/env bash
# Rebuild the `platform` database from a schema snapshot + the primary-data keep set.
# Byline: Claude Code · Fable 5.1 · 2026-09-06. Owner rulings 2026-09-06 18:51–19:02:
#   no migration, no rehearsal for a database that holds no evidence; the snapshot IS the database;
#   "reference stays. period."; reference is never FK-bound to operational tables;
#   human_label* moves under `reference`; agno_app is dead; uiw_* -> proffer_*.
#
# Run from the repo root on the desktop (needs ~/.ssh/ovh). Subcommands, in order:
#   bash scripts/rebuild_platform_from_snapshot.sh dump      # safety dump + fresh schema snapshot + keep-set data
#   bash scripts/rebuild_platform_from_snapshot.sh edit      # rewrite the snapshot to the ruled shape (local file)
#   bash scripts/rebuild_platform_from_snapshot.sh rebuild   # recreate platform from the edited snapshot, reload, verify
#
# Everything produced on the host lands in /data/agno/backups (never git). The edited snapshot is
# committed under sql/bootstrap/ and becomes the golden-template source (D-142 §3).
set -euo pipefail
HOST="${PG_HOST:-100.91.190.107}"
KEY="${OVH_KEY:-$HOME/.ssh/ovh}"
C="${PG_CONTAINER:-agentos-db-w10gg3an43jvry4y79n6sxi1-185413138931}"
STAMP="${STAMP:-20260906}"
B=/data/agno/backups
SNAP_LOCAL="sql/bootstrap/schema_snapshot_${STAMP}.sql"
SSH=(ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=15 "root@$HOST")

# Tables whose rows survive the rebuild (primary data + registries + ledgers). Everything else is
# fixture (D-142) and is NOT carried.
KEEP_SCHEMAS="--schema=reference --schema=media --schema=knowledge --schema=canon --schema=registry --schema=ops"
KEEP_TABLES="-t analysis.human_label -t analysis.human_label_gold -t public.canon_registry -t public.schema_version"

case "${1:-}" in
dump)
  "${SSH[@]}" "set -e; mkdir -p $B
    docker exec $C sh -c 'pg_dump -U ai -d platform -Fc -f /tmp/platform-pre-rebuild-$STAMP.dump && pg_dump -U ai -d platform --schema-only --no-owner > /tmp/schema_snapshot_$STAMP.sql && pg_dump -U ai -d platform --data-only --no-owner --no-privileges $KEEP_SCHEMAS $KEEP_TABLES > /tmp/keep_data_$STAMP.sql'
    for f in platform-pre-rebuild-$STAMP.dump schema_snapshot_$STAMP.sql keep_data_$STAMP.sql; do docker cp $C:/tmp/\$f $B/\$f; done
    ls -la $B | grep $STAMP
    echo \"agno_app refs in snapshot: \$(grep -c agno_app $B/schema_snapshot_$STAMP.sql || true)\"
    echo \"uiw_ refs in snapshot:     \$(grep -c -E '\\buiw_' $B/schema_snapshot_$STAMP.sql || true)\"
    echo \"analysis.human_label refs: snapshot \$(grep -c 'analysis.human_label' $B/schema_snapshot_$STAMP.sql || true), data \$(grep -c 'analysis.human_label' $B/keep_data_$STAMP.sql || true)\"
    grep -oE 'CREATE EXTENSION IF NOT EXISTS [a-z_]+' $B/schema_snapshot_$STAMP.sql | sort -u"
  scp -q -i "$KEY" "root@$HOST:$B/schema_snapshot_$STAMP.sql" "$SNAP_LOCAL"
  echo "snapshot pulled to $SNAP_LOCAL ($(wc -l < "$SNAP_LOCAL") lines)"
  ;;
edit)
  python3 - "$SNAP_LOCAL" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text(encoding="utf-8")
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
hdr = ("-- schema_snapshot_%s.sql — THE DATABASE. Edited by scripts/rebuild_platform_from_snapshot.sh edit.\n"
       "-- Byline: Claude Code · Fable 5.1 · 2026-09-06. Source: pg_dump --schema-only of live platform,\n"
       "-- then: uiw_* -> proffer_* (D-140); agno_app removed (owner 2026-09-06); analysis.human_label* -> reference.*\n"
       "-- (owner 2026-09-06: reference is what evidence is compared against); no FK from reference.* to\n"
       "-- operational tables. Rebuild: DROP/CREATE platform, apply this file, load the primary-data keep set.\n\n")
p.write_text(hdr + s, encoding="utf-8", newline="\n")
print("edited", p, "changed:", before != s)
print("remaining uiw_:", len(re.findall(r"\buiw_", s)), "| agno_app:", s.count("agno_app"), "| analysis.human_label:", s.count("analysis.human_label"),
      "| reference FKs outward:", len(re.findall(r"ALTER TABLE ONLY reference\.\w+\n\s+ADD CONSTRAINT \w+ FOREIGN KEY \([^)]*\) REFERENCES (?!reference\.)", s)))
PY
  ;;
rebuild)
  [ -s "$SNAP_LOCAL" ] || { echo "missing $SNAP_LOCAL"; exit 1; }
  scp -q -i "$KEY" "$SNAP_LOCAL" "root@$HOST:$B/schema_snapshot_${STAMP}.edited.sql"
  "${SSH[@]}" "set -e
    docker cp $B/schema_snapshot_$STAMP.edited.sql $C:/tmp/snap.sql
    # keep-set data was dumped with the old human_label location; retarget it to reference.*
    sed -e 's/analysis\.human_label_gold/reference.human_label_gold/g' -e 's/analysis\.human_label\b/reference.human_label/g' $B/keep_data_$STAMP.sql > $B/keep_data_$STAMP.edited.sql
    docker cp $B/keep_data_$STAMP.edited.sql $C:/tmp/keep.sql
    echo '--- terminate sessions and recreate platform ---'
    docker exec $C psql -U ai -d postgres -v ON_ERROR_STOP=1 -Atc \"select pg_terminate_backend(pid) from pg_stat_activity where datname='platform' and pid<>pg_backend_pid();\" >/dev/null
    docker exec $C psql -U ai -d postgres -v ON_ERROR_STOP=1 -c 'DROP DATABASE platform;' -c 'CREATE DATABASE platform OWNER ai;'
    echo '--- apply snapshot ---'
    docker exec $C psql -U ai -d platform -v ON_ERROR_STOP=1 -q -f /tmp/snap.sql
    echo '--- load keep set ---'
    docker exec $C psql -U ai -d platform -v ON_ERROR_STOP=1 -1 -q -f /tmp/keep.sql
    echo '--- verify ---'
    docker exec $C psql -U ai -d platform -At -F '|' -c \"select n.nspname||'.'||c.relname, (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', n.nspname, c.relname), false, true, '')))[1]::text::int from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and n.nspname in ('reference','media','knowledge','canon','registry') order by 1;\"
    echo \"proffer tables: \$(docker exec $C psql -U ai -d platform -Atc \\\"select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='context' and c.relname like 'proffer\\\\_%' and c.relkind='r'\\\")\"
    echo \"uiw-named objects: \$(docker exec $C psql -U ai -d platform -Atc \\\"select (select count(*) from pg_class where relname like '%uiw%')+(select count(*) from pg_constraint where conname like '%uiw%')\\\")\"
    echo \"FKs leaving reference: \$(docker exec $C psql -U ai -d platform -Atc \\\"select count(*) from pg_constraint where contype='f' and conrelid::regclass::text like 'reference.%' and confrelid::regclass::text not like 'reference.%'\\\")\"
    echo \"analysis.human_label still present: \$(docker exec $C psql -U ai -d platform -Atc \\\"select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='analysis' and c.relname like 'human_label%'\\\")\"
    echo \"tables total: \$(docker exec $C psql -U ai -d platform -Atc \\\"select count(*) from pg_tables where schemaname not in ('pg_catalog','information_schema')\\\")\""
  ;;
*) echo "usage: $0 dump|edit|rebuild"; exit 2;;
esac
