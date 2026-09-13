param(
    [switch]$Apply,
    [string]$Snapshot = (Join-Path $PSScriptRoot '../../../sql/bootstrap/schema_snapshot_20260907.sql')
)
# Codex, 2026-09-12. Emits SQL only; execution is a separate reviewed operation.
# Default transaction terminator is ROLLBACK. This is not a numbered migration.
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $Snapshot -Raw
$names = @('handler_content_signature', 'handler_detected_format', 'handler_compatibility',
    'handler_recommendation', 'handler_selection_decision', 'handler_selection_validation')
$pattern = '(?:' + ($names -join '|') + ')'
$creates = [regex]::Matches($source, "(?ms)^CREATE TABLE context\.$pattern \(.*?^\);")
$alters = [regex]::Matches($source, "(?ms)^ALTER TABLE ONLY context\.$pattern\r?\n.*?;")
$grants = [regex]::Matches($source, "(?m)^GRANT [^;]+ ON TABLE context\.$pattern TO [^;]+;")
if ($creates.Count -ne 6 -or $alters.Count -ne 31 -or $grants.Count -ne 18) {
    throw "Unexpected snapshot coverage: create=$($creates.Count), alter=$($alters.Count), grant=$($grants.Count); review snapshot drift."
}
$function = [regex]::Match($source, '(?ms)^CREATE FUNCTION context\.forbid_mutation\(\) RETURNS trigger.*?^\$\$;').Value
if (!$function) { throw 'Missing canonical append-only function.' }
$functionBody = [regex]::Match($function, '(?s)AS \$\$(.*?)\$\$;').Groups[1].Value
$functionBody = [regex]::Replace($functionBody, '\s+', '')
$snapshotHash = (Get-FileHash -LiteralPath $Snapshot -Algorithm SHA256).Hash
@"
\set ON_ERROR_STOP on
-- Snapshot SHA256: $snapshotHash
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';
SET LOCAL search_path = pg_catalog, public;
SELECT pg_advisory_xact_lock(20260912, 149);
"@
@'
DO $preflight$
DECLARE n text; old_check text;
BEGIN
  IF current_database() <> 'platform' THEN RAISE EXCEPTION 'Wrong database'; END IF;
  FOREACH n IN ARRAY ARRAY['handler_content_signature','handler_detected_format','handler_compatibility',
      'handler_recommendation','handler_selection_decision','handler_selection_validation'] LOOP
    IF to_regclass('context.' || n) IS NOT NULL THEN
      RAISE EXCEPTION 'Expected absent context.%, refusing preexisting/partial schema', n;
    END IF;
  END LOOP;
  FOREACH n IN ARRAY ARRAY['context_import_writer','context_reader','platform_app'] LOOP
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname=n) THEN RAISE EXCEPTION 'Missing role %', n; END IF;
  END LOOP;
  SELECT pg_get_constraintdef(oid) INTO old_check FROM pg_constraint
  WHERE conrelid='context.proffer_preview_receipt'::regclass
    AND conname='proffer_preview_receipt_receipt_type_check' AND contype='c' AND convalidated;
  IF old_check IS DISTINCT FROM
    'CHECK ((receipt_type = ANY (ARRAY[''custody''::text, ''parser_selection''::text, ''parser_execution''::text, ''normalization''::text, ''storage''::text, ''completeness''::text])))'
  THEN RAISE EXCEPTION 'Unexpected receipt CHECK drift: %', old_check; END IF;
END
$preflight$;
-- Lock existing context tables to prevent concurrent changes invalidating preservation proof.
-- Only counts and aggregate SHA-256 fingerprints are emitted; no row contents leave server.
CREATE TEMP TABLE preserved_context (relation text PRIMARY KEY, rows bigint, sha256 text) ON COMMIT DROP;
DO $before$
DECLARE r record; n bigint; h text;
BEGIN
  FOR r IN SELECT c.oid::regclass AS rel FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
           WHERE s.nspname='context' AND c.relkind IN ('r','p') ORDER BY c.oid LOOP
    EXECUTE format('LOCK TABLE %s IN SHARE MODE', r.rel);
    EXECUTE format('SELECT count(*), encode(sha256(convert_to(coalesce(string_agg(row_hash, '''' ORDER BY row_hash), ''''), ''UTF8'')), ''hex'') FROM (SELECT encode(sha256(convert_to(to_jsonb(t)::text, ''UTF8'')), ''hex'') row_hash FROM %s t) q', r.rel) INTO n,h;
    INSERT INTO preserved_context VALUES (r.rel::text,n,h);
  END LOOP;
