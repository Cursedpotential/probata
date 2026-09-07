-- 0060_test_reset.sql
--
-- Byline: Claude · Opus 5 · 2026-08-31, owner-ruled.
--
-- Owner: "The only time things get purged is during testing. So that we start
-- fresh. And you're not even doing that correctly."
--
-- Correct: there has never been a proper reset. Every fresh start so far was
-- an ad-hoc teardown, and each one destroyed something it shouldn't have
-- (migration state once, quarantine dispositions once, a day of work once).
--
-- THE RESET BUTTON. One rule: DATA resets, RULINGS AND IDENTITY survive.
--
--   TRUNCATED (test data, start fresh):
--     raw.*                  landed test ingests
--     evidence.*             test promotions and custody rows
--     working.*              everything derived
--     context.*              intake state
--     timeline.*             projections
--     analysis.*             test conclusions
--     canon proposals/decisions/applications/recompute (test traffic)
--
--   PRESERVED (never touched by a reset):
--     reference.*            identity + taxonomy — cumulative from the very
--                            beginning, INCLUDING what test ingests discovered
--                            (owner ruling, D-115)
--     canon.canonical_table  the boundary   } rulings, not data
--     canon.change_tier      the valve      }
--     ops.*                  migration ledger + run history
--     public.*               contracts, registries, decision precedents
--     ai.*                   Agno's own store
--
-- Requires the literal confirmation string. No partial mode, no cleverness:
-- one honest reset that does the same thing every time.

CREATE OR REPLACE FUNCTION ops.reset_test_data(p_confirm TEXT)
RETURNS TABLE (truncated_schema TEXT, tables_truncated INTEGER)
LANGUAGE plpgsql AS $fn$
DECLARE
  v_schema TEXT;
  v_list   TEXT;
  v_count  INTEGER;
BEGIN
  IF p_confirm IS DISTINCT FROM 'RESET' THEN
    RAISE EXCEPTION 'refusing: call ops.reset_test_data(''RESET'') to confirm a full test-data reset';
  END IF;

  FOREACH v_schema IN ARRAY ARRAY['raw','evidence','working','context','timeline','analysis'] LOOP
    SELECT string_agg(format('%I.%I', nn.nspname, c.relname), ', '), count(*)::INTEGER
      INTO v_list, v_count
      FROM pg_class c JOIN pg_namespace nn ON nn.oid = c.relnamespace
     WHERE c.relkind = 'r' AND nn.nspname = v_schema;
    IF v_list IS NOT NULL THEN
      EXECUTE 'TRUNCATE TABLE ' || v_list || ' RESTART IDENTITY CASCADE';
    END IF;
    truncated_schema := v_schema; tables_truncated := coalesce(v_count,0);
    RETURN NEXT;
  END LOOP;

  -- canon: test traffic resets, rulings survive
  TRUNCATE TABLE canon.recompute_queue, canon.change_application,
                 canon.change_decision, canon.change_proposal
    RESTART IDENTITY CASCADE;
  truncated_schema := 'canon (proposals/decisions/applications/queue only)';
  tables_truncated := 4;
  RETURN NEXT;

  -- reset per-table generations: a fresh test run starts at generation 0
  UPDATE canon.canonical_table SET current_generation = 0;
END $fn$;

COMMENT ON FUNCTION ops.reset_test_data(TEXT) IS
  'THE reset button (D-118). Truncates test data in raw/evidence/working/context/timeline/analysis and canon traffic; preserves reference (identity is cumulative, incl. test-ingest discoveries), canon rulings, ops ledgers, public, ai. Call with ''RESET'' to confirm. This is the ONLY sanctioned purge.';

GRANT EXECUTE ON FUNCTION ops.reset_test_data(TEXT) TO platform_admin;
