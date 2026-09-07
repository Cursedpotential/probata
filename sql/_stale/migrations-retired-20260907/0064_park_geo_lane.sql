-- 0064_park_geo_lane.sql
--
-- Byline: Claude · Opus 5 · 2026-08-31, owner-ruled (D-121).
--
-- The geo/location lane is REAL and its code comes later — but it does not
-- sit in a database whose ingest is unproven. Owner: "why am I gonna bring
-- in the key to the application I've been working on even longer than this,
-- just to have it fucked up too."
--
-- Complete DDL backed up FIRST to sql/parked/geo_lane_parked_20260831.sql
-- (tables, constraints, indexes, comments — one-file restore, committed to
-- git). All ten are empty; DDL is everything there is to preserve.
-- Restore = run that one file. Nothing needs recreating from memory.
DO $$
DECLARE t TEXT; n BIGINT;
BEGIN
  FOREACH t IN ARRAY ARRAY['working.stay_point','working.gps_track','working.geocode_request',
    'working.geocode_resolution','working.geocode_result','working.home_base',
    'working.waypoint_device_split','working.vehicle','reference.geofence','ops.geocode_audit'] LOOP
    IF to_regclass(t) IS NOT NULL THEN
      EXECUTE format('SELECT count(*) FROM %s', t) INTO n;
      IF n > 0 THEN RAISE EXCEPTION 'ABORT: % has % rows', t, n; END IF;
    END IF;
  END LOOP;
END $$;
DROP TABLE IF EXISTS working.stay_point, working.gps_track, working.geocode_request,
  working.geocode_resolution, working.geocode_result, working.home_base,
  working.waypoint_device_split, working.vehicle, reference.geofence,
  ops.geocode_audit CASCADE;