END
$before$;
'@
@"
DO `$guard`$
BEGIN
  IF to_regprocedure('context.forbid_mutation()') IS NULL THEN
    EXECUTE `$definition`$$function`$definition`$;
  ELSIF (SELECT regexp_replace(prosrc, '\s+', '', 'g') FROM pg_proc WHERE oid=to_regprocedure('context.forbid_mutation()')) <> `$body`$$functionBody`$body`$ THEN
    RAISE EXCEPTION 'Existing context.forbid_mutation body differs from canonical snapshot';
  END IF;
END
`$guard`$;
"@
$creates | ForEach-Object { $_.Value }
$alters | ForEach-Object { $_.Value }
$grants | ForEach-Object { $_.Value }
@'
GRANT ALL ON FUNCTION context.forbid_mutation() TO context_import_writer;
GRANT ALL ON FUNCTION context.forbid_mutation() TO platform_app;
-- Expand the CHECK, never rewrite or reinterpret legacy failed receipts.
ALTER TABLE context.proffer_preview_receipt DROP CONSTRAINT proffer_preview_receipt_receipt_type_check;
ALTER TABLE context.proffer_preview_receipt ADD CONSTRAINT proffer_preview_receipt_receipt_type_check
CHECK (receipt_type = ANY (ARRAY['custody','raw_source_verification','parser_selection','parser_execution','normalization','storage','completeness']::text[]));
DO $verify$
DECLARE r record; n bigint; h text; actual integer; privilege text;
BEGIN
  FOR r IN SELECT * FROM preserved_context ORDER BY relation LOOP
    EXECUTE format('SELECT count(*), encode(sha256(convert_to(coalesce(string_agg(row_hash, '''' ORDER BY row_hash), ''''), ''UTF8'')), ''hex'') FROM (SELECT encode(sha256(convert_to(to_jsonb(t)::text, ''UTF8'')), ''hex'') row_hash FROM %s t) q', r.relation::regclass) INTO n,h;
    IF n IS DISTINCT FROM r.rows OR h IS DISTINCT FROM r.sha256 THEN
      RAISE EXCEPTION 'Preservation failure for %',r.relation;
    END IF;
  END LOOP;
  SELECT count(*) INTO actual FROM pg_constraint
    WHERE connamespace='context'::regnamespace AND conrelid IN
      (SELECT oid FROM pg_class WHERE relnamespace='context'::regnamespace AND relname LIKE 'handler_%')
      AND contype='p';
  IF actual <> 6 THEN RAISE EXCEPTION 'Expected six PKs; got %',actual; END IF;
  SELECT count(*) INTO actual FROM pg_constraint
    WHERE connamespace='context'::regnamespace AND conrelid IN
      (SELECT oid FROM pg_class WHERE relnamespace='context'::regnamespace AND relname LIKE 'handler_%')
      AND contype='f' AND convalidated;
  IF actual <> 18 THEN RAISE EXCEPTION 'Expected 18 validated FKs; got %',actual; END IF;
  SELECT count(*) INTO actual FROM pg_constraint
    WHERE connamespace='context'::regnamespace AND conrelid IN
      (SELECT oid FROM pg_class WHERE relnamespace='context'::regnamespace AND relname LIKE 'handler_%')
      AND contype='u';
  IF actual <> 7 THEN RAISE EXCEPTION 'Expected seven UNIQUE constraints; got %',actual; END IF;
  IF EXISTS (SELECT FROM pg_constraint WHERE connamespace='context'::regnamespace
             AND conname='handler_recommendation_signature_key') THEN
    RAISE EXCEPTION 'Recovery-blocking signature uniqueness must not exist';
  END IF;
  FOR r IN SELECT relname,oid FROM pg_class WHERE relnamespace='context'::regnamespace AND relname LIKE 'handler_%' AND relkind='r' LOOP
    IF NOT has_table_privilege('context_import_writer',r.oid,'SELECT')
      OR NOT has_table_privilege('context_import_writer',r.oid,'INSERT')
      OR NOT has_table_privilege('context_reader',r.oid,'SELECT') THEN
      RAISE EXCEPTION 'Missing grants for %',r.relname;
    END IF;
    FOREACH privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'] LOOP
      IF NOT has_table_privilege('platform_app',r.oid,privilege) THEN
        RAISE EXCEPTION 'Missing platform_app % grant for %',privilege,r.relname;
      END IF;
    END LOOP;
  END LOOP;
END
$verify$;
SELECT * FROM preserved_context ORDER BY relation;
SELECT 'PRESERVATION OK' AS result, count(*) AS existing_tables, sum(rows) AS existing_rows FROM preserved_context;
SELECT conrelid::regclass AS relation, contype, count(*) FROM pg_constraint
WHERE connamespace='context'::regnamespace AND conrelid IN
 (SELECT oid FROM pg_class WHERE relnamespace='context'::regnamespace AND relname LIKE 'handler_%')
GROUP BY 1,2 ORDER BY 1,2;
'@
if ($Apply) { 'COMMIT;' } else { 'ROLLBACK;' }
