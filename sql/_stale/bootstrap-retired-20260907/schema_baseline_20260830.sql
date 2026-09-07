-- schema_baseline_20260830.sql
-- Generated 2026-09-01T11:44:55.893671+00:00 from the live `platform`
-- database using PostgreSQL's own DDL serializers (pg_get_constraintdef,
-- pg_get_indexdef, pg_get_viewdef, pg_get_functiondef).
--
-- THIS REPLACES sql/bootstrap/schema_baseline.sql (a pg_dump from 2026-08-10).
--
-- Why: the old baseline was a stale photograph. Tables deleted from the live
-- database kept reappearing on every rebuild because they still existed in that
-- photo. Re-baselining makes deletion permanent and collapses the build from
-- "baseline + 50 migrations replayed in 3 passes" to a single file.
--
-- Migrations 0001-0055 are now HISTORY, not build steps. The next new
-- migration is 0056.
--
-- NOTHING here is immutable. No append-only / forbid / assert guard is
-- included: all 131 such triggers in the old chain guarded context/working
-- (layers under construction), lookup registries, or a finished consolidation
-- -- ZERO guarded evidence.*. See docs/GUARD-TRIGGER-DISPOSITION.md.

SET client_min_messages = warning;

-- ============ schemas ============
CREATE SCHEMA IF NOT EXISTS ai;
CREATE SCHEMA IF NOT EXISTS analysis;
CREATE SCHEMA IF NOT EXISTS archive;
CREATE SCHEMA IF NOT EXISTS canon;
CREATE SCHEMA IF NOT EXISTS context;
CREATE SCHEMA IF NOT EXISTS evidence;
CREATE SCHEMA IF NOT EXISTS ext;
CREATE SCHEMA IF NOT EXISTS ops;
CREATE SCHEMA IF NOT EXISTS public;
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS reference;
CREATE SCHEMA IF NOT EXISTS registry;
CREATE SCHEMA IF NOT EXISTS timeline;
CREATE SCHEMA IF NOT EXISTS working;

-- ============ extensions ============
CREATE EXTENSION IF NOT EXISTS "btree_gin" SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "btree_gist" SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "citext" SCHEMA ai;
CREATE EXTENSION IF NOT EXISTS "fuzzystrmatch" SCHEMA ai;
CREATE EXTENSION IF NOT EXISTS "hstore" SCHEMA ai;
CREATE EXTENSION IF NOT EXISTS "ltree" SCHEMA ai;
-- OPTIONAL (analytics only; skip if it errors): CREATE EXTENSION IF NOT EXISTS "pg_duckdb" SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "pg_trgm" SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "pgcrypto" SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "plpgsql" SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS "postgis" SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "unaccent" SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "vector" SCHEMA public;

-- ============ enum types ============
CREATE TYPE ai.anchor_kind AS ENUM ('docketed_event', 'recurring_holiday', 'life_event', 'derived');
CREATE TYPE ai.assertion_source AS ENUM ('gps', 'claimed_text', 'exif', 'ip_geo', 'cell_tower', 'wifi', 'witness', 'geocode', 'manual');
CREATE TYPE ai.assertion_type AS ENUM ('raw_evidence', 'extracted_fact', 'inferred_fact', 'analytical_finding', 'legal_conclusion');
CREATE TYPE ai.category_polarity AS ENUM ('negative', 'positive', 'neutral', 'linguistic_marker');
CREATE TYPE ai.conduct_party AS ENUM ('user', 'partner', 'child', 'mutual', 'third_party', 'institution', 'unknown');
CREATE TYPE ai.cycle_phase AS ENUM ('calm', 'tension_building', 'conflict', 'repair', 'reconciliation', 'love_bombing', 'withdrawal', 'escalation', 'de_escalation', 'unknown');
CREATE TYPE ai.detection_method AS ENUM ('literal', 'regex', 'priority_screener', 'semantic_similarity', 'model', 'human', 'imported');
CREATE TYPE ai.disclosure_horizon AS ENUM ('contemporaneous', 'hindsight', 'discovered');
CREATE TYPE ai.entity_type AS ENUM ('person', 'org', 'project', 'tech', 'location', 'concept', 'phone', 'email', 'handle', 'device', 'account', 'vehicle', 'address', 'court', 'attorney', 'school', 'doctor', 'institution', 'platform', 'ai_system');
CREATE TYPE ai.event_type AS ENUM ('milestone', 'decision', 'meeting', 'incident', 'change', 'memory', 'upcoming', 'presence', 'communication', 'observation');
CREATE TYPE ai.evidence_tier AS ENUM ('raw', 'extracted', 'inferred', 'analytical', 'legal_conclusion');
CREATE TYPE ai.geocode_provider AS ENUM ('google', 'radar', 'nominatim', 'osm', 'manual');
CREATE TYPE ai.match_method AS ENUM ('exact', 'resolved', 'manual');
CREATE TYPE ai.mcl_factor AS ENUM ('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l');
CREATE TYPE ai.pattern_match_type AS ENUM ('literal', 'regex');
CREATE TYPE ai.precision_class AS ENUM ('exact', 'approximate', 'inferred', 'uncertain');
CREATE TYPE ai.review_state AS ENUM ('unreviewed', 'in_review', 'approved', 'rejected', 'needs_more_evidence');
CREATE TYPE ai.sensitivity_tier AS ENUM ('public', 'restricted', 'sealed');
CREATE TYPE ai.source_system AS ENUM ('postgres', 'neo4j', 'milvus', 'surrealdb');
CREATE TYPE ai.strength_class AS ENUM ('none', 'weak', 'moderate', 'strong', 'conclusive');
CREATE TYPE ai.temporal_class AS ENUM ('historical', 'current', 'future');
CREATE TYPE ai.temporal_relation AS ENUM ('preceded', 'meets', 'overlaps', 'during', 'same_day', 'equals', 'caused_hypothesis');
CREATE TYPE analysis.graph_lane AS ENUM ('semantica', 'sat_temporal');
CREATE TYPE evidence.acquisition_authority AS ENUM ('device_owner', 'parent_guardian', 'account_holder', 'consent_given', 'court_order', 'unclear');
CREATE TYPE evidence.acquisition_method AS ENUM ('own_device', 'household_device', 'voluntary_third_party', 'legal_process', 'public_source', 'unknown');
CREATE TYPE evidence.record_medium AS ENUM ('export', 'screenshot', 'screen_capture', 'forwarded', 'transcript', 'unknown');
CREATE TYPE public.entity_type AS ENUM ('person', 'org', 'project', 'tech', 'location', 'concept');
CREATE TYPE public.event_type AS ENUM ('milestone', 'decision', 'meeting', 'incident', 'change', 'memory', 'upcoming');
CREATE TYPE public.match_method AS ENUM ('exact', 'resolved', 'manual');
CREATE TYPE public.mcl_factor AS ENUM ('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l');
CREATE TYPE public.source_system AS ENUM ('postgres', 'neo4j', 'milvus', 'surrealdb');
CREATE TYPE public.temporal_class AS ENUM ('historical', 'current', 'future');

-- ============ composite types ============
CREATE TYPE ai.source_ref AS (
  system ai.source_system,
  native_id text,
  locator text
);
CREATE TYPE public.source_ref AS (
  system source_system,
  native_id text,
  locator text
);

-- ============ domains ============
CREATE DOMAIN ai.canonical_id AS uuid;
CREATE DOMAIN ai.confidence AS numeric(4,3) CHECK (((VALUE IS NULL) OR ((VALUE >= (0)::numeric) AND (VALUE <= (1)::numeric))));
CREATE DOMAIN ai.geo_point AS geography(Point,4326);
CREATE DOMAIN public.canonical_id AS uuid;
CREATE DOMAIN public.confidence AS numeric(4,3) CHECK (((VALUE IS NULL) OR ((VALUE >= (0)::numeric) AND (VALUE <= (1)::numeric))));
CREATE DOMAIN public.geo_point AS geography(Point,4326);

-- ============ sequences ============
CREATE SEQUENCE IF NOT EXISTS ai.api_keys_id_seq;
CREATE SEQUENCE IF NOT EXISTS analysis.workflow_run_stage_stage_id_seq;
CREATE SEQUENCE IF NOT EXISTS evidence.custody_event_seq_seq;
CREATE SEQUENCE IF NOT EXISTS ops.audit_ledger_id_seq;
CREATE SEQUENCE IF NOT EXISTS ops.workflow_run_stage_stage_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.change_log_seq_seq;
CREATE SEQUENCE IF NOT EXISTS timeline.timeline_projection_generation_sequence_seq;
CREATE SEQUENCE IF NOT EXISTS working.message_serial_number_seq;

-- ============ tables ============

CREATE TABLE IF NOT EXISTS ai.agno_approvals (
  id character varying NOT NULL,
  run_id character varying NOT NULL,
  session_id character varying NOT NULL,
  status character varying NOT NULL,
  source_type character varying NOT NULL,
  approval_type character varying,
  pause_type character varying NOT NULL,
  tool_name character varying,
  tool_args jsonb,
  expires_at bigint,
  agent_id character varying,
  team_id character varying,
  workflow_id character varying,
  user_id character varying,
  schedule_id character varying,
  schedule_run_id character varying,
  source_name character varying,
  requirements jsonb,
  context jsonb,
  resolution_data jsonb,
  resolved_by character varying,
  resolved_at bigint,
  created_at bigint NOT NULL,
  updated_at bigint,
  run_status character varying
);

CREATE TABLE IF NOT EXISTS ai.agno_component_configs (
  component_id character varying NOT NULL,
  version integer NOT NULL,
  label character varying,
  stage character varying NOT NULL,
  config jsonb NOT NULL,
  notes text,
  created_at bigint NOT NULL,
  updated_at bigint,
  deleted_at bigint
);

CREATE TABLE IF NOT EXISTS ai.agno_component_links (
  parent_component_id character varying NOT NULL,
  parent_version integer NOT NULL,
  link_kind character varying NOT NULL,
  link_key character varying NOT NULL,
  child_component_id character varying NOT NULL,
  child_version integer,
  position integer NOT NULL,
  meta jsonb,
  created_at bigint,
  updated_at bigint
);

CREATE TABLE IF NOT EXISTS ai.agno_components (
  component_id character varying NOT NULL,
  component_type character varying NOT NULL,
  name character varying,
  description text,
  current_version integer,
  metadata jsonb,
  created_at bigint NOT NULL,
  updated_at bigint,
  deleted_at bigint
);

CREATE TABLE IF NOT EXISTS ai.agno_eval_runs (
  run_id character varying NOT NULL,
  eval_type character varying NOT NULL,
  eval_data jsonb NOT NULL,
  eval_input jsonb NOT NULL,
  name character varying,
  agent_id character varying,
  team_id character varying,
  workflow_id character varying,
  model_id character varying,
  model_provider character varying,
  evaluated_component_name character varying,
  created_at bigint NOT NULL,
  updated_at bigint
);

CREATE TABLE IF NOT EXISTS ai.agno_knowledge (
  id character varying NOT NULL,
  name character varying NOT NULL,
  description text NOT NULL,
  metadata jsonb,
  type character varying,
  size bigint,
  linked_to character varying,
  access_count bigint,
  status character varying,
  status_message text,
  created_at bigint,
  updated_at bigint,
  external_id character varying
);

CREATE TABLE IF NOT EXISTS ai.agno_learnings (
  learning_id character varying NOT NULL,
  learning_type character varying NOT NULL,
  namespace character varying,
  user_id character varying,
  agent_id character varying,
  team_id character varying,
  workflow_id character varying,
  session_id character varying,
  entity_id character varying,
  entity_type character varying,
  content jsonb NOT NULL,
  metadata jsonb,
  created_at bigint NOT NULL,
  updated_at bigint
);

CREATE TABLE IF NOT EXISTS ai.agno_memories (
  memory_id character varying NOT NULL,
  memory jsonb NOT NULL,
  feedback text,
  input text,
  agent_id character varying,
  team_id character varying,
  user_id character varying,
  topics jsonb,
  created_at bigint NOT NULL,
  updated_at bigint
);

CREATE TABLE IF NOT EXISTS ai.agno_metrics (
  id character varying NOT NULL,
  agent_runs_count bigint NOT NULL,
  team_runs_count bigint NOT NULL,
  workflow_runs_count bigint NOT NULL,
  agent_sessions_count bigint NOT NULL,
  team_sessions_count bigint NOT NULL,
  workflow_sessions_count bigint NOT NULL,
  users_count bigint NOT NULL,
  token_metrics jsonb NOT NULL,
  model_metrics jsonb NOT NULL,
  date date NOT NULL,
  aggregation_period character varying NOT NULL,
  created_at bigint NOT NULL,
  updated_at bigint,
  completed boolean NOT NULL
);

CREATE TABLE IF NOT EXISTS ai.agno_schedule_runs (
  id character varying NOT NULL,
  schedule_id character varying NOT NULL,
  attempt bigint NOT NULL,
  triggered_at bigint,
  completed_at bigint,
  status character varying NOT NULL,
  status_code bigint,
  run_id character varying,
  session_id character varying,
  error text,
  input jsonb,
  output jsonb,
  requirements jsonb,
  created_at bigint NOT NULL
);

CREATE TABLE IF NOT EXISTS ai.agno_schedules (
  id character varying NOT NULL,
  name character varying NOT NULL,
  description text,
  method character varying NOT NULL,
  endpoint character varying NOT NULL,
  payload jsonb,
  cron_expr character varying NOT NULL,
  timezone character varying NOT NULL,
  timeout_seconds bigint NOT NULL,
  max_retries bigint NOT NULL,
  retry_delay_seconds bigint NOT NULL,
  enabled boolean NOT NULL,
  next_run_at bigint,
  locked_by character varying,
  locked_at bigint,
  created_at bigint NOT NULL,
  updated_at bigint
);

CREATE TABLE IF NOT EXISTS ai.agno_schema_versions (
  table_name character varying NOT NULL,
  version character varying NOT NULL,
  created_at character varying NOT NULL,
  updated_at character varying
);

CREATE TABLE IF NOT EXISTS ai.agno_service_accounts (
  id character varying NOT NULL,
  name character varying NOT NULL,
  user_id character varying,
  token_hash character varying NOT NULL,
  token_prefix character varying NOT NULL,
  scopes jsonb NOT NULL,
  created_at bigint NOT NULL,
  expires_at bigint,
  last_used_at bigint,
  revoked_at bigint,
  created_by character varying
);

CREATE TABLE IF NOT EXISTS ai.agno_sessions (
  session_id character varying NOT NULL,
  session_type character varying NOT NULL,
  agent_id character varying,
  team_id character varying,
  workflow_id character varying,
  user_id character varying,
  session_data jsonb,
  agent_data jsonb,
  team_data jsonb,
  workflow_data jsonb,
  metadata jsonb,
  runs jsonb,
  summary jsonb,
  created_at bigint NOT NULL,
  updated_at bigint
);

CREATE TABLE IF NOT EXISTS ai.agno_spans (
  span_id character varying NOT NULL,
  trace_id character varying NOT NULL,
  parent_span_id character varying,
  name character varying NOT NULL,
  span_kind character varying NOT NULL,
  status_code character varying NOT NULL,
  status_message text,
  start_time character varying NOT NULL,
  end_time character varying NOT NULL,
  duration_ms bigint NOT NULL,
  attributes jsonb,
  created_at character varying NOT NULL
);

CREATE TABLE IF NOT EXISTS ai.agno_traces (
  trace_id character varying NOT NULL,
  name character varying NOT NULL,
  status character varying NOT NULL,
  start_time character varying NOT NULL,
  end_time character varying NOT NULL,
  duration_ms bigint NOT NULL,
  run_id character varying,
  session_id character varying,
  user_id character varying,
  agent_id character varying,
  team_id character varying,
  workflow_id character varying,
  created_at character varying NOT NULL
);

CREATE TABLE IF NOT EXISTS ai.api_keys (
  id bigint DEFAULT nextval('api_keys_id_seq'::regclass) NOT NULL,
  key text NOT NULL,
  name text,
  scopes text[] DEFAULT ARRAY['mcp'::text] NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  expires_at timestamp with time zone,
  revoked boolean DEFAULT false NOT NULL,
  last_used_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS ai.casebible_evidence_contents (
  id character varying NOT NULL,
  name character varying NOT NULL,
  description text NOT NULL,
  metadata jsonb,
  type character varying,
  size bigint,
  linked_to character varying,
  access_count bigint,
  status character varying,
  status_message text,
  created_at bigint,
  updated_at bigint,
  external_id character varying
);

CREATE TABLE IF NOT EXISTS ai.casebible_evidence_test_contents (
  id character varying NOT NULL,
  name character varying NOT NULL,
  description text NOT NULL,
  metadata jsonb,
  type character varying,
  size bigint,
  linked_to character varying,
  access_count bigint,
  status character varying,
  status_message text,
  created_at bigint,
  updated_at bigint,
  external_id character varying
);

CREATE TABLE IF NOT EXISTS ai.casebible_ingest_test2_contents (
  id character varying NOT NULL,
  name character varying NOT NULL,
  description text NOT NULL,
  metadata jsonb,
  type character varying,
  size bigint,
  linked_to character varying,
  access_count bigint,
  status character varying,
  status_message text,
  created_at bigint,
  updated_at bigint,
  external_id character varying
);

CREATE TABLE IF NOT EXISTS ai.casebible_ingest_test_contents (
  id character varying NOT NULL,
  name character varying NOT NULL,
  description text NOT NULL,
  metadata jsonb,
  type character varying,
  size bigint,
  linked_to character varying,
  access_count bigint,
  status character varying,
  status_message text,
  created_at bigint,
  updated_at bigint,
  external_id character varying
);

CREATE TABLE IF NOT EXISTS ai.platform_context_contents (
  id character varying NOT NULL,
  name character varying NOT NULL,
  description text NOT NULL,
  metadata jsonb,
  type character varying,
  size bigint,
  linked_to character varying,
  access_count bigint,
  status character varying,
  status_message text,
  created_at bigint,
  updated_at bigint,
  external_id character varying
);

CREATE TABLE IF NOT EXISTS ai.platform_knowledge_contents (
  id character varying NOT NULL,
  name character varying NOT NULL,
  description text NOT NULL,
  metadata jsonb,
  type character varying,
  size bigint,
  linked_to character varying,
  access_count bigint,
  status character varying,
  status_message text,
  created_at bigint,
  updated_at bigint,
  external_id character varying
);

CREATE TABLE IF NOT EXISTS analysis.case_registry_import_receipt (
  id uuid DEFAULT uuidv7() NOT NULL,
  manifest_sha256 bytea NOT NULL,
  source_migration_uri text NOT NULL,
  source_migration_sha256 bytea NOT NULL,
  source_git_commit text NOT NULL,
  payload_schema_version text NOT NULL,
  payload_byte_length bigint NOT NULL,
  canonical_payload_sha256 bytea NOT NULL,
  api_payload_sha256 bytea NOT NULL,
  source_observed_at timestamp with time zone NOT NULL,
  matter_id uuid NOT NULL,
  court_case_id uuid NOT NULL,
  partition_key text NOT NULL,
  approved_by text NOT NULL,
  approved_on date NOT NULL,
  imported_by text NOT NULL,
  imported_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.chunk_classification (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  run_key text NOT NULL,
  batch_index integer NOT NULL,
  classifier_version text NOT NULL,
  conversation_key text,
  seq bigint,
  record_ref text,
  occurred_at timestamp with time zone,
  message_text text NOT NULL,
  labels text[] DEFAULT '{}'::text[] NOT NULL,
  sentiment text,
  severity integer,
  summary text,
  judge_verdict text,
  judge_confidence real,
  judge_model text,
  classify_model text,
  review_state text DEFAULT 'unreviewed'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  decision_id text,
  actor text,
  decision text,
  reason text,
  source text,
  adjudicated_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS analysis.claim_assertion (
  id uuid DEFAULT uuidv7() NOT NULL,
  assertion_generation smallint NOT NULL,
  assertion_kind text NOT NULL,
  statement text NOT NULL,
  rationale text NOT NULL,
  asserted_by_kind text NOT NULL,
  asserted_by text NOT NULL,
  asserted_at timestamp with time zone DEFAULT now() NOT NULL,
  salience text,
  argument_targets text[] DEFAULT '{}'::text[] NOT NULL,
  owner_disposition text DEFAULT 'unreviewed'::text NOT NULL,
  disposition_reason text,
  disposition_at timestamp with time zone,
  source_ref text,
  supersedes_id uuid,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.claim_assertion_member (
  assertion_id uuid NOT NULL,
  claim_candidate_id uuid NOT NULL,
  member_role text DEFAULT 'constituent'::text NOT NULL,
  member_ordinal integer NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS analysis.claim_assertion_synthesis_member (
  synthesis_id uuid NOT NULL,
  member_assertion_id uuid NOT NULL,
  member_generation smallint DEFAULT 1 NOT NULL,
  agreement_state text NOT NULL,
  divergence_note text,
  member_ordinal integer NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.completion_evidence (
  id uuid DEFAULT uuidv7() NOT NULL,
  task_id uuid NOT NULL,
  source_id uuid,
  evidence_item_id uuid,
  evidence_hash_id uuid,
  sha256 bytea,
  outcome text NOT NULL,
  outcome_note text,
  recorded_by text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.content_chunk_classification_decision (
  id uuid DEFAULT uuidv7() NOT NULL,
  chunk_id uuid NOT NULL,
  decision_version integer NOT NULL,
  lane text NOT NULL,
  decision_kind text NOT NULL,
  review_state text NOT NULL,
  classifier_id text NOT NULL,
  classifier_version text NOT NULL,
  confidence double precision NOT NULL,
  rationale text,
  supersedes_id uuid,
  reviewed_by text,
  reviewed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.corroboration_flag (
  flag_id uuid DEFAULT uuidv7() NOT NULL,
  target_kind text NOT NULL,
  target_id text NOT NULL,
  claim text NOT NULL,
  claim_date_start date,
  claim_date_end date,
  evidence_wanted text[],
  status text DEFAULT 'open'::text NOT NULL,
  linked_artifacts jsonb DEFAULT '[]'::jsonb NOT NULL,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.discovery_request (
  id uuid DEFAULT uuidv7() NOT NULL,
  task_id uuid NOT NULL,
  instrument_type text NOT NULL,
  target_person_id uuid,
  target_custodian text,
  draft_text text NOT NULL,
  scope_note text,
  status text DEFAULT 'draft'::text NOT NULL,
  hitl_status text DEFAULT 'pending'::text NOT NULL,
  prompt_version text,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.discovery_request_revision (
  revision_id uuid DEFAULT uuidv7() NOT NULL,
  request_id uuid NOT NULL,
  snapshot jsonb NOT NULL,
  changed_by text NOT NULL,
  ts timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.evidence_task (
  id uuid DEFAULT uuidv7() NOT NULL,
  task_key text NOT NULL,
  case_id uuid NOT NULL,
  finding_id uuid,
  trigger_kind text DEFAULT 'manual'::text NOT NULL,
  evidence_needed text NOT NULL,
  evidence_need_kind text DEFAULT 'corroboration'::text NOT NULL,
  likely_source_id uuid,
  likely_source_note text,
  priority text DEFAULT 'P3_low'::text NOT NULL,
  priority_score numeric,
  priority_inputs jsonb,
  priority_override text,
  priority_override_reason text,
  risk text DEFAULT 'none'::text NOT NULL,
  risk_kind text[] DEFAULT '{}'::text[] NOT NULL,
  risk_note text,
  due_date date,
  due_basis text,
  status text DEFAULT 'draft'::text NOT NULL,
  human_action text,
  human_action_kind text DEFAULT 'none_yet'::text NOT NULL,
  assertion_type assertion_type DEFAULT 'analytical_finding'::assertion_type NOT NULL,
  confidence ai.confidence,
  confidence_tier text DEFAULT 'low'::text NOT NULL,
  confidence_note text,
  is_hypothesis boolean DEFAULT false NOT NULL,
  label_sensitivity text DEFAULT 'routine'::text NOT NULL,
  hitl_required boolean DEFAULT false NOT NULL,
  hitl_status text DEFAULT 'pending'::text NOT NULL,
  source_run_id uuid,
  prompt_version text,
  ontology_version text,
  schema_version text,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  archive_reason text
);

CREATE TABLE IF NOT EXISTS analysis.export (
  export_id uuid DEFAULT uuidv7() NOT NULL,
  export_run uuid,
  package_uri text NOT NULL,
  manifest_sha256 bytea NOT NULL,
  signature bytea,
  included_artifacts uuid[] NOT NULL,
  tier sensitivity_tier NOT NULL,
  purpose text,
  requested_by text NOT NULL,
  approved_by text NOT NULL,
  blocked_by_open_questions uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.export_item (
  package_id uuid NOT NULL,
  evidence_item_id uuid NOT NULL,
  ordinal integer,
  included_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.export_package (
  id uuid DEFAULT uuidv7() NOT NULL,
  case_id uuid NOT NULL,
  package_name text NOT NULL,
  purpose text,
  status text DEFAULT 'draft'::text NOT NULL,
  approved_by text,
  approved_at timestamp with time zone,
  exported_at timestamp with time zone,
  manifest jsonb DEFAULT '{}'::jsonb NOT NULL,
  signature bytea,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.factor_citation (
  id uuid DEFAULT uuidv7() NOT NULL,
  evidence_item_id uuid NOT NULL,
  factor ai.mcl_factor NOT NULL,
  legal_issue_id uuid,
  supports_factor boolean NOT NULL,
  strength text DEFAULT 'moderate'::text NOT NULL,
  supporting_text text,
  relevance_explanation text,
  assertion_type assertion_type DEFAULT 'analytical_finding'::assertion_type NOT NULL,
  confidence ai.confidence,
  is_hypothesis boolean DEFAULT false NOT NULL,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  safe_for_legal_use boolean DEFAULT false NOT NULL,
  supersedes_citation_id uuid,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.finding (
  id uuid DEFAULT uuidv7() NOT NULL,
  case_id uuid,
  finding_type text NOT NULL,
  title text NOT NULL,
  statement text,
  subject_refs uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  conduct_party conduct_party,
  mcl_factors ai.mcl_factor[] DEFAULT '{}'::ai.mcl_factor[] NOT NULL,
  assertion_type assertion_type DEFAULT 'analytical_finding'::assertion_type NOT NULL,
  data_tier evidence_tier DEFAULT 'analytical'::evidence_tier NOT NULL,
  confidence ai.confidence,
  evidence_strength strength_class,
  is_hypothesis boolean DEFAULT true NOT NULL,
  requires_human_review boolean DEFAULT true NOT NULL,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  safe_for_legal_use boolean DEFAULT false NOT NULL,
  bias_caution boolean DEFAULT true NOT NULL,
  authored_perspective text,
  provenance_id uuid,
  created_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  pattern_type text,
  span_message_ids uuid[],
  span_message_count integer,
  span_start timestamp with time zone,
  span_end timestamp with time zone,
  severity_progression text,
  escalation_index numeric,
  contradicts_finding_id uuid
);

CREATE TABLE IF NOT EXISTS analysis.finding_version (
  version_id uuid DEFAULT uuidv7() NOT NULL,
  finding_id uuid NOT NULL,
  snapshot jsonb NOT NULL,
  changed_by text NOT NULL,
  change_note text,
  ts timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.graph_edge_projection (
  id uuid DEFAULT uuidv7() NOT NULL,
  graph_lane analysis.graph_lane NOT NULL,
  graph_database text NOT NULL,
  graph_edge_id text NOT NULL,
  edge_type text NOT NULL,
  from_node_id text NOT NULL,
  to_node_id text NOT NULL,
  source_version_id uuid,
  normalized_record_id uuid,
  content_chunk_id uuid,
  span_start integer,
  span_end integer,
  source_provenance_ref jsonb,
  extractor_name text NOT NULL,
  extractor_version text NOT NULL,
  model_id text,
  prompt_version text,
  run_id uuid,
  source_generation bigint,
  projected_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.graph_node_projection (
  id uuid DEFAULT uuidv7() NOT NULL,
  graph_lane analysis.graph_lane NOT NULL,
  graph_database text NOT NULL,
  graph_node_id text NOT NULL,
  node_labels text[] DEFAULT '{}'::text[] NOT NULL,
  source_version_id uuid,
  normalized_record_id uuid,
  content_chunk_id uuid,
  chat_message_id uuid,
  span_start integer,
  span_end integer,
  source_provenance_ref jsonb,
  extractor_name text NOT NULL,
  extractor_version text NOT NULL,
  model_id text,
  prompt_version text,
  run_id uuid,
  source_generation bigint,
  projected_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.graphrag_comparison_join (
  id uuid DEFAULT uuidv7() NOT NULL,
  run_id uuid NOT NULL,
  stage_id text NOT NULL,
  stage_version text NOT NULL,
  manifest_id uuid NOT NULL,
  manifest_digest bytea NOT NULL,
  semantica_receipt_id uuid,
  sat_temporal_receipt_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.graphrag_comparison_run (
  id uuid DEFAULT uuidv7() NOT NULL,
  query_reference text NOT NULL,
  correlation_id text,
  requested_mode text NOT NULL,
  case_compatibility_reference text,
  horizon_at timestamp with time zone NOT NULL,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.graphrag_eligibility_manifest (
  id uuid DEFAULT uuidv7() NOT NULL,
  run_id uuid NOT NULL,
  schema_version integer DEFAULT 1 NOT NULL,
  pg_generation_reference text NOT NULL,
  source_availability_policy_version text NOT NULL,
  disclosure_policy_version text NOT NULL,
  authorization_policy_version text NOT NULL,
  issuer text NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  membership_digest bytea,
  member_count integer,
  sealed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.graphrag_eligibility_manifest_member (
  manifest_id uuid NOT NULL,
  ordinal bigint NOT NULL,
  source_version_id uuid NOT NULL,
  normalized_record_id uuid NOT NULL,
  text_unit_id uuid,
  source_sha256 bytea,
  normalized_record_digest bytea,
  source_available_from timestamp with time zone,
  disclosure_tier text,
  authority_class text,
  projection_version text,
  source_provenance_ref jsonb
);

CREATE TABLE IF NOT EXISTS analysis.graphrag_lane_candidate (
  id uuid DEFAULT uuidv7() NOT NULL,
  lane_result_id uuid NOT NULL,
  ordinal bigint NOT NULL,
  source_version_id uuid NOT NULL,
  normalized_record_id uuid NOT NULL,
  text_unit_id uuid,
  source_sha256 bytea,
  normalized_record_digest bytea,
  source_available_from timestamp with time zone,
  disclosure_tier text,
  authority_class text,
  projection_version text,
  candidate_type text NOT NULL,
  candidate_ref jsonb,
  trace_ref jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.graphrag_lane_receipt (
  id uuid DEFAULT uuidv7() NOT NULL,
  run_id uuid NOT NULL,
  lane_id analysis.graph_lane NOT NULL,
  stage_id text NOT NULL,
  stage_version text NOT NULL,
  manifest_id uuid NOT NULL,
  manifest_digest bytea NOT NULL,
  status text NOT NULL,
  lane_result_id uuid,
  outcome_ref jsonb,
  error_ref jsonb,
  completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.graphrag_lane_result (
  id uuid DEFAULT uuidv7() NOT NULL,
  run_id uuid NOT NULL,
  lane_id analysis.graph_lane NOT NULL,
  manifest_id uuid NOT NULL,
  manifest_digest bytea NOT NULL,
  projection_version text,
  status text NOT NULL,
  trace_ref jsonb,
  warning_refs jsonb,
  error_ref jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.human_label (
  conversation_key text NOT NULL,
  seq bigint NOT NULL,
  occurred_at timestamp with time zone,
  who text,
  message_text text NOT NULL,
  labels text[] DEFAULT '{}'::text[] NOT NULL,
  is_clean boolean,
  severity integer,
  notes text
);

CREATE TABLE IF NOT EXISTS analysis.human_label_gold (
  legacy_message_id uuid,
  conversation_key text NOT NULL,
  seq bigint NOT NULL,
  occurred_at timestamp with time zone,
  who text,
  message_text text,
  ai_flagged text,
  ai_flag_count integer,
  labels text[],
  is_clean boolean,
  severity integer,
  notes text,
  labeled_by text,
  labeled_at timestamp with time zone,
  created_at timestamp with time zone,
  relink_status text,
  archived_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS analysis.knowledge_evidence_promotion (
  id uuid DEFAULT uuidv7() NOT NULL,
  idempotency_key text NOT NULL,
  partition_key text NOT NULL,
  matter_id uuid NOT NULL,
  court_case_id uuid NOT NULL,
  evidence_item_id uuid NOT NULL,
  normalized_record_id uuid NOT NULL,
  evidence_hash_id uuid NOT NULL,
  source_id uuid,
  file_node_id uuid,
  source_run_id uuid,
  knowledge_lane text NOT NULL,
  retrieval_item_ref text NOT NULL,
  content_ref text,
  chunk_ref text,
  source_pointer jsonb NOT NULL,
  source_pointer_hash bytea NOT NULL,
  promoted_by text NOT NULL,
  promoted_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.legal_timeline_event (
  id uuid DEFAULT uuidv7() NOT NULL,
  case_id uuid NOT NULL,
  event_date timestamp with time zone NOT NULL,
  event_date_end timestamp with time zone,
  date_precision precision_class DEFAULT 'exact'::precision_class NOT NULL,
  title text NOT NULL,
  description text,
  event_type text DEFAULT 'communication'::text NOT NULL,
  evidence_item_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  normalized_record_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  mcl_factors ai.mcl_factor[] DEFAULT '{}'::ai.mcl_factor[] NOT NULL,
  participants text[] DEFAULT '{}'::text[] NOT NULL,
  assertion_type assertion_type DEFAULT 'analytical_finding'::assertion_type NOT NULL,
  confidence ai.confidence,
  is_verified boolean DEFAULT false NOT NULL,
  is_disputed boolean DEFAULT false NOT NULL,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  safe_for_legal_use boolean DEFAULT false NOT NULL,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.location_assertion (
  id uuid DEFAULT uuidv7() NOT NULL,
  subject_type text NOT NULL,
  subject_id uuid NOT NULL,
  location_id uuid,
  geog ai.geo_point,
  asserted_at_ts timestamp with time zone,
  ts_precision precision_class DEFAULT 'inferred'::precision_class NOT NULL,
  spatial_confidence ai.confidence,
  assertion_source assertion_source NOT NULL,
  evidence_strength strength_class,
  requires_human_review boolean DEFAULT false NOT NULL,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  safe_for_legal_use boolean DEFAULT false NOT NULL,
  data_tier evidence_tier DEFAULT 'inferred'::evidence_tier NOT NULL,
  provenance_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.location_contradiction (
  id uuid DEFAULT uuidv7() NOT NULL,
  claimed_assertion_id uuid NOT NULL,
  observed_assertion_id uuid NOT NULL,
  distance_m numeric(12,2),
  disagreement_flag boolean DEFAULT false NOT NULL,
  tie_break_reason text,
  analysis_confidence ai.confidence,
  requires_human_review boolean DEFAULT true NOT NULL,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  safe_for_legal_use boolean DEFAULT false NOT NULL,
  data_tier evidence_tier DEFAULT 'analytical'::evidence_tier NOT NULL,
  provenance_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.matter_knowledge_partition (
  partition_key text NOT NULL,
  matter_id uuid NOT NULL,
  default_court_case_id uuid NOT NULL,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.pattern_finding (
  id uuid DEFAULT uuidv7() NOT NULL,
  subject_type text NOT NULL,
  subject_id uuid NOT NULL,
  category_id citext NOT NULL,
  pattern_id uuid,
  pattern_set_id uuid,
  subcategory text,
  detection_method detection_method NOT NULL,
  rule_name text,
  matched_text text,
  matched_pattern text,
  start_char integer,
  end_char integer,
  context_before text,
  context_after text,
  author_party conduct_party,
  author_entity_id uuid,
  bias_caution boolean DEFAULT true NOT NULL,
  authored_perspective text,
  confidence ai.confidence,
  severity smallint,
  score smallint,
  evidence_strength strength_class,
  is_verified boolean DEFAULT false NOT NULL,
  verified_by text,
  verified_at timestamp with time zone,
  verification_notes text,
  requires_human_review boolean DEFAULT true NOT NULL,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  safe_for_legal_use boolean DEFAULT false NOT NULL,
  finding_id uuid,
  data_tier evidence_tier DEFAULT 'inferred'::evidence_tier NOT NULL,
  provenance_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.redaction (
  redaction_id uuid DEFAULT uuidv7() NOT NULL,
  redaction_run uuid,
  source_artifact uuid NOT NULL,
  redacted_artifact uuid NOT NULL,
  policy_version text NOT NULL,
  redaction_map jsonb NOT NULL,
  reversible boolean DEFAULT true NOT NULL,
  authorized_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.relational_classification (
  id uuid DEFAULT uuidv7() NOT NULL,
  subject_type text NOT NULL,
  subject_id uuid NOT NULL,
  event_category text,
  surface_sentiment text,
  emotional_tone text,
  relational_function text,
  cycle_phase cycle_phase,
  cycle_transition_type text,
  love_bombing_indicator boolean,
  repair_attempt_indicator boolean,
  cooperation_indicator boolean,
  neutral_context_indicator boolean,
  precedes_concerning_event boolean,
  follows_concerning_event boolean,
  temporal_proximity_to_conflict_s bigint,
  changes_nearby_interpretation boolean,
  corroborated boolean,
  conduct_party conduct_party,
  pattern_relevance text,
  mcl_factor_hint ai.mcl_factor,
  classified_by text,
  confidence ai.confidence,
  detector_provenance_id uuid,
  requires_human_review boolean DEFAULT true NOT NULL,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  safe_for_legal_use boolean DEFAULT false NOT NULL,
  data_tier evidence_tier DEFAULT 'analytical'::evidence_tier NOT NULL,
  provenance_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.resolution_evidence (
  id uuid DEFAULT uuidv7() NOT NULL,
  resolution_id uuid NOT NULL,
  polarity text NOT NULL,
  method text,
  evidence_ref_type text,
  evidence_ref_id uuid,
  weight ai.confidence,
  note text,
  provenance ai.source_ref[] DEFAULT '{}'::ai.source_ref[] NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.review_decision (
  decision_id uuid DEFAULT uuidv7() NOT NULL,
  task_id uuid,
  target_kind text NOT NULL,
  target_id uuid NOT NULL,
  reviewer text NOT NULL,
  decision text NOT NULL,
  set_confidence ai.confidence,
  set_evidence_strength strength_class,
  sensitive_label_decision jsonb,
  court_readiness text DEFAULT 'not_reviewed'::text NOT NULL,
  tier_approved sensitivity_tier,
  requires_corroboration boolean DEFAULT false NOT NULL,
  score_snapshot uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  prompt_version_id uuid,
  ontology_version_id uuid,
  schema_version_id uuid,
  rationale text NOT NULL,
  decided_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.review_task (
  task_id uuid DEFAULT uuidv7() NOT NULL,
  trigger_code text NOT NULL,
  target_kind text NOT NULL,
  target_id uuid NOT NULL,
  score_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  blocks text NOT NULL,
  reviewer_role text,
  state text DEFAULT 'pending'::text NOT NULL,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.score (
  score_id uuid DEFAULT uuidv7() NOT NULL,
  target_kind text NOT NULL,
  target_id uuid NOT NULL,
  score_type text NOT NULL,
  value ai.confidence NOT NULL,
  band text NOT NULL,
  method text NOT NULL,
  method_detail jsonb DEFAULT '{}'::jsonb NOT NULL,
  rationale text NOT NULL,
  evidence_refs uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  assertion_type assertion_type NOT NULL,
  config_version text,
  scoring_run_id uuid NOT NULL,
  recheck_after timestamp with time zone,
  stale boolean DEFAULT false NOT NULL,
  valid_from timestamp with time zone DEFAULT now() NOT NULL,
  valid_to timestamp with time zone,
  superseded_by uuid,
  created_by text NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.task_dependency (
  task_id uuid NOT NULL,
  depends_on uuid NOT NULL,
  dep_kind text NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.task_event (
  event_id uuid DEFAULT uuidv7() NOT NULL,
  task_id uuid NOT NULL,
  from_status text,
  to_status text NOT NULL,
  actor text NOT NULL,
  actor_kind text NOT NULL,
  reason text,
  ts timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.task_legal_link (
  task_id uuid NOT NULL,
  legal_issue_id uuid NOT NULL,
  factor ai.mcl_factor NOT NULL,
  element_note text
);

CREATE TABLE IF NOT EXISTS analysis.task_person (
  task_id uuid NOT NULL,
  person_id uuid NOT NULL,
  role text NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.task_revision (
  revision_id uuid DEFAULT uuidv7() NOT NULL,
  task_id uuid NOT NULL,
  snapshot jsonb NOT NULL,
  changed_by text NOT NULL,
  change_note text,
  ts timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.time_assertion (
  assertion_id uuid DEFAULT uuidv7() NOT NULL,
  event_id uuid NOT NULL,
  valid_earliest timestamp with time zone NOT NULL,
  valid_latest timestamp with time zone NOT NULL,
  valid_point timestamp with time zone,
  valid_range tstzrange GENERATED ALWAYS AS (tstzrange(valid_earliest, valid_latest, '[]'::text)) STORED,
  ts_raw text,
  ts_utc timestamp with time zone,
  tz_offset_minutes integer,
  tz_source text,
  certainty precision_class NOT NULL,
  assertion_type assertion_type DEFAULT 'extracted_fact'::assertion_type NOT NULL,
  confidence ai.confidence,
  disclosure_horizon disclosure_horizon DEFAULT 'contemporaneous'::disclosure_horizon NOT NULL,
  is_conflicted boolean DEFAULT false NOT NULL,
  requires_human_review boolean DEFAULT false NOT NULL,
  discovered_at timestamp with time zone,
  discovery_source uuid,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL,
  ingest_run_id uuid,
  sys_period tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone) NOT NULL,
  superseded_by uuid,
  derived_from uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  anchor_refs uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  reasoning text,
  prompt_version text,
  ontology_version text,
  schema_version text,
  author text NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.timeline_event (
  event_id uuid DEFAULT uuidv7() NOT NULL,
  canonical_event_id ai.canonical_id,
  event_key citext,
  serial_id bigint,
  title text NOT NULL,
  description text,
  event_type ai.event_type NOT NULL,
  temporal_class ai.temporal_class DEFAULT 'historical'::ai.temporal_class NOT NULL,
  valid_earliest timestamp with time zone,
  valid_latest timestamp with time zone,
  valid_point timestamp with time zone,
  valid_range tstzrange GENERATED ALWAYS AS (tstzrange(valid_earliest, valid_latest, '[]'::text)) STORED,
  current_certainty precision_class,
  current_confidence ai.confidence,
  disclosure_horizon disclosure_horizon DEFAULT 'contemporaneous'::disclosure_horizon NOT NULL,
  assertion_type assertion_type DEFAULT 'analytical_finding'::assertion_type NOT NULL,
  location_id uuid,
  primary_geo ai.geo_point,
  is_conflicted boolean DEFAULT false NOT NULL,
  requires_human_review boolean DEFAULT false NOT NULL,
  safe_for_legal_use boolean DEFAULT false NOT NULL,
  reviewed_by text,
  reviewed_at timestamp with time zone,
  conduct_party conduct_party,
  mcl_relevance ai.mcl_factor[] DEFAULT '{}'::ai.mcl_factor[] NOT NULL,
  source_artifact_id uuid,
  primary_record_id uuid,
  ingest_run_id uuid,
  derived_from uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  prompt_version text,
  ontology_version text,
  schema_version text,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.workflow_run (
  run_id uuid DEFAULT uuidv7() NOT NULL,
  workflow text NOT NULL,
  mode text DEFAULT 'auto'::text NOT NULL,
  source_name text,
  source_path text,
  sha256 text,
  artifact_id text,
  domain text,
  status text DEFAULT 'running'::text NOT NULL,
  summary jsonb,
  error text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  gate_state text,
  parent_run_id uuid,
  custody_tier text DEFAULT 'full'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS analysis.workflow_run_stage (
  stage_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  run_id uuid NOT NULL,
  seq integer NOT NULL,
  name text NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  content text,
  output jsonb,
  started_at timestamp with time zone,
  finished_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS canon.canonical_table (
  id uuid DEFAULT uuidv7() NOT NULL,
  table_schema text NOT NULL,
  table_name text NOT NULL,
  default_tier text DEFAULT 'batch_review'::text NOT NULL,
  current_generation bigint DEFAULT 0 NOT NULL,
  recompute_targets text[] DEFAULT '{}'::text[] NOT NULL,
  registered_by text NOT NULL,
  registered_at timestamp with time zone DEFAULT now() NOT NULL,
  notes text,
  auto_confirm_min_confidence ai.confidence
);

CREATE TABLE IF NOT EXISTS canon.change_application (
  id uuid DEFAULT uuidv7() NOT NULL,
  proposal_id uuid NOT NULL,
  decision_id uuid NOT NULL,
  prior_values jsonb NOT NULL,
  applied_patch jsonb NOT NULL,
  generation_before bigint NOT NULL,
  generation_after bigint NOT NULL,
  applied_at timestamp with time zone DEFAULT now() NOT NULL,
  error text
);

CREATE TABLE IF NOT EXISTS canon.change_decision (
  id uuid DEFAULT uuidv7() NOT NULL,
  proposal_id uuid NOT NULL,
  decided_by text NOT NULL,
  decision text NOT NULL,
  batch_id uuid,
  note text,
  decided_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS canon.change_proposal (
  id uuid DEFAULT uuidv7() NOT NULL,
  canonical_table_id uuid NOT NULL,
  target_pk jsonb NOT NULL,
  proposal_kind text NOT NULL,
  patch jsonb NOT NULL,
  rationale text,
  origin_surface text NOT NULL,
  origin_ref jsonb DEFAULT '{}'::jsonb NOT NULL,
  proposed_by text NOT NULL,
  source_generation bigint NOT NULL,
  tier text NOT NULL,
  status text DEFAULT 'proposed'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS canon.change_tier (
  tier text NOT NULL,
  description text NOT NULL,
  auto_applies boolean DEFAULT false NOT NULL,
  sort_order integer DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS canon.recompute_queue (
  id uuid DEFAULT uuidv7() NOT NULL,
  application_id uuid NOT NULL,
  canonical_table_id uuid NOT NULL,
  target_pk jsonb NOT NULL,
  recompute_target text NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  claimed_by text,
  claimed_at timestamp with time zone,
  finished_at timestamp with time zone,
  error text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.activity_execution (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_version_id uuid NOT NULL,
  workflow_id text NOT NULL,
  activity_name text NOT NULL,
  idempotency_key text NOT NULL,
  request_digest bytea,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.activity_receipt (
  id uuid DEFAULT uuidv7() NOT NULL,
  activity_execution_id uuid NOT NULL,
  attempt integer NOT NULL,
  status text NOT NULL,
  started_at timestamp with time zone NOT NULL,
  completed_at timestamp with time zone,
  result_ref jsonb,
  error_detail jsonb,
  not_applicable_reason text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.first_party_thread_message_relative_time_anchor (
  anchor_id uuid NOT NULL,
  thread_version_id uuid NOT NULL,
  message_id uuid NOT NULL,
  link_role text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.first_party_thread_source_relative_time_anchor (
  anchor_id uuid NOT NULL,
  thread_source_id uuid NOT NULL,
  link_role text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.first_party_thread_version_relative_time_anchor (
  anchor_id uuid NOT NULL,
  thread_version_id uuid NOT NULL,
  link_role text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.hash_batch (
  id uuid DEFAULT uuidv7() NOT NULL,
  activity_execution_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  attempt integer NOT NULL,
  hash_kind text NOT NULL,
  raw_generation_id uuid,
  normalized_generation_id uuid,
  status text DEFAULT 'open'::text NOT NULL,
  member_count bigint,
  result_ref jsonb,
  activity_receipt_id uuid,
  completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.hash_batch_member (
  hash_batch_id uuid NOT NULL,
  ordinal bigint NOT NULL,
  source_version_id uuid,
  raw_record_id uuid,
  normalized_record_id uuid,
  digest bytea NOT NULL,
  construction text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.hash_manifest (
  id uuid DEFAULT uuidv7() NOT NULL,
  hash_kind text NOT NULL,
  raw_generation_id uuid,
  normalized_generation_id uuid,
  status text DEFAULT 'open'::text NOT NULL,
  member_count bigint,
  sealed_hash_receipt_id uuid,
  sealed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.hash_manifest_member (
  hash_manifest_id uuid NOT NULL,
  ordinal bigint NOT NULL,
  raw_record_id uuid,
  normalized_record_id uuid,
  member_digest bytea NOT NULL,
  member_canon text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.hash_receipt (
  id uuid DEFAULT uuidv7() NOT NULL,
  activity_receipt_id uuid NOT NULL,
  hash_kind text NOT NULL,
  algorithm text DEFAULT 'sha256'::text NOT NULL,
  digest bytea NOT NULL,
  construction text NOT NULL,
  hash_manifest_id uuid,
  source_version_id uuid,
  raw_record_id uuid,
  raw_generation_id uuid,
  normalized_record_id uuid,
  normalized_generation_id uuid,
  computed_at timestamp with time zone NOT NULL,
  computed_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.normalization_lineage (
  id uuid DEFAULT uuidv7() NOT NULL,
  normalized_generation_id uuid NOT NULL,
  raw_generation_id uuid NOT NULL,
  normalized_record_id uuid NOT NULL,
  raw_record_id uuid NOT NULL,
  derivation_role text NOT NULL,
  source_span_offset bigint,
  source_span_length bigint,
  field_map jsonb DEFAULT '[]'::jsonb NOT NULL,
  normalizer_id text NOT NULL,
  normalizer_version text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.normalized_generation (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_version_id uuid NOT NULL,
  raw_generation_id uuid NOT NULL,
  generation_ordinal integer NOT NULL,
  normalizer_id text NOT NULL,
  normalizer_version text NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  sealed_at timestamp with time zone,
  sealed_by text,
  published_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.normalized_generation_publication (
  id uuid DEFAULT uuidv7() NOT NULL,
  normalized_generation_id uuid NOT NULL,
  activity_receipt_id uuid NOT NULL,
  idempotency_key text NOT NULL,
  publication_ref jsonb NOT NULL,
  published_at timestamp with time zone NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.normalized_record_identity (
  id uuid DEFAULT uuidv7() NOT NULL,
  normalized_generation_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  record_ordinal bigint NOT NULL,
  record_type text NOT NULL,
  occurred_at timestamp with time zone,
  canonical_bytes bytea NOT NULL,
  canonicalization text NOT NULL,
  normalized_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.normalized_record_range_locator (
  source_range_locator_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  normalized_record_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.raw_format_registry (
  format_id text NOT NULL,
  subtype_relation regclass NOT NULL,
  registered_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.raw_generation (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_version_id uuid NOT NULL,
  generation_ordinal integer NOT NULL,
  format_id text NOT NULL,
  parser_id text NOT NULL,
  parser_version text NOT NULL,
  extraction_bundle_object_id uuid,
  status text DEFAULT 'open'::text NOT NULL,
  sealed_at timestamp with time zone,
  sealed_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  context_source_fingerprint_ref uuid,
  context_raw_fingerprint_manifest_ref uuid,
  context_raw_generation_fingerprint_ref uuid,
  context_raw_source_verification_ref uuid
);

CREATE TABLE IF NOT EXISTS context.raw_record_identity (
  id uuid DEFAULT uuidv7() NOT NULL,
  raw_generation_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  format_id text NOT NULL,
  record_ordinal bigint NOT NULL,
  record_status text NOT NULL,
  raw_hash_construction text NOT NULL,
  status_reason text,
  locator_object_id uuid,
  byte_offset bigint,
  byte_length bigint,
  stored_bytes bytea,
  native_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.raw_record_range_locator (
  source_range_locator_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  raw_record_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.reconciliation_receipt (
  id uuid DEFAULT uuidv7() NOT NULL,
  activity_receipt_id uuid NOT NULL,
  reconciliation_kind text NOT NULL,
  raw_generation_id uuid,
  normalized_generation_id uuid,
  status text NOT NULL,
  expected jsonb DEFAULT '{}'::jsonb NOT NULL,
  observed jsonb DEFAULT '{}'::jsonb NOT NULL,
  discrepancies jsonb DEFAULT '[]'::jsonb NOT NULL,
  verified_at timestamp with time zone NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.relative_time_anchor (
  id uuid DEFAULT uuidv7() NOT NULL,
  anchor_key uuid DEFAULT uuidv7() NOT NULL,
  version_ordinal integer NOT NULL,
  placement_kind text NOT NULL,
  lower_bound_at timestamp with time zone,
  upper_bound_at timestamp with time zone,
  last_known_before_anchor_id uuid,
  first_known_after_anchor_id uuid,
  contextual_sequence_key text,
  contextual_sequence_ordinal bigint,
  metadata_basis text NOT NULL,
  raw_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  raw_metadata_ref text,
  confidence double precision NOT NULL,
  ambiguity text,
  review_state text NOT NULL,
  reviewed_by text,
  reviewed_at timestamp with time zone,
  provenance_digest bytea NOT NULL,
  supersedes_id uuid,
  presentation_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.repair_assessment (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_version_id uuid NOT NULL,
  original_object_id uuid NOT NULL,
  activity_receipt_id uuid NOT NULL,
  declared_format text NOT NULL,
  detection jsonb NOT NULL,
  preview jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.repair_decision (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_version_id uuid NOT NULL,
  assessment_id uuid NOT NULL,
  actor_ref text NOT NULL,
  approved boolean NOT NULL,
  apply_repair boolean NOT NULL,
  tool_id text,
  tool_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
  decision_idempotency_key text NOT NULL,
  decided_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.repair_resolution (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_version_id uuid NOT NULL,
  assessment_id uuid NOT NULL,
  decision_id uuid NOT NULL,
  original_object_id uuid NOT NULL,
  active_object_id uuid NOT NULL,
  activity_receipt_id uuid NOT NULL,
  actor_ref text NOT NULL,
  applied boolean NOT NULL,
  tool_id text,
  tool_result jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.retained_object (
  id uuid DEFAULT uuidv7() NOT NULL,
  storage_class text NOT NULL,
  object_uri text NOT NULL,
  content_sha256 bytea NOT NULL,
  byte_length bigint NOT NULL,
  inline_bytes bytea,
  immutable_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.source (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_key text NOT NULL,
  provenance_class text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.source_metadata (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_version_id uuid NOT NULL,
  raw_record_id uuid,
  metadata_class text NOT NULL,
  metadata jsonb NOT NULL,
  extractor_id text NOT NULL,
  extractor_version text,
  extraction_activity_receipt_id uuid NOT NULL,
  generated_at timestamp with time zone NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.source_object_range_locator (
  source_range_locator_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  source_object_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.source_range_locator (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_version_id uuid NOT NULL,
  coordinate_system text NOT NULL,
  range_start bigint NOT NULL,
  range_end bigint NOT NULL,
  exact_slice_sha256 bytea NOT NULL,
  verification_activity_receipt_id uuid NOT NULL,
  locator_projection jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.source_version (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  version_ordinal integer NOT NULL,
  workflow_id text NOT NULL,
  submission_idempotency_key text NOT NULL,
  declared_format text NOT NULL,
  original_filename text,
  acquired_at timestamp with time zone NOT NULL,
  original_object_id uuid,
  status text DEFAULT 'registered'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  matter_id uuid,
  court_case_id uuid,
  source_context_ref uuid
);

CREATE TABLE IF NOT EXISTS context.source_version_object (
  source_version_id uuid NOT NULL,
  object_id uuid NOT NULL,
  object_role text NOT NULL,
  parent_object_id uuid,
  member_locator jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.third_party_thread_message_relative_time_anchor (
  anchor_id uuid NOT NULL,
  thread_version_id uuid NOT NULL,
  message_id uuid NOT NULL,
  link_role text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.third_party_thread_source_relative_time_anchor (
  anchor_id uuid NOT NULL,
  thread_source_id uuid NOT NULL,
  link_role text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.third_party_thread_version_relative_time_anchor (
  anchor_id uuid NOT NULL,
  thread_version_id uuid NOT NULL,
  link_role text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.uiw_preview_attachment (
  preview_handle text NOT NULL,
  snapshot_seq bigint NOT NULL,
  message_id text NOT NULL,
  attachment_id text NOT NULL,
  filename text,
  media_type text,
  byte_length bigint,
  sha256 bytea,
  source_locator_ref text NOT NULL
);

CREATE TABLE IF NOT EXISTS context.uiw_preview_binding (
  preview_handle text NOT NULL,
  request_id text NOT NULL,
  source_ref text NOT NULL,
  workflow_id text NOT NULL,
  run_id text NOT NULL,
  parser_options_ref text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.uiw_preview_decision (
  id uuid NOT NULL,
  preview_handle text NOT NULL,
  decision_key bytea NOT NULL,
  approved boolean NOT NULL,
  reason text DEFAULT ''::text NOT NULL,
  actor_subject_uid text NOT NULL,
  selection_ref text NOT NULL,
  parser_options_ref text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.uiw_preview_event (
  preview_handle text NOT NULL,
  event_id bigint NOT NULL,
  event_type text NOT NULL,
  occurred_at timestamp with time zone NOT NULL,
  phase text NOT NULL,
  receipt_ref text,
  message_count integer,
  detail text DEFAULT ''::text NOT NULL
);

CREATE TABLE IF NOT EXISTS context.uiw_preview_message (
  preview_handle text NOT NULL,
  snapshot_seq bigint NOT NULL,
  message_id text NOT NULL,
  ordinal bigint NOT NULL,
  sent_at timestamp with time zone,
  sender_participant_id text,
  body text NOT NULL,
  participant_ids text[] DEFAULT '{}'::text[] NOT NULL,
  source_locator_ref text NOT NULL
);

CREATE TABLE IF NOT EXISTS context.uiw_preview_participant (
  preview_handle text NOT NULL,
  snapshot_seq bigint NOT NULL,
  participant_id text NOT NULL,
  display_name text NOT NULL,
  canonical_address text
);

CREATE TABLE IF NOT EXISTS context.uiw_preview_receipt (
  preview_handle text NOT NULL,
  snapshot_seq bigint NOT NULL,
  receipt_type text NOT NULL,
  receipt_ref text NOT NULL,
  status text NOT NULL,
  digest bytea,
  recorded_at timestamp with time zone NOT NULL
);

CREATE TABLE IF NOT EXISTS context.uiw_preview_snapshot (
  preview_handle text NOT NULL,
  snapshot_seq bigint NOT NULL,
  phase text NOT NULL,
  source_version_id uuid NOT NULL,
  raw_generation_id uuid NOT NULL,
  normalized_generation_id uuid NOT NULL,
  parser_id text,
  parser_version text,
  parser_config_digest bytea,
  preview_digest bytea NOT NULL,
  reason text DEFAULT ''::text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS context.uiw_source_context_revision (
  source_context_ref uuid NOT NULL,
  request_id text NOT NULL,
  revision integer NOT NULL,
  supersedes_ref uuid,
  matter_id uuid NOT NULL,
  court_case_id uuid NOT NULL,
  source_ref text NOT NULL,
  observed_source jsonb NOT NULL,
  previous_assertions jsonb,
  assertions jsonb NOT NULL,
  change_reason text NOT NULL,
  actor_subject_uid text NOT NULL,
  actor_username text NOT NULL,
  idempotency_key text NOT NULL,
  content_digest bytea NOT NULL,
  receipt_ref text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS evidence.acquisition (
  id uuid DEFAULT uuidv7() NOT NULL,
  method evidence.acquisition_method DEFAULT 'unknown'::evidence.acquisition_method NOT NULL,
  authority evidence.acquisition_authority DEFAULT 'unclear'::evidence.acquisition_authority NOT NULL,
  source_device text,
  device_custodian text,
  custody_transferred_at timestamp with time zone,
  acquired_at timestamp with time zone,
  export_created_at timestamp with time zone,
  notes text,
  producible boolean DEFAULT false NOT NULL,
  supersedes_id uuid,
  asserted_by text DEFAULT 'human'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  device_id uuid,
  asserted_by_identity text NOT NULL
);

CREATE TABLE IF NOT EXISTS evidence.artifact_metadata (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  acquisition_id uuid,
  fs_original_path text,
  fs_filename text,
  fs_size_bytes bigint,
  fs_mtime timestamp with time zone,
  fs_ctime timestamp with time zone,
  fs_birthtime timestamp with time zone,
  fs_observed_at timestamp with time zone DEFAULT now() NOT NULL,
  embedded jsonb DEFAULT '{}'::jsonb NOT NULL,
  embedded_export_at timestamp with time zone,
  export_set_id text,
  export_kind text,
  record_count_claimed integer,
  filename_export_at timestamp with time zone,
  resolved_export_at timestamp with time zone,
  resolved_source text,
  layer_disagreement jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS evidence.custody_event (
  seq bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  file_node_id uuid,
  evidence_hash_id uuid,
  event_type text NOT NULL,
  actor text NOT NULL,
  occurred_at timestamp with time zone DEFAULT now() NOT NULL,
  occurred_certainty precision_class DEFAULT 'exact'::precision_class NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL,
  prev_event_digest bytea,
  event_digest bytea NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS evidence.evidence_hash (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_ref text NOT NULL,
  algo text DEFAULT 'sha256'::text NOT NULL,
  digest bytea NOT NULL,
  hashed_at timestamp with time zone DEFAULT now() NOT NULL,
  blob_key text,
  meta jsonb DEFAULT '{}'::jsonb NOT NULL,
  level text DEFAULT 'H1'::text NOT NULL,
  source_id uuid,
  file_node_id uuid,
  md5_prefilter bytea,
  record_locator jsonb,
  member_hash_ids uuid[],
  canon_version text DEFAULT 'h1-rawbytes-v1'::text NOT NULL,
  computed_by text
);

CREATE TABLE IF NOT EXISTS evidence.evidence_item (
  id uuid DEFAULT uuidv7() NOT NULL,
  case_id uuid NOT NULL,
  source_id uuid,
  file_node_id uuid,
  normalized_record_id uuid,
  evidence_hash_id uuid,
  exhibit_number text,
  title text NOT NULL,
  description text,
  quote text,
  context text,
  evidence_type text DEFAULT 'communication'::text NOT NULL,
  evidence_date timestamp with time zone,
  evidence_date_end timestamp with time zone,
  date_precision precision_class DEFAULT 'exact'::precision_class NOT NULL,
  assertion_type assertion_type DEFAULT 'extracted_fact'::assertion_type NOT NULL,
  confidence ai.confidence,
  confidence_tier text DEFAULT 'low'::text NOT NULL,
  relevance_score ai.confidence,
  is_hypothesis boolean DEFAULT false NOT NULL,
  is_exhibit boolean DEFAULT false NOT NULL,
  is_authenticated boolean DEFAULT false NOT NULL,
  authentication_method text,
  chain_of_custody text,
  sensitivity_tier sensitivity_tier DEFAULT 'restricted'::sensitivity_tier NOT NULL,
  privacy_sensitivity text DEFAULT 'none'::text NOT NULL,
  redaction_status text DEFAULT 'none'::text NOT NULL,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  reviewed_by text,
  reviewed_at timestamp with time zone,
  hitl_required boolean DEFAULT true NOT NULL,
  safe_for_legal_use boolean DEFAULT false NOT NULL,
  supersedes_item_id uuid,
  source_run_id uuid,
  prompt_version text,
  ontology_version text,
  schema_version text,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  matter_id uuid,
  court_case_id uuid
);

CREATE TABLE IF NOT EXISTS evidence.ingest_run (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid,
  source_sha256 bytea NOT NULL,
  source_filename text NOT NULL,
  source_bytes bigint,
  parser text NOT NULL,
  parser_version text NOT NULL,
  deriver_version text,
  raw_table text,
  runner text NOT NULL,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  finished_at timestamp with time zone,
  status text DEFAULT 'running'::text NOT NULL,
  outcome_detail text,
  count_claimed bigint,
  count_parsed bigint,
  count_rejected bigint,
  count_deduped bigint,
  count_raw bigint,
  count_spine bigint,
  count_attestations bigint,
  notes jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS evidence.source (
  id uuid DEFAULT uuidv7() NOT NULL,
  sha256 bytea NOT NULL,
  md5_prefilter bytea,
  byte_size bigint NOT NULL,
  mime_type text,
  original_filename text,
  source_type text NOT NULL,
  source_platform text,
  custodian text DEFAULT 'Matt Salem'::text NOT NULL,
  acquisition_source text NOT NULL,
  acquisition_method text,
  origin_device_id uuid,
  origin_account uuid,
  acquired_at_raw text,
  acquired_at_utc timestamp with time zone,
  acquired_tz_offset text,
  acquired_certainty precision_class DEFAULT 'exact'::precision_class NOT NULL,
  provenance_tier text DEFAULT 'r2_canonical'::text NOT NULL,
  r2_bucket text,
  r2_key text,
  local_path text,
  hash_canon_version text DEFAULT 'h1-rawbytes-v1'::text NOT NULL,
  sensitivity_tier sensitivity_tier DEFAULT 'restricted'::sensitivity_tier NOT NULL,
  legal_sensitivity text DEFAULT 'none'::text NOT NULL,
  privacy_sensitivity text DEFAULT 'none'::text NOT NULL,
  supersedes_source_id uuid,
  custody_status text DEFAULT 'collected'::text NOT NULL,
  extraction_status text DEFAULT 'pending'::text NOT NULL,
  processing_status text DEFAULT 'pending'::text NOT NULL,
  review_status text DEFAULT 'not_reviewed'::text NOT NULL,
  export_status text DEFAULT 'not_exported'::text NOT NULL,
  verified_by text,
  verified_at timestamp with time zone,
  original_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  derived_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL,
  acquisition_id uuid
);

CREATE TABLE IF NOT EXISTS ops.audit_ledger (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  ts timestamp with time zone DEFAULT now() NOT NULL,
  actor text NOT NULL,
  action_type text NOT NULL,
  object_schema text,
  object_ref text,
  horizon_context jsonb,
  base_version bigint,
  payload_hash text,
  prev_hash text,
  entry_hash text NOT NULL
);

CREATE TABLE IF NOT EXISTS ops.migration_ledger (
  migration_id text NOT NULL,
  filename text NOT NULL,
  ddl_sha256 bytea NOT NULL,
  applied_at timestamp with time zone DEFAULT now() NOT NULL,
  applied_by text NOT NULL,
  statements_ok integer,
  guards_skipped integer,
  notes text
);

CREATE TABLE IF NOT EXISTS ops.processing_run (
  run_id uuid DEFAULT uuidv7() NOT NULL,
  run_type text NOT NULL,
  run_purpose text,
  status text DEFAULT 'queued'::text NOT NULL,
  actor text NOT NULL,
  tool_or_model text,
  code_version text,
  prompt_version_id uuid,
  model_version_id uuid,
  schema_version_id uuid,
  ontology_version_id uuid,
  classification_version_id uuid,
  input_evidence_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  input_artifact_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  output_artifact_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  input_digest jsonb DEFAULT '[]'::jsonb NOT NULL,
  inputs_hash bytea,
  params jsonb DEFAULT '{}'::jsonb NOT NULL,
  ran_local_only boolean DEFAULT false NOT NULL,
  cloud_exposure boolean DEFAULT false NOT NULL,
  counts_processed integer,
  counts_failed integer,
  confidence_summary jsonb,
  human_review_requirement boolean DEFAULT false NOT NULL,
  replayable boolean DEFAULT false NOT NULL,
  error_message text,
  summary text,
  supersedes_run uuid,
  started_at timestamp with time zone,
  finished_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  code_ref text
);

CREATE TABLE IF NOT EXISTS ops.tool_call_ledger (
  tool_call_id uuid DEFAULT uuidv7() NOT NULL,
  run_id uuid,
  tool_name text NOT NULL,
  tool_category text NOT NULL,
  requested_by text,
  input_summary text,
  input_payload_uri text,
  input_hash bytea,
  output_summary text,
  output_payload_uri text,
  output_hash bytea,
  created_artifact_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  updated_record_refs jsonb DEFAULT '[]'::jsonb NOT NULL,
  runtime_ms integer,
  cost_estimate numeric(12,4),
  human_approval_status text DEFAULT 'n/a'::text NOT NULL,
  safety_flags jsonb DEFAULT '[]'::jsonb NOT NULL,
  replayability_status text DEFAULT 'replayable'::text NOT NULL,
  errors text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  prompt_version text
);

CREATE TABLE IF NOT EXISTS ops.workflow_run (
  run_id uuid DEFAULT uuidv7() NOT NULL,
  workflow text NOT NULL,
  mode text DEFAULT 'auto'::text NOT NULL,
  source_name text,
  source_path text,
  sha256 text,
  artifact_id text,
  domain text,
  status text DEFAULT 'running'::text NOT NULL,
  summary jsonb,
  error text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  gate_state text,
  parent_run_id uuid,
  custody_tier text DEFAULT 'full'::text NOT NULL,
  trace_id text,
  report_schema_version text DEFAULT '1.0'::text NOT NULL,
  source_context jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS ops.workflow_run_review_action (
  action_id uuid DEFAULT uuidv7() NOT NULL,
  run_id uuid NOT NULL,
  stage_seq integer,
  action_type text NOT NULL,
  actor text DEFAULT 'owner'::text NOT NULL,
  reason text NOT NULL,
  replacement jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS ops.workflow_run_stage (
  stage_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  run_id uuid NOT NULL,
  seq integer NOT NULL,
  name text NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  content text,
  output jsonb,
  started_at timestamp with time zone,
  finished_at timestamp with time zone,
  outcome_reason_code text,
  outcome_reason_detail text
);

CREATE TABLE IF NOT EXISTS public.app_setting (
  key text NOT NULL,
  value jsonb NOT NULL,
  value_type text DEFAULT 'json'::text NOT NULL,
  description text,
  updated_by text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.canon_registry (
  id uuid DEFAULT uuidv7() NOT NULL,
  canon_name text NOT NULL,
  family text NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  recipe text NOT NULL,
  reference_impl text,
  test_vectors jsonb DEFAULT '[]'::jsonb NOT NULL,
  notes text,
  established_at timestamp with time zone DEFAULT now() NOT NULL,
  superseded_by uuid
);

CREATE TABLE IF NOT EXISTS public.change_log (
  seq bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  change_id uuid DEFAULT uuidv7() NOT NULL,
  table_name text NOT NULL,
  record_id uuid,
  field_name text,
  action text NOT NULL,
  previous_value text,
  new_value text,
  actor text NOT NULL,
  change_origin text NOT NULL,
  reason text,
  related_run_id uuid,
  related_decision_id uuid,
  detail jsonb,
  prev_change_hash bytea,
  row_hash bytea NOT NULL,
  change_timestamp timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.classification_version (
  classification_version_id uuid DEFAULT uuidv7() NOT NULL,
  version_label text NOT NULL,
  scheme text NOT NULL,
  label_set jsonb DEFAULT '[]'::jsonb NOT NULL,
  source text NOT NULL,
  definition_uri text,
  definition_hash bytea,
  supersedes uuid,
  review_status text DEFAULT 'pending'::text NOT NULL,
  notes text,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.decision_log (
  decision_id uuid DEFAULT uuidv7() NOT NULL,
  decision_title text NOT NULL,
  decision_type text NOT NULL,
  context text,
  options_considered jsonb DEFAULT '[]'::jsonb NOT NULL,
  decision_made text NOT NULL,
  reasoning_summary text,
  evidence_or_artifacts_considered jsonb DEFAULT '[]'::jsonb NOT NULL,
  owner text NOT NULL,
  reversibility text,
  related_risks text,
  related_open_questions uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  supersedes uuid,
  review_status text DEFAULT 'none'::text NOT NULL,
  decided_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.decision_precedent (
  precedent_id uuid DEFAULT uuidv7() NOT NULL,
  decision_id uuid NOT NULL,
  source_decision_id uuid NOT NULL,
  similarity_score ai.confidence,
  relationship_type text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.memory_items (
  memory_id uuid DEFAULT uuidv7() NOT NULL,
  memory_type text NOT NULL,
  title text NOT NULL,
  summary text,
  content_inline text,
  content_uri text,
  content_hash bytea,
  source_of_memory text,
  created_by text NOT NULL,
  confidence ai.confidence,
  assertion_type assertion_type,
  status text DEFAULT 'active'::text NOT NULL,
  review_status text DEFAULT 'none'::text NOT NULL,
  is_sensitive boolean DEFAULT false NOT NULL,
  mirror_store ai.source_system,
  superseded_by uuid,
  related_artifact_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  related_evidence_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  related_ontology_id uuid,
  related_schema_id uuid,
  tags jsonb DEFAULT '[]'::jsonb NOT NULL,
  fts tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((COALESCE(title, ''::text) || ' '::text) || COALESCE(summary, ''::text)))) STORED,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.model_version (
  model_version_id uuid DEFAULT uuidv7() NOT NULL,
  provider text,
  model_id text NOT NULL,
  role text NOT NULL,
  version text,
  dims integer,
  ran_local_capable boolean DEFAULT false NOT NULL,
  params jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ontology_version (
  ontology_version_id uuid DEFAULT uuidv7() NOT NULL,
  version_label text NOT NULL,
  source text NOT NULL,
  definition_uri text,
  definition_hash bytea,
  node_types jsonb DEFAULT '[]'::jsonb NOT NULL,
  edge_types jsonb DEFAULT '[]'::jsonb NOT NULL,
  supersedes uuid,
  review_status text DEFAULT 'pending'::text NOT NULL,
  notes text,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.open_questions (
  question_id uuid DEFAULT uuidv7() NOT NULL,
  question_text text NOT NULL,
  category text NOT NULL,
  raised_by text,
  status text DEFAULT 'open'::text NOT NULL,
  answer_summary text,
  answered_by text,
  answered_at timestamp with time zone,
  related_run_id uuid,
  related_artifact_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  blocks_export boolean DEFAULT false NOT NULL,
  requires_corroboration boolean DEFAULT false NOT NULL,
  priority integer DEFAULT 3 NOT NULL,
  raised_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.platform_consolidation_receipt_claim (
  receipt_id uuid NOT NULL,
  claim_kind text NOT NULL,
  checkpoint_id uuid,
  successor_receipt_id uuid,
  claimed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.prompt_registry (
  prompt_id uuid DEFAULT uuidv7() NOT NULL,
  prompt_name text NOT NULL,
  prompt_version text NOT NULL,
  prompt_type text NOT NULL,
  full_prompt_text text NOT NULL,
  body_sha256 bytea NOT NULL,
  purpose text,
  inputs_expected text,
  outputs_expected text,
  known_limitations text,
  safety_constraints text,
  human_approval_required boolean DEFAULT false NOT NULL,
  superseded_by uuid,
  status text DEFAULT 'active'::text NOT NULL,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.schema_version (
  schema_version_id uuid DEFAULT uuidv7() NOT NULL,
  version_label text NOT NULL,
  applies_to text NOT NULL,
  ddl_uri text,
  ddl_hash bytea,
  migration_id text,
  supersedes uuid,
  status text DEFAULT 'active'::text NOT NULL,
  notes text,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.session_summaries (
  session_id uuid DEFAULT uuidv7() NOT NULL,
  session_start timestamp with time zone NOT NULL,
  session_end timestamp with time zone,
  user_goal text,
  work_completed text,
  files_inspected jsonb DEFAULT '[]'::jsonb NOT NULL,
  artifacts_created jsonb DEFAULT '[]'::jsonb NOT NULL,
  decisions_made uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  open_questions uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  next_actions text,
  blockers text,
  tone_preference_notes text,
  important_warnings text,
  related_run_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  fts tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((COALESCE(user_goal, ''::text) || ' '::text) || COALESCE(work_completed, ''::text)))) STORED,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.spatial_ref_sys (
  srid integer NOT NULL,
  auth_name character varying(256),
  auth_srid integer,
  srtext character varying(2048),
  proj4text character varying(2048)
);

CREATE TABLE IF NOT EXISTS public.transcript_insight (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_file text NOT NULL,
  platform text,
  insight_type text NOT NULL,
  content text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  mined_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.file_node (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  parent_node_id uuid,
  node_kind text NOT NULL,
  node_path ltree,
  ordinal integer,
  sha256 bytea,
  byte_span_start bigint,
  byte_span_end bigint,
  locator jsonb DEFAULT '{}'::jsonb NOT NULL,
  mime_type text,
  extraction_confidence ai.confidence,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.gps_point (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  file_node_id uuid,
  device_id uuid,
  geog ai.geo_point NOT NULL,
  captured_at timestamp with time zone,
  captured_raw text,
  ts_precision precision_class DEFAULT 'exact'::precision_class NOT NULL,
  accuracy_m numeric(8,2),
  point_sequence bigint,
  ingest_run_id uuid,
  raw_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  data_tier evidence_tier DEFAULT 'raw'::evidence_tier NOT NULL,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.raw_activity (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  file_node_id uuid,
  event_serial bigint,
  start_raw text,
  end_raw text,
  start_utc timestamp with time zone,
  end_utc timestamp with time zone,
  tz_offset_min integer,
  duration_s bigint,
  activity_type text,
  activity_probability ai.confidence,
  distance_m numeric(12,2),
  start_geog ai.geo_point,
  end_geog ai.geo_point,
  place_id_start text,
  place_id_end text,
  parent_id uuid,
  memory_id uuid,
  ingest_run_id uuid,
  raw_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  data_tier evidence_tier DEFAULT 'raw'::evidence_tier NOT NULL,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.raw_ai_chat (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  device_id uuid,
  acquisition_id uuid,
  medium evidence.record_medium DEFAULT 'export'::evidence.record_medium NOT NULL,
  record_index integer,
  raw jsonb NOT NULL,
  raw_text text,
  content_hash text NOT NULL,
  content_canon text DEFAULT 'h2-rawelement-v1'::text NOT NULL,
  parser_version text,
  superseded_by uuid,
  supersede_note text,
  ingest_run_id uuid,
  deriver_version text,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.raw_csv (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  device_id uuid,
  acquisition_id uuid,
  medium evidence.record_medium DEFAULT 'export'::evidence.record_medium NOT NULL,
  record_index integer,
  raw jsonb NOT NULL,
  raw_text text,
  content_hash text NOT NULL,
  content_canon text DEFAULT 'h2-rawelement-v1'::text NOT NULL,
  parser_version text,
  superseded_by uuid,
  supersede_note text,
  ingest_run_id uuid,
  deriver_version text,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.raw_facebook (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  device_id uuid,
  acquisition_id uuid,
  medium evidence.record_medium DEFAULT 'export'::evidence.record_medium NOT NULL,
  record_index integer,
  raw jsonb NOT NULL,
  raw_text text,
  content_hash text NOT NULL,
  content_canon text DEFAULT 'h2-rawelement-v1'::text NOT NULL,
  parser_version text,
  superseded_by uuid,
  supersede_note text,
  ingest_run_id uuid,
  deriver_version text,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.raw_imessage (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  device_id uuid,
  acquisition_id uuid,
  medium evidence.record_medium DEFAULT 'export'::evidence.record_medium NOT NULL,
  record_index integer,
  raw jsonb NOT NULL,
  raw_text text,
  content_hash text NOT NULL,
  content_canon text DEFAULT 'h2-rawelement-v1'::text NOT NULL,
  parser_version text,
  superseded_by uuid,
  supersede_note text,
  ingest_run_id uuid,
  deriver_version text,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.raw_path (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  file_node_id uuid,
  path_serial bigint,
  point_sequence bigint NOT NULL,
  point_geog ai.geo_point NOT NULL,
  point_ts_raw text,
  point_ts_utc timestamp with time zone,
  tz_offset_min integer,
  aligned_activity_id uuid,
  parent_id uuid,
  ingest_run_id uuid,
  raw_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  data_tier evidence_tier DEFAULT 'raw'::evidence_tier NOT NULL,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.raw_phone (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  device_id uuid,
  acquisition_id uuid,
  medium evidence.record_medium DEFAULT 'export'::evidence.record_medium NOT NULL,
  record_index integer,
  raw jsonb NOT NULL,
  raw_text text,
  content_hash text NOT NULL,
  content_canon text DEFAULT 'h2-rawelement-v1'::text NOT NULL,
  parser_version text,
  superseded_by uuid,
  supersede_note text,
  ingest_run_id uuid,
  deriver_version text,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.raw_rejected (
  id uuid DEFAULT uuidv7() NOT NULL,
  ingest_run_id uuid NOT NULL,
  source_sha256 bytea NOT NULL,
  record_index bigint,
  element_tag text,
  reason text NOT NULL,
  reason_detail text,
  content_hash text,
  raw jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.raw_sms (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  device_id uuid,
  acquisition_id uuid,
  medium evidence.record_medium DEFAULT 'export'::evidence.record_medium NOT NULL,
  record_index integer,
  raw jsonb NOT NULL,
  raw_text text,
  content_hash text NOT NULL,
  content_canon text DEFAULT 'h2-rawelement-v1'::text NOT NULL,
  parser_version text,
  superseded_by uuid,
  supersede_note text,
  ingest_run_id uuid,
  deriver_version text,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.raw_trip (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  file_node_id uuid,
  event_serial bigint,
  start_raw text,
  end_raw text,
  start_utc timestamp with time zone,
  end_utc timestamp with time zone,
  tz_offset_min integer,
  duration_s bigint,
  distance_from_origin_km numeric(12,3),
  destination_place_ids text[],
  parent_id uuid,
  ingest_run_id uuid,
  raw_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  data_tier evidence_tier DEFAULT 'raw'::evidence_tier NOT NULL,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.raw_visit (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_id uuid NOT NULL,
  file_node_id uuid,
  event_serial bigint,
  hierarchy_level integer,
  start_raw text,
  end_raw text,
  start_utc timestamp with time zone,
  end_utc timestamp with time zone,
  tz_offset_min integer,
  duration_s bigint,
  detection_probability ai.confidence,
  semantic_type text,
  semantic_probability ai.confidence,
  place_id text,
  geog ai.geo_point,
  parent_id uuid,
  memory_id uuid,
  ingest_run_id uuid,
  raw_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  data_tier evidence_tier DEFAULT 'raw'::evidence_tier NOT NULL,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS reference.behavior_category (
  category_id citext NOT NULL,
  label text NOT NULL,
  description text,
  polarity category_polarity NOT NULL,
  default_severity smallint DEFAULT 5 NOT NULL,
  mcl_factors ai.mcl_factor[] DEFAULT '{}'::ai.mcl_factor[] NOT NULL,
  aliases citext[] DEFAULT '{}'::citext[] NOT NULL,
  is_case_specific boolean DEFAULT false NOT NULL,
  source text,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  is_enabled boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS reference.behavior_category_mcl (
  category_id citext NOT NULL,
  factor_code ai.mcl_factor NOT NULL,
  weight text,
  is_critical boolean DEFAULT false NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS reference.claim_type (
  slug text NOT NULL,
  label text NOT NULL,
  description text NOT NULL,
  parent_slug text,
  retired_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS reference.custody_factor (
  factor ai.mcl_factor NOT NULL,
  code_display text NOT NULL,
  name text NOT NULL,
  statutory_text text,
  is_key_factor boolean DEFAULT false NOT NULL,
  notes text
);

CREATE TABLE IF NOT EXISTS reference.detection_pattern (
  id uuid DEFAULT uuidv7() NOT NULL,
  pattern_set_id uuid NOT NULL,
  category_id citext NOT NULL,
  subcategory text,
  match_type pattern_match_type NOT NULL,
  pattern text NOT NULL,
  keywords text[] DEFAULT '{}'::text[] NOT NULL,
  severity smallint DEFAULT 5 NOT NULL,
  score smallint,
  mcl_factors ai.mcl_factor[] DEFAULT '{}'::ai.mcl_factor[] NOT NULL,
  description text,
  is_case_specific boolean DEFAULT false NOT NULL,
  authored_perspective text,
  bias_caution boolean DEFAULT true NOT NULL,
  source text,
  is_active boolean DEFAULT true NOT NULL,
  valid_from timestamp with time zone DEFAULT now() NOT NULL,
  valid_to timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS reference.detection_pattern_set (
  id uuid DEFAULT uuidv7() NOT NULL,
  name citext NOT NULL,
  version text NOT NULL,
  source text,
  source_artifact text,
  description text,
  is_active boolean DEFAULT false NOT NULL,
  authored_perspective text,
  valid_from timestamp with time zone DEFAULT now() NOT NULL,
  valid_to timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  provenance_id uuid
);

CREATE TABLE IF NOT EXISTS reference.format_resolver (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_signature text NOT NULL,
  source_label text,
  source_fields jsonb NOT NULL,
  mappings jsonb NOT NULL,
  target_schema text DEFAULT 'analysis.message'::text NOT NULL,
  ai_model text,
  used_count integer DEFAULT 0 NOT NULL,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  created_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS reference.knowledge_tag (
  id uuid DEFAULT uuidv7() NOT NULL,
  slug text NOT NULL,
  label text NOT NULL,
  description text,
  parent_tag_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS reference.legal_issue (
  id uuid DEFAULT uuidv7() NOT NULL,
  case_id uuid NOT NULL,
  issue_key text NOT NULL,
  title text NOT NULL,
  description text,
  issue_type text DEFAULT 'custody'::text NOT NULL,
  statutory_basis text,
  weight ai.confidence,
  weight_basis text,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS reference.legal_issue_factor (
  legal_issue_id uuid NOT NULL,
  factor ai.mcl_factor NOT NULL,
  element_note text
);

CREATE TABLE IF NOT EXISTS reference.lexicon_sync (
  id uuid DEFAULT uuidv7() NOT NULL,
  lexicon text NOT NULL,
  language text DEFAULT 'en'::text NOT NULL,
  version text,
  level text,
  source_url text,
  source_commit text,
  status text DEFAULT 'pending'::text NOT NULL,
  term_count integer,
  error_message text,
  pattern_set_id uuid,
  last_sync_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS reference.pattern_lexicon (
  id uuid DEFAULT uuidv7() NOT NULL,
  pattern_set_id uuid NOT NULL,
  lexicon_type text NOT NULL,
  term text NOT NULL,
  variants text[] DEFAULT '{}'::text[] NOT NULL,
  match_type pattern_match_type DEFAULT 'literal'::pattern_match_type NOT NULL,
  relevance_signal text,
  severity smallint DEFAULT 0 NOT NULL,
  mcl_factors ai.mcl_factor[] DEFAULT '{}'::ai.mcl_factor[] NOT NULL,
  is_case_specific boolean DEFAULT true NOT NULL,
  sensitivity_tier sensitivity_tier DEFAULT 'restricted'::sensitivity_tier NOT NULL,
  source text,
  is_active boolean DEFAULT true NOT NULL,
  valid_from timestamp with time zone DEFAULT now() NOT NULL,
  valid_to timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS reference.relative_rule (
  rule_id uuid DEFAULT uuidv7() NOT NULL,
  phrase_pattern text NOT NULL,
  resolution_expr text NOT NULL,
  result_certainty precision_class NOT NULL,
  lower_offset interval,
  upper_offset interval,
  config jsonb DEFAULT '{}'::jsonb NOT NULL,
  ontology_version text,
  prompt_version text,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS reference.score_band_config (
  config_version text NOT NULL,
  bands jsonb NOT NULL,
  effective_from timestamp with time zone DEFAULT now() NOT NULL,
  changed_by text NOT NULL,
  rationale text NOT NULL
);

CREATE TABLE IF NOT EXISTS reference.topic_code (
  code character varying(6) NOT NULL,
  label text NOT NULL,
  keywords text[] DEFAULT '{}'::text[] NOT NULL,
  mcl_factors ai.mcl_factor[],
  is_case_specific boolean DEFAULT false NOT NULL,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS registry.court_case (
  id uuid DEFAULT uuidv7() NOT NULL,
  matter_id uuid NOT NULL,
  caption text NOT NULL,
  docket_number text,
  court_name text,
  jurisdiction text,
  case_type text,
  status text DEFAULT 'pre_filing'::text NOT NULL,
  filed_on date,
  closed_on date,
  is_primary boolean DEFAULT false NOT NULL,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  verification_state text DEFAULT 'proposed'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS registry.device (
  id uuid NOT NULL,
  make_model text,
  os text,
  imei_or_serial citext,
  owner_entity_id uuid,
  device_label text,
  acquired_note text,
  verification_state text DEFAULT 'proposed'::text NOT NULL,
  identification_confidence ai.confidence,
  identification_signal text
);

CREATE TABLE IF NOT EXISTS registry.entity (
  id uuid DEFAULT uuidv7() NOT NULL,
  entity_type ai.entity_type NOT NULL,
  display_name citext,
  canonical_name citext,
  normalized_name citext,
  sensitivity_tier sensitivity_tier,
  is_party boolean DEFAULT false NOT NULL,
  data_tier evidence_tier DEFAULT 'inferred'::evidence_tier NOT NULL,
  evidence_confidence ai.confidence,
  provenance ai.source_ref[] DEFAULT '{}'::ai.source_ref[] NOT NULL,
  requires_human_review boolean DEFAULT false NOT NULL,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  safe_for_legal_use boolean DEFAULT false NOT NULL,
  merged_into_id uuid,
  first_seen_at timestamp with time zone,
  last_seen_at timestamp with time zone,
  sys_period tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone) NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS registry.entity_alias (
  id uuid DEFAULT uuidv7() NOT NULL,
  entity_id uuid NOT NULL,
  alias_text citext NOT NULL,
  alias_kind text,
  confidence ai.confidence,
  alias_dmeta text GENERATED ALWAYS AS (dmetaphone((alias_text)::text)) STORED,
  provenance ai.source_ref[] DEFAULT '{}'::ai.source_ref[] NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS registry.id_xref (
  id uuid DEFAULT uuidv7() NOT NULL,
  canonical_entity_id uuid,
  system_a ai.source_system NOT NULL,
  native_id_a text NOT NULL,
  system_b ai.source_system NOT NULL,
  native_id_b text NOT NULL,
  match_method ai.match_method NOT NULL,
  confidence ai.confidence,
  source ai.source_ref,
  is_current boolean DEFAULT true NOT NULL,
  sys_period tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone) NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS registry.location (
  id uuid DEFAULT uuidv7() NOT NULL,
  name text,
  geog ai.geo_point NOT NULL,
  geohash9 text GENERATED ALWAYS AS (st_geohash((geog)::geometry, 9)) STORED,
  address text,
  place_type text,
  is_fuzzed boolean DEFAULT false NOT NULL,
  sensitivity_tier sensitivity_tier DEFAULT 'restricted'::sensitivity_tier NOT NULL,
  spatial_confidence ai.confidence,
  data_tier evidence_tier DEFAULT 'extracted'::evidence_tier NOT NULL,
  provenance_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  verification_state text DEFAULT 'proposed'::text NOT NULL,
  identification_confidence ai.confidence,
  identification_signal text
);

CREATE TABLE IF NOT EXISTS registry.matter (
  id uuid DEFAULT uuidv7() NOT NULL,
  title text NOT NULL,
  description text,
  status text DEFAULT 'active'::text NOT NULL,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  verification_state text DEFAULT 'proposed'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS registry.person (
  id uuid NOT NULL,
  relationship_type text,
  connection_to text,
  role_in_case text,
  gender text,
  is_minor boolean DEFAULT false NOT NULL,
  is_flagged boolean DEFAULT false NOT NULL,
  notes text,
  verification_state text DEFAULT 'proposed'::text NOT NULL,
  identification_confidence ai.confidence,
  identification_signal text
);

CREATE TABLE IF NOT EXISTS timeline.event_candidate (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  source_system text NOT NULL,
  source_record_id text NOT NULL,
  source_record_version text,
  source_locator jsonb DEFAULT '{}'::jsonb NOT NULL,
  extraction_run_id text,
  temporal_precision text NOT NULL,
  occurred_at timestamp with time zone,
  valid_from timestamp with time zone,
  valid_to timestamp with time zone,
  temporal_confidence real,
  display_summary text NOT NULL,
  event_type text NOT NULL,
  entity_refs text[] DEFAULT '{}'::text[] NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS timeline.event_candidate_relative_time_anchor (
  event_candidate_id uuid NOT NULL,
  anchor_id uuid NOT NULL,
  anchor_role text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS timeline.event_candidate_source_range (
  id uuid DEFAULT uuidv7() NOT NULL,
  event_candidate_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  source_range_locator_id uuid NOT NULL,
  member_ordinal bigint NOT NULL,
  extractor_id text NOT NULL,
  extractor_version text NOT NULL,
  schema_manifest_digest bytea NOT NULL,
  extraction_activity_receipt_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS timeline.timeline_collection (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  slug text NOT NULL,
  title text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS timeline.timeline_member (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  collection_id uuid NOT NULL,
  member_authority text NOT NULL,
  candidate_id uuid,
  governed_source_schema text,
  governed_source_table text,
  governed_source_pk text,
  governed_source_version text,
  display_order numeric,
  group_label text,
  included boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS timeline.timeline_projection_activation (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  generation_id uuid NOT NULL,
  activated_by text NOT NULL,
  note text,
  activated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS timeline.timeline_projection_generation (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  sequence bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  collection_id uuid NOT NULL,
  status text DEFAULT 'sealed'::text NOT NULL,
  policy_version text DEFAULT 'adr-0060-timesketch-mapping-v1'::text NOT NULL,
  member_count integer NOT NULL,
  membership_hash text NOT NULL,
  content_hash text NOT NULL,
  idempotency_key text NOT NULL,
  since_generation_id uuid,
  superseded_by uuid,
  created_by text DEFAULT 'timeline_projector'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS timeline.timeline_projection_member (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  generation_id uuid NOT NULL,
  source_member_id uuid NOT NULL,
  stable_member_id text NOT NULL,
  opensearch_doc_id text NOT NULL,
  authority_state text NOT NULL,
  amends_stable_member_id text,
  display_at_utc timestamp with time zone NOT NULL,
  display_summary text NOT NULL,
  event_type text NOT NULL,
  temporal_precision text NOT NULL,
  occurred_at timestamp with time zone,
  valid_from timestamp with time zone,
  valid_to timestamp with time zone,
  temporal_confidence real,
  source_available_from timestamp with time zone NOT NULL,
  entity_refs text[] DEFAULT '{}'::text[] NOT NULL,
  verification_state text DEFAULT 'unverified'::text NOT NULL,
  privacy_level text,
  privileged boolean DEFAULT false NOT NULL,
  source_system text NOT NULL,
  source_record_id text NOT NULL,
  source_record_version text,
  core_content_hash text NOT NULL,
  annotation_content_hash text NOT NULL,
  change_class text DEFAULT 'core'::text NOT NULL,
  member_content_hash text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS timeline.timeline_projection_receipt (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  generation_id uuid NOT NULL,
  member_id uuid,
  sink text DEFAULT 'timesketch_opensearch'::text NOT NULL,
  idempotency_key text NOT NULL,
  status text NOT NULL,
  attempt integer DEFAULT 1 NOT NULL,
  expected_content_hash text,
  observed_content_hash text,
  opensearch_doc_id text,
  opensearch_index text,
  error_code text,
  error_digest text,
  started_at timestamp with time zone,
  finished_at timestamp with time zone,
  observed_at timestamp with time zone,
  previous_receipt_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.account (
  id uuid NOT NULL,
  platform text NOT NULL,
  account_key citext NOT NULL,
  owner_entity_id uuid
);

CREATE TABLE IF NOT EXISTS working.artifact_registry (
  artifact_id uuid DEFAULT uuidv7() NOT NULL,
  artifact_kind text NOT NULL,
  title text,
  format text,
  sha256 bytea NOT NULL,
  path_or_uri text,
  byte_size bigint,
  content_inline text,
  assertion_type assertion_type NOT NULL,
  confidence ai.confidence,
  evidence_strength strength_class,
  timestamp_certainty precision_class,
  is_sensitive boolean DEFAULT false NOT NULL,
  sensitivity_tier sensitivity_tier,
  producing_run uuid,
  parent_artifact_id uuid,
  derived_from_artifact_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  related_source_evidence uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  superseded_by uuid,
  archive_reason text,
  summary_md text,
  metadata_json jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.attachment (
  id uuid DEFAULT uuidv7() NOT NULL,
  message_id uuid NOT NULL,
  source_artifact_id uuid,
  media_asset_id uuid,
  filename text,
  attachment_type text,
  mime_type text,
  file_sha256 bytea,
  file_size bigint,
  object_uri text,
  thumbnail_uri text,
  width integer,
  height integer,
  duration_s numeric,
  is_screenshot boolean DEFAULT false NOT NULL,
  contains_faces boolean DEFAULT false NOT NULL,
  ocr_text text,
  transcription text,
  exif jsonb,
  ocr_confidence ai.confidence,
  embedding_ref text,
  data_tier evidence_tier DEFAULT 'extracted'::evidence_tier NOT NULL,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  platform_attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  raw_data jsonb,
  provenance_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.call_log (
  id uuid NOT NULL,
  source_artifact_id uuid NOT NULL,
  conversation_id uuid,
  from_raw text,
  from_e164 text,
  from_entity_id uuid,
  to_raw text,
  to_e164 text,
  to_entity_id uuid,
  call_type text NOT NULL,
  direction text,
  started_at timestamp with time zone,
  ts_precision precision_class DEFAULT 'exact'::precision_class NOT NULL,
  duration_s integer,
  is_blocked boolean DEFAULT false NOT NULL,
  presentation text,
  data_tier evidence_tier DEFAULT 'extracted'::evidence_tier NOT NULL,
  platform_attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  raw_data jsonb,
  provenance_id uuid
);

CREATE TABLE IF NOT EXISTS working.candidate_entity (
  id uuid DEFAULT uuidv7() NOT NULL,
  extraction_run_id uuid NOT NULL,
  source_raw_table text NOT NULL,
  source_raw_id text NOT NULL,
  entity_type text NOT NULL,
  name text NOT NULL,
  normalized_name text NOT NULL,
  confidence double precision,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  content_sha256 bytea NOT NULL,
  review_state text DEFAULT 'pending'::text NOT NULL,
  promoted_to_table text,
  promoted_to_id text,
  promoted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  case_id text DEFAULT 'primary'::text NOT NULL,
  domain text DEFAULT 'evidence'::text NOT NULL,
  topic_tags text[] DEFAULT '{}'::text[] NOT NULL,
  knowledge_actor text DEFAULT 'owner'::text NOT NULL,
  ontology_version text,
  knowledge_time timestamp with time zone,
  graph_lane analysis.graph_lane
);

CREATE TABLE IF NOT EXISTS working.candidate_event (
  id uuid DEFAULT uuidv7() NOT NULL,
  extraction_run_id uuid NOT NULL,
  source_raw_table text NOT NULL,
  source_raw_id text NOT NULL,
  event_type text NOT NULL,
  summary text NOT NULL,
  occurred_at timestamp with time zone,
  validity tstzrange,
  temporal_confidence double precision,
  primary_entity_id uuid,
  confidence double precision,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  content_sha256 bytea NOT NULL,
  review_state text DEFAULT 'pending'::text NOT NULL,
  promoted_to_table text,
  promoted_to_id text,
  promoted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  case_id text DEFAULT 'primary'::text NOT NULL,
  domain text DEFAULT 'evidence'::text NOT NULL,
  topic_tags text[] DEFAULT '{}'::text[] NOT NULL,
  knowledge_actor text DEFAULT 'owner'::text NOT NULL,
  ontology_version text,
  knowledge_time timestamp with time zone,
  graph_lane analysis.graph_lane
);

CREATE TABLE IF NOT EXISTS working.candidate_fact (
  id uuid DEFAULT uuidv7() NOT NULL,
  extraction_run_id uuid NOT NULL,
  source_raw_table text NOT NULL,
  source_raw_id text NOT NULL,
  subject_entity_id uuid,
  object_entity_id uuid,
  predicate text NOT NULL,
  statement text NOT NULL,
  evidence_quote text,
  confidence double precision,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  content_sha256 bytea NOT NULL,
  review_state text DEFAULT 'pending'::text NOT NULL,
  promoted_to_table text,
  promoted_to_id text,
  promoted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  case_id text DEFAULT 'primary'::text NOT NULL,
  domain text DEFAULT 'evidence'::text NOT NULL,
  topic_tags text[] DEFAULT '{}'::text[] NOT NULL,
  knowledge_actor text DEFAULT 'owner'::text NOT NULL,
  ontology_version text,
  knowledge_time timestamp with time zone,
  graph_lane analysis.graph_lane
);

CREATE TABLE IF NOT EXISTS working.chat_conversation (
  id uuid DEFAULT uuidv7() NOT NULL,
  source text NOT NULL,
  external_id text NOT NULL,
  title text,
  source_path text,
  created_at timestamp with time zone,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS working.chat_message (
  id uuid DEFAULT uuidv7() NOT NULL,
  conversation_id uuid NOT NULL,
  message_index integer NOT NULL,
  role text NOT NULL,
  content text DEFAULT ''::text NOT NULL,
  sent_at timestamp with time zone,
  thinking text,
  attachments jsonb DEFAULT '[]'::jsonb NOT NULL,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  content_hash text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.claim_candidate (
  id uuid DEFAULT uuidv7() NOT NULL,
  extraction_run_id uuid NOT NULL,
  window_id uuid NOT NULL,
  chat_conversation_id uuid NOT NULL,
  chat_message_id uuid NOT NULL,
  chat_chunk_id uuid,
  message_ordinal bigint NOT NULL,
  span_start integer,
  span_end integer,
  speaker_role text NOT NULL,
  claim_class text NOT NULL,
  claim_type_slug text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  verbatim text NOT NULL,
  hedged boolean NOT NULL,
  hedge_terms text[] DEFAULT '{}'::text[] NOT NULL,
  date_raw text,
  relative_time_anchor_id uuid,
  participant_codes text[] DEFAULT '{}'::text[] NOT NULL,
  fingerprint text NOT NULL,
  content_sha256 bytea NOT NULL,
  extractor text NOT NULL,
  extractor_version text NOT NULL,
  model_id text,
  confidence double precision,
  review_state text DEFAULT 'pending'::text NOT NULL,
  reviewed_by text,
  reviewed_at timestamp with time zone,
  review_note text,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  graph_lane analysis.graph_lane,
  prompt_version text,
  source_generation bigint,
  projected_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS working.claim_temporal_edge (
  id uuid DEFAULT uuidv7() NOT NULL,
  extraction_run_id uuid NOT NULL,
  from_claim_id uuid NOT NULL,
  relation text NOT NULL,
  target_kind text NOT NULL,
  to_claim_id uuid,
  target_phrase text,
  resolved_claim_id uuid,
  resolved_by text,
  resolved_at timestamp with time zone,
  offset_raw text,
  offset_interval interval,
  as_stated_verbatim text NOT NULL,
  hedged boolean DEFAULT false NOT NULL,
  confidence double precision,
  review_state text DEFAULT 'pending'::text NOT NULL,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  graph_lane analysis.graph_lane
);

CREATE TABLE IF NOT EXISTS working.content_chunk (
  id uuid DEFAULT uuidv7() NOT NULL,
  generation_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  chunk_index bigint NOT NULL,
  content text NOT NULL,
  content_sha256 bytea NOT NULL,
  derivation_mode text NOT NULL,
  token_count bigint,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.content_chunk_generation (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_version_id uuid NOT NULL,
  normalized_generation_id uuid,
  generation_ordinal integer NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  completeness_scope text DEFAULT 'complete'::text NOT NULL,
  requires_verbatim_reassembly boolean DEFAULT true NOT NULL,
  policy_id text NOT NULL,
  policy_version text NOT NULL,
  chunker_id text NOT NULL,
  chunker_version text NOT NULL,
  config_digest bytea NOT NULL,
  schema_version text NOT NULL,
  implementation_digest bytea NOT NULL,
  source_view text NOT NULL,
  source_canonicalization text NOT NULL,
  source_sha256 bytea NOT NULL,
  source_byte_length bigint NOT NULL,
  source_codepoint_length bigint,
  chunk_count bigint,
  member_count bigint,
  manifest_sha256 bytea,
  activity_execution_id uuid NOT NULL,
  activity_receipt_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  sealed_at timestamp with time zone,
  sealed_by text,
  aborted_at timestamp with time zone,
  abort_reason text
);

CREATE TABLE IF NOT EXISTS working.content_chunk_projection (
  id uuid DEFAULT uuidv7() NOT NULL,
  chunk_id uuid NOT NULL,
  sink text NOT NULL,
  embedder_id text,
  projection_ref text,
  source_generation bigint,
  status text DEFAULT 'pending'::text NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  last_error text,
  projected_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.content_chunk_reassembly_receipt (
  id uuid DEFAULT uuidv7() NOT NULL,
  generation_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  source_sha256 bytea NOT NULL,
  reassembled_sha256 bytea NOT NULL,
  source_byte_length bigint NOT NULL,
  reassembled_byte_length bigint NOT NULL,
  covered_range_start bigint DEFAULT 0 NOT NULL,
  covered_range_end bigint NOT NULL,
  gap_count bigint NOT NULL,
  overlap_count bigint NOT NULL,
  chunk_count bigint NOT NULL,
  member_count bigint NOT NULL,
  verification_result text NOT NULL,
  verifier_id text NOT NULL,
  verifier_version text NOT NULL,
  activity_receipt_id uuid NOT NULL,
  verified_at timestamp with time zone NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.content_chunk_source_span (
  id uuid DEFAULT uuidv7() NOT NULL,
  chunk_id uuid NOT NULL,
  generation_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  member_ordinal bigint NOT NULL,
  source_range_locator_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.context_archive (
  id uuid DEFAULT uuidv7() NOT NULL,
  archive_path text NOT NULL,
  archive_sha256 text NOT NULL,
  provider text,
  conversation_log_count integer DEFAULT 0 NOT NULL,
  asset_count integer DEFAULT 0 NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  manifest jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.context_asset (
  id uuid DEFAULT uuidv7() NOT NULL,
  archive_id uuid,
  member_path text NOT NULL,
  asset_category text NOT NULL,
  file_ext text,
  content_hash text NOT NULL,
  byte_size bigint,
  r2_bucket text,
  r2_key text,
  content_inline text,
  conversation_id text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  origin_kind text DEFAULT 'export_asset'::text NOT NULL,
  media_type text,
  modality text DEFAULT 'binary'::text NOT NULL,
  extracted_text text,
  extraction_tool_id text,
  extraction_confidence double precision,
  extraction_status text DEFAULT 'pending'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS working.context_asset_derivation (
  parent_asset_id uuid NOT NULL,
  child_asset_id uuid NOT NULL,
  derivation_type text NOT NULL,
  tool_id text NOT NULL,
  tool_version text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS working.context_asset_message (
  asset_id uuid NOT NULL,
  message_id uuid NOT NULL,
  relationship text DEFAULT 'referenced'::text NOT NULL,
  linked_at timestamp with time zone DEFAULT now() NOT NULL,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS working.context_record (
  id uuid DEFAULT uuidv7() NOT NULL,
  record_type text DEFAULT 'message'::text NOT NULL,
  source text NOT NULL,
  conversation_id text,
  conversation_title text,
  role text,
  participants jsonb DEFAULT '[]'::jsonb NOT NULL,
  content text DEFAULT ''::text NOT NULL,
  occurred_at timestamp with time zone,
  knowledge_time timestamp with time zone DEFAULT now() NOT NULL,
  lane text DEFAULT 'context'::text NOT NULL,
  content_hash text NOT NULL,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  weaviate_synced_at timestamp with time zone,
  graphiti_synced_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS working.email (
  id uuid NOT NULL,
  address citext,
  owner_entity_id uuid,
  validity tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone) NOT NULL
);

CREATE TABLE IF NOT EXISTS working.entity_mention (
  id uuid DEFAULT uuidv7() NOT NULL,
  surface_text citext NOT NULL,
  surface_norm text GENERATED ALWAYS AS (lower((surface_text)::text)) STORED,
  mention_kind text,
  subject_type text,
  subject_id uuid,
  start_char integer,
  end_char integer,
  context_snippet text,
  extraction_method text,
  confidence ai.confidence,
  mention_dmeta text GENERATED ALWAYS AS (dmetaphone((surface_text)::text)) STORED,
  data_tier evidence_tier DEFAULT 'extracted'::evidence_tier NOT NULL,
  provenance ai.source_ref[] DEFAULT '{}'::ai.source_ref[] NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.entity_resolution (
  id uuid DEFAULT uuidv7() NOT NULL,
  mention_id uuid NOT NULL,
  canonical_entity_id uuid NOT NULL,
  source_specific_id text,
  match_method ai.match_method NOT NULL,
  resolved_by text,
  match_score ai.confidence,
  similarity_metrics jsonb DEFAULT '{}'::jsonb NOT NULL,
  requires_human_review boolean DEFAULT true NOT NULL,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  reviewed_by text,
  reviewed_at timestamp with time zone,
  review_notes text,
  safe_for_legal_use boolean DEFAULT false NOT NULL,
  data_tier evidence_tier DEFAULT 'analytical'::evidence_tier NOT NULL,
  provenance ai.source_ref[] DEFAULT '{}'::ai.source_ref[] NOT NULL,
  sys_period tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone) NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.event_source_record (
  link_id uuid DEFAULT uuidv7() NOT NULL,
  event_id uuid,
  record_id uuid,
  source_id uuid,
  raw_ref jsonb,
  role text DEFAULT 'primary'::text NOT NULL,
  raw_table text,
  medium evidence.record_medium,
  agrees boolean,
  note text
);

CREATE TABLE IF NOT EXISTS working.evidence_vector_projection_job (
  id uuid DEFAULT uuidv7() NOT NULL,
  chunk_id uuid NOT NULL,
  projection_version text DEFAULT 'evidence-vector@1'::text NOT NULL,
  reason text NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  authority_state text,
  attempts integer DEFAULT 0 NOT NULL,
  generation bigint DEFAULT 0 NOT NULL,
  next_attempt_at timestamp with time zone DEFAULT now() NOT NULL,
  locked_at timestamp with time zone,
  locked_by text,
  projection_hash text,
  last_error text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  completed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS working.extraction_run (
  id uuid DEFAULT uuidv7() NOT NULL,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  finished_at timestamp with time zone,
  extractor text NOT NULL,
  extractor_version text NOT NULL,
  model_id text,
  source_summary text NOT NULL,
  status text DEFAULT 'running'::text NOT NULL,
  error text,
  stats jsonb DEFAULT '{}'::jsonb NOT NULL,
  graph_lane analysis.graph_lane,
  prompt_version text,
  source_generation bigint
);

CREATE TABLE IF NOT EXISTS working.extraction_window (
  id uuid DEFAULT uuidv7() NOT NULL,
  extraction_run_id uuid NOT NULL,
  chat_conversation_id uuid NOT NULL,
  ordinal_range int4range NOT NULL,
  read_mode text NOT NULL,
  claims_emitted integer DEFAULT 0 NOT NULL,
  ordinals_no_claims integer[] DEFAULT '{}'::integer[] NOT NULL,
  truncated boolean DEFAULT false NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.first_party_context_thread (
  context_thread_id uuid DEFAULT uuidv7() NOT NULL,
  owner_person_id uuid NOT NULL,
  matter_id uuid NOT NULL,
  court_case_id uuid NOT NULL,
  case_key text DEFAULT 'primary'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.first_party_context_thread_message (
  thread_version_id uuid NOT NULL,
  context_thread_id uuid NOT NULL,
  message_id uuid NOT NULL,
  thread_ordinal bigint NOT NULL,
  occurred_at timestamp with time zone,
  source_available_from timestamp with time zone,
  required_for_horizon boolean DEFAULT true NOT NULL,
  membership_confidence double precision NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.first_party_context_thread_source (
  id uuid DEFAULT uuidv7() NOT NULL,
  thread_version_id uuid NOT NULL,
  context_thread_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  source_anchor_ordinal bigint NOT NULL,
  platform text NOT NULL,
  platform_conversation_key text NOT NULL,
  representation_kind text NOT NULL,
  capture_kind text NOT NULL,
  declared_format text NOT NULL,
  originating_device_id uuid,
  perspective_person_id uuid NOT NULL,
  coverage_first_occurred_at timestamp with time zone,
  coverage_last_occurred_at timestamp with time zone,
  coverage_message_count bigint,
  source_available_from timestamp with time zone,
  required_for_horizon boolean DEFAULT true NOT NULL,
  metadata_clock_kind text NOT NULL,
  metadata_timestamp timestamp with time zone,
  metadata_timezone text,
  metadata_clock_basis text NOT NULL,
  metadata_confidence double precision,
  metadata_review_state text NOT NULL,
  metadata_ambiguity text,
  raw_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  raw_metadata_ref text,
  metadata_extractor_id text NOT NULL,
  metadata_extractor_version text NOT NULL,
  assertion_version integer NOT NULL,
  confidence double precision NOT NULL,
  review_state text NOT NULL,
  supersedes_id uuid,
  provenance_digest bytea NOT NULL,
  asserted_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.first_party_context_thread_version (
  id uuid DEFAULT uuidv7() NOT NULL,
  context_thread_id uuid NOT NULL,
  version_ordinal integer NOT NULL,
  classifier_id text NOT NULL,
  classifier_version text NOT NULL,
  assertion_digest bytea NOT NULL,
  confidence double precision NOT NULL,
  review_state text NOT NULL,
  first_occurred_at timestamp with time zone,
  last_occurred_at timestamp with time zone,
  knowledge_available_from timestamp with time zone,
  supersedes_id uuid,
  reviewed_by text,
  reviewed_at timestamp with time zone,
  rationale text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.handle (
  id uuid NOT NULL,
  platform text NOT NULL,
  handle citext NOT NULL,
  owner_entity_id uuid,
  is_blocked boolean DEFAULT false NOT NULL,
  validity tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone) NOT NULL
);

CREATE TABLE IF NOT EXISTS working.message (
  id uuid NOT NULL,
  conversation_id uuid NOT NULL,
  ts_utc timestamp with time zone,
  platform text NOT NULL,
  external_id text,
  serial_number bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  prev_message_id uuid,
  next_message_id uuid,
  time_since_prev_s integer,
  sender_raw text,
  sender_e164 text,
  sender_entity_id uuid,
  recipient_raw text,
  recipient_e164 text,
  direction text,
  message_type text DEFAULT 'text'::text NOT NULL,
  delivery_status text,
  status_code integer,
  is_blocked boolean DEFAULT false NOT NULL,
  raw_ts text,
  tz text,
  ts_earliest timestamp with time zone,
  ts_latest timestamp with time zone,
  temporal_confidence ai.confidence,
  relative_time_refs jsonb DEFAULT '[]'::jsonb NOT NULL,
  word_count integer,
  char_count integer,
  content_sha256 bytea,
  language text,
  surface_sentiment_hint text,
  inferred_intent_hint text,
  topic_hint text,
  domain_type_hint text,
  relevance_hint text,
  custody_relevance_hint text,
  evidence_strength_hint strength_class,
  extraction_confidence ai.confidence,
  is_private boolean DEFAULT false NOT NULL,
  is_redacted boolean DEFAULT false NOT NULL,
  has_attachments boolean DEFAULT false NOT NULL,
  attachment_count integer DEFAULT 0 NOT NULL,
  has_behaviors boolean DEFAULT false NOT NULL,
  behavior_count integer DEFAULT 0 NOT NULL,
  max_behavior_severity text,
  screenshot_attachment_id uuid,
  body_embedding_ref text,
  platform_attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  raw_data jsonb,
  is_read boolean,
  hint_provenance jsonb,
  derived_from_record_id uuid,
  derived_from_raw_table text,
  derived_from_raw_id uuid,
  deriver_version text,
  derived_at timestamp with time zone,
  projection_kind text DEFAULT 'first_party'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS working.message_participant (
  id uuid DEFAULT uuidv7() NOT NULL,
  message_id uuid NOT NULL,
  entity_id uuid,
  participant_raw text,
  participant_e164 text,
  role text NOT NULL,
  conduct_party conduct_party,
  derived_from_raw_id uuid,
  deriver_version text
);

CREATE TABLE IF NOT EXISTS working.message_projection_route (
  normalized_record_id uuid NOT NULL,
  projection_kind text NOT NULL,
  decision_state text DEFAULT 'proposed'::text NOT NULL,
  basis jsonb DEFAULT '{}'::jsonb NOT NULL,
  proposed_by text NOT NULL,
  proposed_at timestamp with time zone DEFAULT now() NOT NULL,
  approved_by text,
  approved_at timestamp with time zone,
  deriver_version text NOT NULL
);

CREATE TABLE IF NOT EXISTS working.normalized_record (
  id uuid DEFAULT uuidv7() NOT NULL,
  artifact_id uuid NOT NULL,
  record_type text NOT NULL,
  source text NOT NULL,
  conversation_id text,
  role text,
  participants jsonb DEFAULT '[]'::jsonb NOT NULL,
  content text DEFAULT ''::text NOT NULL,
  occurred_at timestamp with time zone,
  knowledge_time timestamp with time zone DEFAULT now() NOT NULL,
  disclosure_tier text DEFAULT 'contemporaneous'::text NOT NULL,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  conversation_ref uuid,
  ts_precision precision_class DEFAULT 'exact'::precision_class NOT NULL,
  sensitivity_tier sensitivity_tier,
  data_tier evidence_tier DEFAULT 'extracted'::evidence_tier NOT NULL,
  review_status review_state DEFAULT 'unreviewed'::review_state NOT NULL,
  safe_for_legal_use boolean DEFAULT false NOT NULL,
  provenance_id uuid,
  export_created_at timestamp with time zone,
  acquired_at timestamp with time zone,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL,
  realized_at timestamp with time zone,
  realized_evidence jsonb,
  acquisition_id uuid,
  device_id uuid,
  sender_entity_id uuid,
  derived_from_raw_table text,
  derived_from_raw_id uuid,
  deriver_version text,
  derived_at timestamp with time zone,
  attestation_count integer DEFAULT 0 NOT NULL,
  case_id text DEFAULT 'primary'::text NOT NULL,
  domain text DEFAULT 'evidence'::text NOT NULL,
  topic_tags text[] DEFAULT '{}'::text[] NOT NULL,
  knowledge_actor text DEFAULT 'owner'::text NOT NULL,
  ontology_version text,
  source_record_key text,
  source_content_sha256 bytea,
  sender text,
  recipients jsonb DEFAULT '[]'::jsonb NOT NULL,
  message_corpus text
);

CREATE TABLE IF NOT EXISTS working.organization (
  id uuid NOT NULL,
  org_type text,
  legal_name citext,
  jurisdiction text
);

CREATE TABLE IF NOT EXISTS working.phone (
  id uuid NOT NULL,
  e164 citext,
  raw_number text,
  owner_entity_id uuid,
  is_blocked boolean DEFAULT false NOT NULL,
  validity tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone) NOT NULL
);

CREATE TABLE IF NOT EXISTS working.promotion (
  id uuid DEFAULT uuidv7() NOT NULL,
  candidate_kind text NOT NULL,
  candidate_id uuid NOT NULL,
  lane text NOT NULL,
  target_system text NOT NULL,
  target_ref text NOT NULL,
  promoted_by text NOT NULL,
  promoted_at timestamp with time zone DEFAULT now() NOT NULL,
  revoked_at timestamp with time zone,
  revoked_reason text,
  attrs jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS working.realization_event (
  id uuid DEFAULT uuidv7() NOT NULL,
  case_id text DEFAULT 'primary'::text NOT NULL,
  kind text NOT NULL,
  realized_at timestamp with time zone NOT NULL,
  trigger_record_id uuid,
  evidence_pointer jsonb DEFAULT '{}'::jsonb NOT NULL,
  proposer text NOT NULL,
  approval_state text DEFAULT 'proposed'::text NOT NULL,
  proposed_at timestamp with time zone DEFAULT now() NOT NULL,
  approved_at timestamp with time zone,
  approved_by text,
  notes text
);

CREATE TABLE IF NOT EXISTS working.realization_event_record (
  realization_event_id uuid NOT NULL,
  normalized_record_id uuid NOT NULL,
  case_id text DEFAULT 'primary'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS working.record_visible_from (
  record_id uuid NOT NULL,
  visible_from timestamp with time zone,
  base_version text NOT NULL,
  source_clock_hash text NOT NULL,
  refreshed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.source_provenance (
  id uuid DEFAULT uuidv7() NOT NULL,
  source_raw_table text NOT NULL,
  source_raw_id text NOT NULL,
  revision integer DEFAULT 1 NOT NULL,
  occurred_at timestamp with time zone,
  export_created_at timestamp with time zone,
  acquired_at timestamp with time zone,
  ingested_at timestamp with time zone,
  realized_at timestamp with time zone,
  realized_at_source text,
  realized_at_state text DEFAULT 'unset'::text NOT NULL,
  acquisition_method text DEFAULT 'unknown'::text NOT NULL,
  acquisition_authority text DEFAULT 'unclear'::text NOT NULL,
  source_device text,
  device_custodian text,
  custody_transferred_at timestamp with time zone,
  acquisition_notes text,
  asserted_by text NOT NULL,
  asserted_by_kind text DEFAULT 'human'::text NOT NULL,
  producible boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.temporal_anchor (
  anchor_id uuid DEFAULT uuidv7() NOT NULL,
  anchor_key citext,
  label text NOT NULL,
  anchor_type anchor_kind NOT NULL,
  event_id uuid,
  valid_earliest timestamp with time zone NOT NULL,
  valid_latest timestamp with time zone NOT NULL,
  valid_range tstzrange GENERATED ALWAYS AS (tstzrange(valid_earliest, valid_latest, '[]'::text)) STORED,
  certainty precision_class NOT NULL,
  confidence ai.confidence,
  derived_from uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  requires_human_review boolean DEFAULT false NOT NULL,
  author text NOT NULL,
  asserted_at timestamp with time zone DEFAULT now() NOT NULL,
  retracted_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS working.third_party_context_thread (
  context_thread_id uuid DEFAULT uuidv7() NOT NULL,
  matter_id uuid NOT NULL,
  court_case_id uuid NOT NULL,
  case_key text DEFAULT 'primary'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.third_party_context_thread_message (
  thread_version_id uuid NOT NULL,
  context_thread_id uuid NOT NULL,
  message_id uuid NOT NULL,
  conversation_acquisition_id uuid NOT NULL,
  thread_ordinal bigint NOT NULL,
  occurred_at timestamp with time zone,
  source_available_from timestamp with time zone,
  required_for_horizon boolean DEFAULT true NOT NULL,
  membership_confidence double precision NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.third_party_context_thread_source (
  id uuid DEFAULT uuidv7() NOT NULL,
  thread_version_id uuid NOT NULL,
  context_thread_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  represented_conversation_id uuid NOT NULL,
  conversation_acquisition_id uuid NOT NULL,
  acquisition_activity_receipt_id uuid NOT NULL,
  source_anchor_ordinal bigint NOT NULL,
  platform text NOT NULL,
  platform_conversation_key text NOT NULL,
  representation_kind text NOT NULL,
  capture_kind text NOT NULL,
  declared_format text NOT NULL,
  originating_device_id uuid,
  perspective_entity_id uuid NOT NULL,
  coverage_first_occurred_at timestamp with time zone,
  coverage_last_occurred_at timestamp with time zone,
  coverage_message_count bigint,
  source_available_from timestamp with time zone,
  required_for_horizon boolean DEFAULT true NOT NULL,
  metadata_clock_kind text NOT NULL,
  metadata_timestamp timestamp with time zone,
  metadata_timezone text,
  metadata_clock_basis text NOT NULL,
  metadata_confidence double precision,
  metadata_review_state text NOT NULL,
  metadata_ambiguity text,
  raw_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  raw_metadata_ref text,
  metadata_extractor_id text NOT NULL,
  metadata_extractor_version text NOT NULL,
  assertion_version integer NOT NULL,
  confidence double precision NOT NULL,
  review_state text NOT NULL,
  supersedes_id uuid,
  provenance_digest bytea NOT NULL,
  asserted_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.third_party_context_thread_version (
  id uuid DEFAULT uuidv7() NOT NULL,
  context_thread_id uuid NOT NULL,
  version_ordinal integer NOT NULL,
  classifier_id text NOT NULL,
  classifier_version text NOT NULL,
  assertion_digest bytea NOT NULL,
  confidence double precision NOT NULL,
  review_state text NOT NULL,
  first_occurred_at timestamp with time zone,
  last_occurred_at timestamp with time zone,
  knowledge_available_from timestamp with time zone,
  supersedes_id uuid,
  reviewed_by text,
  reviewed_at timestamp with time zone,
  rationale text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.third_party_conversation (
  id uuid DEFAULT uuidv7() NOT NULL,
  case_id text DEFAULT 'primary'::text NOT NULL,
  source_artifact_id uuid NOT NULL,
  platform text NOT NULL,
  external_thread_key text NOT NULL,
  title text,
  started_at timestamp with time zone,
  ended_at timestamp with time zone,
  message_count integer DEFAULT 0 NOT NULL,
  review_status text DEFAULT 'pending'::text NOT NULL,
  platform_attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  deriver_version text NOT NULL,
  derived_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.third_party_conversation_acquisition (
  id uuid DEFAULT uuidv7() NOT NULL,
  conversation_id uuid NOT NULL,
  acquisition_id uuid NOT NULL,
  approval_state text DEFAULT 'proposed'::text NOT NULL,
  proposed_by text NOT NULL,
  proposed_at timestamp with time zone DEFAULT now() NOT NULL,
  approved_by text,
  approved_at timestamp with time zone,
  supersedes_id uuid,
  notes text
);

CREATE TABLE IF NOT EXISTS working.third_party_message (
  id uuid DEFAULT uuidv7() NOT NULL,
  conversation_id uuid NOT NULL,
  normalized_record_id uuid NOT NULL,
  projection_kind text DEFAULT 'acquired_third_party'::text NOT NULL,
  occurred_at timestamp with time zone,
  platform text NOT NULL,
  external_id text,
  sender_raw text,
  sender_entity_id uuid,
  message_type text DEFAULT 'text'::text NOT NULL,
  temporal_confidence ai.confidence,
  raw_ts text,
  tz text,
  content_sha256 bytea,
  platform_attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
  raw_data jsonb,
  deriver_version text NOT NULL,
  derived_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.third_party_message_participant (
  id uuid DEFAULT uuidv7() NOT NULL,
  message_id uuid NOT NULL,
  entity_id uuid,
  participant_raw text NOT NULL,
  participant_e164 text,
  role text NOT NULL,
  deriver_version text NOT NULL
);

CREATE TABLE IF NOT EXISTS working.walk_checkpoint (
  id uuid DEFAULT uuidv7() NOT NULL,
  walk_run_id uuid NOT NULL,
  checkpoint_no integer NOT NULL,
  checkpoint_kind text NOT NULL,
  last_completed_step_no integer NOT NULL,
  cursor jsonb DEFAULT '{}'::jsonb NOT NULL,
  belief_state jsonb DEFAULT '{}'::jsonb NOT NULL,
  base_version text NOT NULL,
  horizon_hash text NOT NULL,
  chain_hash text NOT NULL,
  is_resumable boolean NOT NULL,
  failure jsonb,
  captured_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.walk_run (
  id uuid DEFAULT uuidv7() NOT NULL,
  case_id text DEFAULT 'primary'::text NOT NULL,
  agent_id text NOT NULL,
  bound_lane text,
  horizon_policy text NOT NULL,
  horizon_ceiling timestamp with time zone,
  model_id text,
  prompt_version text,
  base_version text NOT NULL,
  parameters jsonb DEFAULT '{}'::jsonb NOT NULL,
  genesis_hash text NOT NULL,
  final_corpus_hash text,
  status text DEFAULT 'running'::text NOT NULL,
  invalidated_reason text,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  finished_at timestamp with time zone,
  notes text,
  rewalk_of_id uuid,
  resume_from_checkpoint_id uuid,
  sealed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS working.walk_step (
  id uuid DEFAULT uuidv7() NOT NULL,
  walk_run_id uuid NOT NULL,
  step_no integer NOT NULL,
  horizon_at timestamp with time zone,
  record_id uuid,
  conclusion text,
  belief jsonb,
  confidence real,
  stance text,
  corpus_hash text NOT NULL,
  prev_hash text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.walk_step_realization_retrieval (
  id uuid DEFAULT uuidv7() NOT NULL,
  walk_step_id uuid NOT NULL,
  realization_event_id uuid NOT NULL,
  store text NOT NULL,
  rank integer,
  score real,
  was_used boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS working.walk_step_retrieval (
  id uuid DEFAULT uuidv7() NOT NULL,
  walk_step_id uuid NOT NULL,
  record_id uuid NOT NULL,
  store text NOT NULL,
  rank integer,
  score real,
  was_used boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- ============ primary keys / unique / check ============
ALTER TABLE ai.agno_approvals ADD CONSTRAINT agno_approvals_pkey PRIMARY KEY (id);
ALTER TABLE ai.agno_component_configs ADD CONSTRAINT agno_component_configs_pkey PRIMARY KEY (component_id, version);
ALTER TABLE ai.agno_component_links ADD CONSTRAINT agno_component_links_pkey PRIMARY KEY (parent_component_id, parent_version, link_kind, link_key);
ALTER TABLE ai.agno_components ADD CONSTRAINT agno_components_pkey PRIMARY KEY (component_id);
ALTER TABLE ai.agno_eval_runs ADD CONSTRAINT agno_eval_runs_pkey PRIMARY KEY (run_id);
ALTER TABLE ai.agno_knowledge ADD CONSTRAINT agno_knowledge_pkey PRIMARY KEY (id);
ALTER TABLE ai.agno_learnings ADD CONSTRAINT agno_learnings_pkey PRIMARY KEY (learning_id);
ALTER TABLE ai.agno_memories ADD CONSTRAINT agno_memories_pkey PRIMARY KEY (memory_id);
ALTER TABLE ai.agno_metrics ADD CONSTRAINT agno_metrics_pkey PRIMARY KEY (id);
ALTER TABLE ai.agno_metrics ADD CONSTRAINT agno_metrics_uq_metrics_date_period UNIQUE (date, aggregation_period);
ALTER TABLE ai.agno_schedule_runs ADD CONSTRAINT agno_schedule_runs_pkey PRIMARY KEY (id);
ALTER TABLE ai.agno_schedules ADD CONSTRAINT agno_schedules_pkey PRIMARY KEY (id);
ALTER TABLE ai.agno_schema_versions ADD CONSTRAINT agno_schema_versions_pkey PRIMARY KEY (table_name);
ALTER TABLE ai.agno_service_accounts ADD CONSTRAINT agno_service_accounts_pkey PRIMARY KEY (id);
ALTER TABLE ai.agno_service_accounts ADD CONSTRAINT agno_service_accounts_token_hash_key UNIQUE (token_hash);
ALTER TABLE ai.agno_sessions ADD CONSTRAINT agno_sessions_pkey PRIMARY KEY (session_id);
ALTER TABLE ai.agno_spans ADD CONSTRAINT agno_spans_pkey PRIMARY KEY (span_id);
ALTER TABLE ai.agno_traces ADD CONSTRAINT agno_traces_pkey PRIMARY KEY (trace_id);
ALTER TABLE ai.api_keys ADD CONSTRAINT api_keys_key_key UNIQUE (key);
ALTER TABLE ai.api_keys ADD CONSTRAINT api_keys_pkey PRIMARY KEY (id);
ALTER TABLE ai.casebible_evidence_contents ADD CONSTRAINT casebible_evidence_contents_pkey PRIMARY KEY (id);
ALTER TABLE ai.casebible_evidence_test_contents ADD CONSTRAINT casebible_evidence_test_contents_pkey PRIMARY KEY (id);
ALTER TABLE ai.casebible_ingest_test2_contents ADD CONSTRAINT casebible_ingest_test2_contents_pkey PRIMARY KEY (id);
ALTER TABLE ai.casebible_ingest_test_contents ADD CONSTRAINT casebible_ingest_test_contents_pkey PRIMARY KEY (id);
ALTER TABLE ai.platform_context_contents ADD CONSTRAINT platform_context_contents_pkey PRIMARY KEY (id);
ALTER TABLE ai.platform_knowledge_contents ADD CONSTRAINT platform_knowledge_contents_pkey PRIMARY KEY (id);
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_receipt_api_payload_sha256_check CHECK ((octet_length(api_payload_sha256) = 32));
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_receipt_approved_by_check CHECK ((length(btrim(approved_by)) > 0));
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_receipt_canonical_payload_sha256_check CHECK ((octet_length(canonical_payload_sha256) = 32));
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_receipt_imported_by_check CHECK ((length(btrim(imported_by)) > 0));
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_receipt_manifest_sha256_check CHECK ((octet_length(manifest_sha256) = 32));
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_receipt_manifest_sha256_key UNIQUE (manifest_sha256);
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_receipt_payload_byte_length_check CHECK ((payload_byte_length > 0));
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_receipt_payload_schema_version_check CHECK ((length(btrim(payload_schema_version)) > 0));
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_receipt_pkey PRIMARY KEY (id);
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_receipt_source_git_commit_check CHECK ((source_git_commit ~ '^[0-9a-f]{40}$'::text));
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_receipt_source_migration_sha256_check CHECK ((octet_length(source_migration_sha256) = 32));
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_receipt_source_migration_uri_check CHECK ((length(btrim(source_migration_uri)) > 0));
ALTER TABLE analysis.chunk_classification ADD CONSTRAINT chunk_classification_judge_confidence_check CHECK (((judge_confidence IS NULL) OR ((judge_confidence >= (0)::double precision) AND (judge_confidence <= (1)::double precision))));
ALTER TABLE analysis.chunk_classification ADD CONSTRAINT chunk_classification_pkey PRIMARY KEY (id);
ALTER TABLE analysis.chunk_classification ADD CONSTRAINT chunk_classification_severity_check CHECK (((severity IS NULL) OR ((severity >= 0) AND (severity <= 10))));
ALTER TABLE analysis.chunk_classification ADD CONSTRAINT chunkclass_adjudication_fields_complete CHECK ((((decision_id IS NULL) AND (actor IS NULL) AND (decision IS NULL) AND (reason IS NULL) AND (source IS NULL) AND (adjudicated_at IS NULL)) OR ((decision_id IS NOT NULL) AND (actor IS NOT NULL) AND (decision IS NOT NULL) AND (reason IS NOT NULL) AND (source IS NOT NULL) AND (adjudicated_at IS NOT NULL))));
ALTER TABLE analysis.chunk_classification ADD CONSTRAINT chunkclass_decision_valid CHECK (((decision IS NULL) OR (decision = ANY (ARRAY['approve'::text, 'correct'::text]))));
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_asserted_by_check CHECK ((length(btrim(asserted_by)) > 0));
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_asserted_by_kind_check CHECK ((asserted_by_kind = ANY (ARRAY['owner'::text, 'model'::text])));
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_assertion_generation_check CHECK ((assertion_generation = ANY (ARRAY[1, 2])));
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_assertion_kind_check CHECK ((assertion_kind = ANY (ARRAY['connection'::text, 'significance'::text, 'decision'::text, 'exposure'::text, 'gap'::text, 'correction'::text])));
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text));
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_disposition_dated CHECK (((owner_disposition = 'unreviewed'::text) OR (disposition_at IS NOT NULL)));
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_id_assertion_generation_key UNIQUE (id, assertion_generation);
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_no_self_supersede CHECK ((supersedes_id IS DISTINCT FROM id));
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_owner_disposition_check CHECK ((owner_disposition = ANY (ARRAY['unreviewed'::text, 'accepted'::text, 'rejected'::text, 'parked'::text, 'superseded'::text])));
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_parked_has_reason CHECK (((owner_disposition <> 'parked'::text) OR (disposition_reason IS NOT NULL)));
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_pkey PRIMARY KEY (id);
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_rationale_check CHECK ((length(btrim(rationale)) > 0));
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_salience_check CHECK (((salience IS NULL) OR (salience = ANY (ARRAY['hot'::text, 'good'::text, 'warm'::text]))));
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_statement_check CHECK ((length(btrim(statement)) > 0));
ALTER TABLE analysis.claim_assertion_member ADD CONSTRAINT claim_assertion_member_assertion_id_member_ordinal_key UNIQUE (assertion_id, member_ordinal);
ALTER TABLE analysis.claim_assertion_member ADD CONSTRAINT claim_assertion_member_member_ordinal_check CHECK ((member_ordinal >= 0));
ALTER TABLE analysis.claim_assertion_member ADD CONSTRAINT claim_assertion_member_member_role_check CHECK ((member_role = ANY (ARRAY['constituent'::text, 'supports'::text, 'contradicts'::text, 'context'::text])));
ALTER TABLE analysis.claim_assertion_member ADD CONSTRAINT claim_assertion_member_pkey PRIMARY KEY (assertion_id, claim_candidate_id);
ALTER TABLE analysis.claim_assertion_synthesis_member ADD CONSTRAINT claim_assertion_synthesis_membe_synthesis_id_member_ordinal_key UNIQUE (synthesis_id, member_ordinal);
ALTER TABLE analysis.claim_assertion_synthesis_member ADD CONSTRAINT claim_assertion_synthesis_member_agreement_state_check CHECK ((agreement_state = ANY (ARRAY['concurs'::text, 'diverges'::text, 'extends'::text])));
ALTER TABLE analysis.claim_assertion_synthesis_member ADD CONSTRAINT claim_assertion_synthesis_member_member_generation_check CHECK ((member_generation = 1));
ALTER TABLE analysis.claim_assertion_synthesis_member ADD CONSTRAINT claim_assertion_synthesis_member_member_ordinal_check CHECK ((member_ordinal >= 0));
ALTER TABLE analysis.claim_assertion_synthesis_member ADD CONSTRAINT claim_assertion_synthesis_member_pkey PRIMARY KEY (synthesis_id, member_assertion_id);
ALTER TABLE analysis.claim_assertion_synthesis_member ADD CONSTRAINT synthesis_divergence_is_explained CHECK (((agreement_state <> 'diverges'::text) OR (divergence_note IS NOT NULL)));
ALTER TABLE analysis.claim_assertion_synthesis_member ADD CONSTRAINT synthesis_member_not_self CHECK ((synthesis_id <> member_assertion_id));
ALTER TABLE analysis.completion_evidence ADD CONSTRAINT completion_evidence_outcome_check CHECK ((outcome = ANY (ARRAY['satisfied'::text, 'unmet'::text, 'overcome'::text, 'partial'::text])));
ALTER TABLE analysis.completion_evidence ADD CONSTRAINT completion_evidence_pkey PRIMARY KEY (id);
ALTER TABLE analysis.completion_evidence ADD CONSTRAINT completion_sha_len CHECK (((sha256 IS NULL) OR (octet_length(sha256) = 32)));
ALTER TABLE analysis.content_chunk_classification_decision ADD CONSTRAINT content_chunk_classification_deci_chunk_id_decision_version_key UNIQUE (chunk_id, decision_version);
ALTER TABLE analysis.content_chunk_classification_decision ADD CONSTRAINT content_chunk_classification_decision_check CHECK (((decision_kind <> 'initial_context'::text) OR ((lane = 'context'::text) AND (review_state = 'system_initial'::text))));
ALTER TABLE analysis.content_chunk_classification_decision ADD CONSTRAINT content_chunk_classification_decision_check1 CHECK ((((reviewed_by IS NULL) AND (reviewed_at IS NULL)) OR ((reviewed_by IS NOT NULL) AND (reviewed_at IS NOT NULL))));
ALTER TABLE analysis.content_chunk_classification_decision ADD CONSTRAINT content_chunk_classification_decision_check2 CHECK (((review_state <> ALL (ARRAY['human_approved'::text, 'human_rejected'::text])) OR (reviewed_at IS NOT NULL)));
ALTER TABLE analysis.content_chunk_classification_decision ADD CONSTRAINT content_chunk_classification_decision_classifier_id_check CHECK ((length(btrim(classifier_id)) > 0));
ALTER TABLE analysis.content_chunk_classification_decision ADD CONSTRAINT content_chunk_classification_decision_classifier_version_check CHECK ((length(btrim(classifier_version)) > 0));
ALTER TABLE analysis.content_chunk_classification_decision ADD CONSTRAINT content_chunk_classification_decision_confidence_check CHECK (((confidence >= (0)::double precision) AND (confidence <= (1)::double precision)));
ALTER TABLE analysis.content_chunk_classification_decision ADD CONSTRAINT content_chunk_classification_decision_decision_kind_check CHECK ((decision_kind = ANY (ARRAY['initial_context'::text, 'reviewed_assignment'::text, 'supersession'::text])));
ALTER TABLE analysis.content_chunk_classification_decision ADD CONSTRAINT content_chunk_classification_decision_decision_version_check CHECK ((decision_version > 0));
ALTER TABLE analysis.content_chunk_classification_decision ADD CONSTRAINT content_chunk_classification_decision_lane_check CHECK ((lane = ANY (ARRAY['context'::text, 'legal'::text, 'personal_history'::text])));
ALTER TABLE analysis.content_chunk_classification_decision ADD CONSTRAINT content_chunk_classification_decision_pkey PRIMARY KEY (id);
ALTER TABLE analysis.content_chunk_classification_decision ADD CONSTRAINT content_chunk_classification_decision_review_state_check CHECK ((review_state = ANY (ARRAY['system_initial'::text, 'pending'::text, 'human_approved'::text, 'human_rejected'::text, 'superseded'::text])));
ALTER TABLE analysis.corroboration_flag ADD CONSTRAINT corroboration_flag_pkey PRIMARY KEY (flag_id);
ALTER TABLE analysis.corroboration_flag ADD CONSTRAINT corroboration_flag_status_check CHECK ((status = ANY (ARRAY['open'::text, 'partial'::text, 'corroborated'::text, 'unobtainable'::text])));
ALTER TABLE analysis.corroboration_flag ADD CONSTRAINT corroboration_flag_target_kind_check CHECK ((target_kind = ANY (ARRAY['record'::text, 'knowledge'::text, 'run'::text])));
ALTER TABLE analysis.discovery_request ADD CONSTRAINT discovery_request_hitl_status_check CHECK ((hitl_status = ANY (ARRAY['pending'::text, 'approved'::text, 'declined'::text])));
ALTER TABLE analysis.discovery_request ADD CONSTRAINT discovery_request_instrument_type_check CHECK ((instrument_type = ANY (ARRAY['subpoena'::text, 'subpoena_duces_tecum'::text, 'rfa'::text, 'rfp'::text, 'rog'::text, 'witness_question'::text, 'deposition_topic'::text, 'self_collection'::text, 'records_request'::text, 'preservation_letter'::text])));
ALTER TABLE analysis.discovery_request ADD CONSTRAINT discovery_request_pkey PRIMARY KEY (id);
ALTER TABLE analysis.discovery_request ADD CONSTRAINT discovery_request_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'served'::text, 'responded'::text, 'withdrawn'::text])));
ALTER TABLE analysis.discovery_request_revision ADD CONSTRAINT discovery_request_revision_pkey PRIMARY KEY (revision_id);
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_confidence_tier_check CHECK ((confidence_tier = ANY (ARRAY['high'::text, 'medium'::text, 'low'::text])));
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_evidence_need_kind_check CHECK ((evidence_need_kind = ANY (ARRAY['corroboration'::text, 'original_source'::text, 'authentication'::text, 'metadata'::text, 'completeness'::text, 'chain_of_custody'::text, 'rebuttal'::text, 'foundation'::text, 'impeachment'::text])));
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_hitl_status_check CHECK ((hitl_status = ANY (ARRAY['pending'::text, 'approved'::text, 'declined'::text])));
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_human_action_kind_check CHECK ((human_action_kind = ANY (ARRAY['review_label'::text, 'approve_instrument'::text, 'serve_subpoena'::text, 'collect_self'::text, 'request_from_counsel'::text, 'interview_witness'::text, 'authenticate'::text, 'redact'::text, 'decide_relevance'::text, 'file_motion'::text, 'none_yet'::text])));
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_label_sensitivity_check CHECK ((label_sensitivity = ANY (ARRAY['routine'::text, 'sensitive'::text, 'high'::text])));
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_pkey PRIMARY KEY (id);
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_priority_check CHECK ((priority = ANY (ARRAY['P0_critical'::text, 'P1_high'::text, 'P2_medium'::text, 'P3_low'::text, 'P4_backlog'::text])));
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_priority_override_check CHECK (((priority_override IS NULL) OR (priority_override = ANY (ARRAY['P0_critical'::text, 'P1_high'::text, 'P2_medium'::text, 'P3_low'::text, 'P4_backlog'::text]))));
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_risk_check CHECK ((risk = ANY (ARRAY['none'::text, 'low'::text, 'medium'::text, 'high'::text])));
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'proposed'::text, 'needs_human_review'::text, 'approved'::text, 'in_progress'::text, 'awaiting_response'::text, 'blocked'::text, 'obtained'::text, 'verified'::text, 'closed_satisfied'::text, 'closed_unmet'::text, 'closed_overcome'::text, 'superseded'::text, 'archived'::text])));
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_task_key_key UNIQUE (task_key);
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_trigger_kind_check CHECK ((trigger_kind = ANY (ARRAY['contradiction'::text, 'anomaly'::text, 'gap'::text, 'behavioral_pattern'::text, 'custody_factor_concern'::text, 'safety_concern'::text, 'communication_barrier'::text, 'established_custodial_environment'::text, 'selective_framing'::text, 'timeline_hole'::text, 'attribution_uncertainty'::text, 'manual'::text])));
ALTER TABLE analysis.export ADD CONSTRAINT export_pkey PRIMARY KEY (export_id);
ALTER TABLE analysis.export_item ADD CONSTRAINT export_item_pkey PRIMARY KEY (package_id, evidence_item_id);
ALTER TABLE analysis.export_package ADD CONSTRAINT export_package_pkey PRIMARY KEY (id);
ALTER TABLE analysis.export_package ADD CONSTRAINT export_package_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'exported'::text, 'withdrawn'::text])));
ALTER TABLE analysis.factor_citation ADD CONSTRAINT factcite_legal_gate CHECK (((safe_for_legal_use = false) OR ((review_status = 'approved'::review_state) AND (is_hypothesis = false))));
ALTER TABLE analysis.factor_citation ADD CONSTRAINT factor_citation_evidence_item_id_factor_supports_factor_key UNIQUE (evidence_item_id, factor, supports_factor);
ALTER TABLE analysis.factor_citation ADD CONSTRAINT factor_citation_pkey PRIMARY KEY (id);
ALTER TABLE analysis.factor_citation ADD CONSTRAINT factor_citation_strength_check CHECK ((strength = ANY (ARRAY['weak'::text, 'moderate'::text, 'strong'::text, 'decisive'::text])));
ALTER TABLE analysis.finding ADD CONSTRAINT finding_legal_gate CHECK (((safe_for_legal_use = false) OR ((review_status = 'approved'::review_state) AND (is_hypothesis = false))));
ALTER TABLE analysis.finding ADD CONSTRAINT finding_pattern_type_check CHECK (((pattern_type IS NULL) OR (pattern_type = ANY (ARRAY['escalation'::text, 'cycle'::text, 'triggered_response'::text, 'time_based'::text, 'single'::text]))));
ALTER TABLE analysis.finding ADD CONSTRAINT finding_pkey PRIMARY KEY (id);
ALTER TABLE analysis.finding ADD CONSTRAINT finding_severity_progression_check CHECK (((severity_progression IS NULL) OR (severity_progression = ANY (ARRAY['escalating'::text, 'stable'::text, 'de_escalating'::text]))));
ALTER TABLE analysis.finding_version ADD CONSTRAINT finding_version_pkey PRIMARY KEY (version_id);
ALTER TABLE analysis.graph_edge_projection ADD CONSTRAINT graph_edge_projection_graph_lane_graph_database_graph_edge__key UNIQUE (graph_lane, graph_database, graph_edge_id);
ALTER TABLE analysis.graph_edge_projection ADD CONSTRAINT graph_edge_projection_pkey PRIMARY KEY (id);
ALTER TABLE analysis.graph_node_projection ADD CONSTRAINT graph_node_projection_graph_lane_graph_database_graph_node__key UNIQUE (graph_lane, graph_database, graph_node_id);
ALTER TABLE analysis.graph_node_projection ADD CONSTRAINT graph_node_projection_pkey PRIMARY KEY (id);
ALTER TABLE analysis.graphrag_comparison_join ADD CONSTRAINT graphrag_comparison_join_pkey PRIMARY KEY (id);
ALTER TABLE analysis.graphrag_comparison_join ADD CONSTRAINT graphrag_comparison_join_run_id_stage_id_stage_version_mani_key UNIQUE (run_id, stage_id, stage_version, manifest_id, manifest_digest);
ALTER TABLE analysis.graphrag_comparison_run ADD CONSTRAINT graphrag_comparison_run_pkey PRIMARY KEY (id);
ALTER TABLE analysis.graphrag_eligibility_manifest ADD CONSTRAINT graphrag_eligibility_manifest_pkey PRIMARY KEY (id);
ALTER TABLE analysis.graphrag_eligibility_manifest ADD CONSTRAINT graphrag_eligibility_manifest_status_check CHECK ((status = ANY (ARRAY['open'::text, 'sealed'::text])));
ALTER TABLE analysis.graphrag_eligibility_manifest_member ADD CONSTRAINT graphrag_eligibility_manifest_me_normalized_record_digest_check CHECK (((normalized_record_digest IS NULL) OR (octet_length(normalized_record_digest) = 32)));
ALTER TABLE analysis.graphrag_eligibility_manifest_member ADD CONSTRAINT graphrag_eligibility_manifest_member_ordinal_check CHECK ((ordinal >= 0));
ALTER TABLE analysis.graphrag_eligibility_manifest_member ADD CONSTRAINT graphrag_eligibility_manifest_member_pkey PRIMARY KEY (manifest_id, ordinal);
ALTER TABLE analysis.graphrag_eligibility_manifest_member ADD CONSTRAINT graphrag_eligibility_manifest_member_source_sha256_check CHECK (((source_sha256 IS NULL) OR (octet_length(source_sha256) = 32)));
ALTER TABLE analysis.graphrag_lane_candidate ADD CONSTRAINT graphrag_lane_candidate_lane_result_id_ordinal_key UNIQUE (lane_result_id, ordinal);
ALTER TABLE analysis.graphrag_lane_candidate ADD CONSTRAINT graphrag_lane_candidate_normalized_record_digest_check CHECK (((normalized_record_digest IS NULL) OR (octet_length(normalized_record_digest) = 32)));
ALTER TABLE analysis.graphrag_lane_candidate ADD CONSTRAINT graphrag_lane_candidate_ordinal_check CHECK ((ordinal >= 0));
ALTER TABLE analysis.graphrag_lane_candidate ADD CONSTRAINT graphrag_lane_candidate_pkey PRIMARY KEY (id);
ALTER TABLE analysis.graphrag_lane_candidate ADD CONSTRAINT graphrag_lane_candidate_source_sha256_check CHECK (((source_sha256 IS NULL) OR (octet_length(source_sha256) = 32)));
ALTER TABLE analysis.graphrag_lane_receipt ADD CONSTRAINT graphrag_lane_receipt_pkey PRIMARY KEY (id);
ALTER TABLE analysis.graphrag_lane_receipt ADD CONSTRAINT graphrag_lane_receipt_run_id_lane_id_stage_id_stage_version_key UNIQUE (run_id, lane_id, stage_id, stage_version, manifest_digest);
ALTER TABLE analysis.graphrag_lane_result ADD CONSTRAINT graphrag_lane_result_pkey PRIMARY KEY (id);
ALTER TABLE analysis.graphrag_lane_result ADD CONSTRAINT graphrag_lane_result_run_id_lane_id_key UNIQUE (run_id, lane_id);
ALTER TABLE analysis.human_label ADD CONSTRAINT human_label_pkey PRIMARY KEY (conversation_key, seq);
ALTER TABLE analysis.human_label ADD CONSTRAINT human_label_severity_check CHECK (((severity IS NULL) OR ((severity >= 0) AND (severity <= 10))));
ALTER TABLE analysis.human_label_gold ADD CONSTRAINT human_label_gold_pkey PRIMARY KEY (conversation_key, seq);
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_idempotency_key_check CHECK (((length(btrim(idempotency_key)) >= 1) AND (length(btrim(idempotency_key)) <= 200)));
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_item_key UNIQUE (evidence_item_id);
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_knowledge_lane_check CHECK ((knowledge_lane = 'evidence'::text));
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_pkey PRIMARY KEY (id);
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_pointer_key UNIQUE (court_case_id, source_pointer_hash);
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_promoted_by_check CHECK ((length(btrim(promoted_by)) > 0));
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_request_key UNIQUE (matter_id, idempotency_key);
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_retrieval_item_ref_check CHECK ((length(btrim(retrieval_item_ref)) > 0));
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_source_pointer_check CHECK ((jsonb_typeof(source_pointer) = 'object'::text));
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_source_pointer_hash_check CHECK ((octet_length(source_pointer_hash) = 32));
ALTER TABLE analysis.legal_timeline_event ADD CONSTRAINT legal_timeline_event_event_type_check CHECK ((event_type = ANY (ARRAY['communication'::text, 'incident'::text, 'filing'::text, 'hearing'::text, 'order'::text, 'exchange'::text, 'visit'::text, 'other'::text])));
ALTER TABLE analysis.legal_timeline_event ADD CONSTRAINT legal_timeline_event_pkey PRIMARY KEY (id);
ALTER TABLE analysis.legal_timeline_event ADD CONSTRAINT legaltl_legal_gate CHECK (((safe_for_legal_use = false) OR (review_status = 'approved'::review_state)));
ALTER TABLE analysis.location_assertion ADD CONSTRAINT locassert_legal_gate CHECK (((safe_for_legal_use = false) OR (review_status = 'approved'::review_state)));
ALTER TABLE analysis.location_assertion ADD CONSTRAINT location_assertion_data_tier_check CHECK ((data_tier = ANY (ARRAY['inferred'::evidence_tier, 'analytical'::evidence_tier])));
ALTER TABLE analysis.location_assertion ADD CONSTRAINT location_assertion_pkey PRIMARY KEY (id);
ALTER TABLE analysis.location_assertion ADD CONSTRAINT location_assertion_subject_type_check CHECK ((subject_type = ANY (ARRAY['event'::text, 'message'::text, 'person'::text, 'device'::text, 'media'::text])));
ALTER TABLE analysis.location_contradiction ADD CONSTRAINT chk_loc_contra_distinct CHECK ((claimed_assertion_id <> observed_assertion_id));
ALTER TABLE analysis.location_contradiction ADD CONSTRAINT location_contradiction_data_tier_check CHECK ((data_tier = 'analytical'::evidence_tier));
ALTER TABLE analysis.location_contradiction ADD CONSTRAINT location_contradiction_pkey PRIMARY KEY (id);
ALTER TABLE analysis.location_contradiction ADD CONSTRAINT loccontra_legal_gate CHECK (((safe_for_legal_use = false) OR (review_status = 'approved'::review_state)));
ALTER TABLE analysis.matter_knowledge_partition ADD CONSTRAINT matter_knowledge_partition_created_by_check CHECK ((length(btrim(created_by)) > 0));
ALTER TABLE analysis.matter_knowledge_partition ADD CONSTRAINT matter_knowledge_partition_partition_key_check CHECK ((length(btrim(partition_key)) > 0));
ALTER TABLE analysis.matter_knowledge_partition ADD CONSTRAINT matter_knowledge_partition_pkey PRIMARY KEY (partition_key);
ALTER TABLE analysis.matter_knowledge_partition ADD CONSTRAINT matter_knowledge_partition_scope_key UNIQUE (partition_key, matter_id);
ALTER TABLE analysis.pattern_finding ADD CONSTRAINT pattern_finding_attribution_gate CHECK (((safe_for_legal_use = false) OR (author_party IS NOT NULL)));
ALTER TABLE analysis.pattern_finding ADD CONSTRAINT pattern_finding_legal_gate CHECK (((safe_for_legal_use = false) OR (review_status = 'approved'::review_state)));
ALTER TABLE analysis.pattern_finding ADD CONSTRAINT pattern_finding_pkey PRIMARY KEY (id);
ALTER TABLE analysis.pattern_finding ADD CONSTRAINT pattern_finding_score_chk CHECK (((score IS NULL) OR ((score >= 1) AND (score <= 10))));
ALTER TABLE analysis.pattern_finding ADD CONSTRAINT pattern_finding_sev_chk CHECK (((severity IS NULL) OR ((severity >= 0) AND (severity <= 10))));
ALTER TABLE analysis.pattern_finding ADD CONSTRAINT pattern_finding_subj_chk CHECK ((subject_type = ANY (ARRAY['message'::text, 'ocr_text'::text, 'transcript'::text, 'event'::text])));
ALTER TABLE analysis.pattern_finding ADD CONSTRAINT pattern_finding_tier_chk CHECK ((data_tier = ANY (ARRAY['inferred'::evidence_tier, 'analytical'::evidence_tier])));
ALTER TABLE analysis.redaction ADD CONSTRAINT redaction_pkey PRIMARY KEY (redaction_id);
ALTER TABLE analysis.relational_classification ADD CONSTRAINT relational_classification_classified_by_check CHECK ((classified_by = ANY (ARRAY['rule'::text, 'model'::text, 'human'::text])));
ALTER TABLE analysis.relational_classification ADD CONSTRAINT relational_classification_pkey PRIMARY KEY (id);
ALTER TABLE analysis.relational_classification ADD CONSTRAINT relational_classification_subject_type_check CHECK ((subject_type = ANY (ARRAY['message'::text, 'event'::text, 'call'::text])));
ALTER TABLE analysis.relational_classification ADD CONSTRAINT relcls_legal_gate CHECK (((safe_for_legal_use = false) OR (review_status = 'approved'::review_state)));
ALTER TABLE analysis.resolution_evidence ADD CONSTRAINT resolution_evidence_pkey PRIMARY KEY (id);
ALTER TABLE analysis.resolution_evidence ADD CONSTRAINT resolution_evidence_polarity_check CHECK ((polarity = ANY (ARRAY['supports'::text, 'contradicts'::text])));
ALTER TABLE analysis.review_decision ADD CONSTRAINT review_decision_court_readiness_check CHECK ((court_readiness = ANY (ARRAY['not_reviewed'::text, 'draft'::text, 'needs_corroboration'::text, 'review_passed'::text, 'court_ready'::text, 'excluded'::text, 'strategically_sensitive'::text])));
ALTER TABLE analysis.review_decision ADD CONSTRAINT review_decision_decision_check CHECK ((decision = ANY (ARRAY['approved'::text, 'rejected'::text, 'needs_changes'::text, 'needs_context'::text, 'escalated'::text, 'hold'::text])));
ALTER TABLE analysis.review_decision ADD CONSTRAINT review_decision_pkey PRIMARY KEY (decision_id);
ALTER TABLE analysis.review_task ADD CONSTRAINT review_task_pkey PRIMARY KEY (task_id);
ALTER TABLE analysis.review_task ADD CONSTRAINT review_task_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'in_review'::text, 'resolved'::text])));
ALTER TABLE analysis.score ADD CONSTRAINT score_band_check CHECK ((band = ANY (ARRAY['very_low'::text, 'low'::text, 'medium'::text, 'high'::text, 'very_high'::text])));
ALTER TABLE analysis.score ADD CONSTRAINT score_method_check CHECK ((method = ANY (ARRAY['rule'::text, 'model'::text, 'human'::text, 'hybrid'::text])));
ALTER TABLE analysis.score ADD CONSTRAINT score_pkey PRIMARY KEY (score_id);
ALTER TABLE analysis.score ADD CONSTRAINT score_score_type_check CHECK ((score_type = ANY (ARRAY['extraction'::text, 'temporal'::text, 'identity'::text, 'location'::text, 'evidence_strength'::text, 'legal_relevance'::text, 'abuse_pattern'::text, 'corroboration'::text, 'contradiction'::text, 'court_readiness'::text])));
ALTER TABLE analysis.task_dependency ADD CONSTRAINT task_dependency_check CHECK ((task_id <> depends_on));
ALTER TABLE analysis.task_dependency ADD CONSTRAINT task_dependency_dep_kind_check CHECK ((dep_kind = ANY (ARRAY['blocks'::text, 'prereq_of'::text, 'corroborates'::text, 'duplicate_of'::text])));
ALTER TABLE analysis.task_dependency ADD CONSTRAINT task_dependency_pkey PRIMARY KEY (task_id, depends_on, dep_kind);
ALTER TABLE analysis.task_event ADD CONSTRAINT task_event_actor_kind_check CHECK ((actor_kind = ANY (ARRAY['system'::text, 'agent'::text, 'human'::text])));
ALTER TABLE analysis.task_event ADD CONSTRAINT task_event_pkey PRIMARY KEY (event_id);
ALTER TABLE analysis.task_legal_link ADD CONSTRAINT task_legal_link_pkey PRIMARY KEY (task_id, legal_issue_id, factor);
ALTER TABLE analysis.task_person ADD CONSTRAINT task_person_pkey PRIMARY KEY (task_id, person_id, role);
ALTER TABLE analysis.task_person ADD CONSTRAINT task_person_role_check CHECK ((role = ANY (ARRAY['subject'::text, 'custodian'::text, 'witness'::text, 'child'::text, 'third_party'::text, 'self'::text])));
ALTER TABLE analysis.task_revision ADD CONSTRAINT task_revision_pkey PRIMARY KEY (revision_id);
ALTER TABLE analysis.time_assertion ADD CONSTRAINT time_assertion_pkey PRIMARY KEY (assertion_id);
ALTER TABLE analysis.time_assertion ADD CONSTRAINT time_assertion_tz_source_check CHECK (((tz_source IS NULL) OR (tz_source = ANY (ARRAY['exif_offset'::text, 'export_header'::text, 'assumed_local'::text, 'device_setting'::text, 'unknown'::text]))));
ALTER TABLE analysis.time_assertion ADD CONSTRAINT valid_ordering CHECK ((valid_earliest <= valid_latest));
ALTER TABLE analysis.timeline_event ADD CONSTRAINT timeline_event_event_key_key UNIQUE (event_key);
ALTER TABLE analysis.timeline_event ADD CONSTRAINT timeline_event_pkey PRIMARY KEY (event_id);
ALTER TABLE analysis.workflow_run ADD CONSTRAINT workflow_run_custody_tier_check CHECK ((custody_tier = ANY (ARRAY['full'::text, 'light'::text])));
ALTER TABLE analysis.workflow_run ADD CONSTRAINT workflow_run_gate_state_check CHECK (((gate_state = ANY (ARRAY['waiting'::text, 'released'::text, 'abort'::text])) OR (gate_state IS NULL)));
ALTER TABLE analysis.workflow_run ADD CONSTRAINT workflow_run_mode_check CHECK ((mode = ANY (ARRAY['auto'::text, 'supervised'::text])));
ALTER TABLE analysis.workflow_run ADD CONSTRAINT workflow_run_pkey PRIMARY KEY (run_id);
ALTER TABLE analysis.workflow_run ADD CONSTRAINT workflow_run_status_check CHECK ((status = ANY (ARRAY['running'::text, 'paused'::text, 'completed'::text, 'failed'::text])));
ALTER TABLE analysis.workflow_run_stage ADD CONSTRAINT workflow_run_stage_pkey PRIMARY KEY (stage_id);
ALTER TABLE analysis.workflow_run_stage ADD CONSTRAINT workflow_run_stage_run_id_seq_key UNIQUE (run_id, seq);
ALTER TABLE analysis.workflow_run_stage ADD CONSTRAINT workflow_run_stage_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'running'::text, 'success'::text, 'failed'::text, 'skipped'::text])));
ALTER TABLE canon.canonical_table ADD CONSTRAINT canonical_table_pkey PRIMARY KEY (id);
ALTER TABLE canon.canonical_table ADD CONSTRAINT canonical_table_table_schema_table_name_key UNIQUE (table_schema, table_name);
ALTER TABLE canon.change_application ADD CONSTRAINT change_application_pkey PRIMARY KEY (id);
ALTER TABLE canon.change_application ADD CONSTRAINT change_application_proposal_id_key UNIQUE (proposal_id);
ALTER TABLE canon.change_decision ADD CONSTRAINT change_decision_decision_check CHECK ((decision = ANY (ARRAY['approve'::text, 'reject'::text, 'requeue'::text])));
ALTER TABLE canon.change_decision ADD CONSTRAINT change_decision_pkey PRIMARY KEY (id);
ALTER TABLE canon.change_proposal ADD CONSTRAINT change_proposal_origin_surface_check CHECK ((origin_surface = ANY (ARRAY['extractor'::text, 'workbench'::text, 'graph_reconciliation'::text, 'agent'::text, 'human'::text])));
ALTER TABLE canon.change_proposal ADD CONSTRAINT change_proposal_pkey PRIMARY KEY (id);
ALTER TABLE canon.change_proposal ADD CONSTRAINT change_proposal_proposal_kind_check CHECK ((proposal_kind = ANY (ARRAY['correct'::text, 'adopt_candidate'::text, 'promote'::text, 'merge'::text, 'retire'::text, 'create'::text])));
ALTER TABLE canon.change_proposal ADD CONSTRAINT change_proposal_status_check CHECK ((status = ANY (ARRAY['proposed'::text, 'approved'::text, 'rejected'::text, 'stale_requeued'::text, 'applied'::text, 'failed'::text])));
ALTER TABLE canon.change_tier ADD CONSTRAINT change_tier_pkey PRIMARY KEY (tier);
ALTER TABLE canon.recompute_queue ADD CONSTRAINT recompute_queue_pkey PRIMARY KEY (id);
ALTER TABLE canon.recompute_queue ADD CONSTRAINT recompute_queue_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'claimed'::text, 'done'::text, 'failed'::text, 'skipped'::text])));
ALTER TABLE context.activity_execution ADD CONSTRAINT activity_execution_activity_name_check CHECK ((length(btrim(activity_name)) > 0));
ALTER TABLE context.activity_execution ADD CONSTRAINT activity_execution_id_source_version_id_key UNIQUE (id, source_version_id);
ALTER TABLE context.activity_execution ADD CONSTRAINT activity_execution_idempotency_key_check CHECK ((length(btrim(idempotency_key)) > 0));
ALTER TABLE context.activity_execution ADD CONSTRAINT activity_execution_pkey PRIMARY KEY (id);
ALTER TABLE context.activity_execution ADD CONSTRAINT activity_execution_request_digest_check CHECK (((request_digest IS NULL) OR (octet_length(request_digest) = 32)));
ALTER TABLE context.activity_execution ADD CONSTRAINT activity_execution_source_version_id_activity_name_idempote_key UNIQUE (source_version_id, activity_name, idempotency_key);
ALTER TABLE context.activity_execution ADD CONSTRAINT activity_execution_workflow_id_check CHECK ((length(btrim(workflow_id)) > 0));
ALTER TABLE context.activity_receipt ADD CONSTRAINT activity_receipt_activity_execution_id_attempt_key UNIQUE (activity_execution_id, attempt);
ALTER TABLE context.activity_receipt ADD CONSTRAINT activity_receipt_attempt_check CHECK ((attempt > 0));
ALTER TABLE context.activity_receipt ADD CONSTRAINT activity_receipt_check CHECK ((((status = 'success'::text) AND (completed_at IS NOT NULL) AND (result_ref IS NOT NULL) AND (error_detail IS NULL) AND (not_applicable_reason IS NULL)) OR ((status = 'failed'::text) AND (completed_at IS NOT NULL) AND (result_ref IS NULL) AND (error_detail IS NOT NULL) AND (not_applicable_reason IS NULL)) OR ((status = 'not_applicable'::text) AND (completed_at IS NOT NULL) AND (result_ref IS NULL) AND (error_detail IS NULL) AND (not_applicable_reason IS NOT NULL))));
ALTER TABLE context.activity_receipt ADD CONSTRAINT activity_receipt_error_detail_check CHECK (((error_detail IS NULL) OR (jsonb_typeof(error_detail) = 'object'::text)));
ALTER TABLE context.activity_receipt ADD CONSTRAINT activity_receipt_not_applicable_reason_check CHECK (((not_applicable_reason IS NULL) OR (length(btrim(not_applicable_reason)) > 0)));
ALTER TABLE context.activity_receipt ADD CONSTRAINT activity_receipt_pkey PRIMARY KEY (id);
ALTER TABLE context.activity_receipt ADD CONSTRAINT activity_receipt_result_ref_check CHECK (((result_ref IS NULL) OR (jsonb_typeof(result_ref) = 'object'::text)));
ALTER TABLE context.activity_receipt ADD CONSTRAINT activity_receipt_status_check CHECK ((status = ANY (ARRAY['success'::text, 'failed'::text, 'not_applicable'::text])));
ALTER TABLE context.first_party_thread_message_relative_time_anchor ADD CONSTRAINT first_party_thread_message_relative_time_anchor_link_role_check CHECK ((link_role = ANY (ARRAY['primary_fallback'::text, 'lower_bound'::text, 'upper_bound'::text, 'sequence_context'::text])));
ALTER TABLE context.first_party_thread_message_relative_time_anchor ADD CONSTRAINT first_party_thread_message_relative_time_anchor_pkey PRIMARY KEY (anchor_id);
ALTER TABLE context.first_party_thread_source_relative_time_anchor ADD CONSTRAINT first_party_thread_source_relati_thread_source_id_anchor_id_key UNIQUE (thread_source_id, anchor_id);
ALTER TABLE context.first_party_thread_source_relative_time_anchor ADD CONSTRAINT first_party_thread_source_relative_time_anchor_link_role_check CHECK ((link_role = ANY (ARRAY['primary_fallback'::text, 'lower_bound'::text, 'upper_bound'::text, 'sequence_context'::text])));
ALTER TABLE context.first_party_thread_source_relative_time_anchor ADD CONSTRAINT first_party_thread_source_relative_time_anchor_pkey PRIMARY KEY (anchor_id);
ALTER TABLE context.first_party_thread_version_relative_time_anchor ADD CONSTRAINT first_party_thread_version_rela_thread_version_id_anchor_id_key UNIQUE (thread_version_id, anchor_id);
ALTER TABLE context.first_party_thread_version_relative_time_anchor ADD CONSTRAINT first_party_thread_version_relative_time_anchor_link_role_check CHECK ((link_role = ANY (ARRAY['primary_fallback'::text, 'lower_bound'::text, 'upper_bound'::text, 'sequence_context'::text])));
ALTER TABLE context.first_party_thread_version_relative_time_anchor ADD CONSTRAINT first_party_thread_version_relative_time_anchor_pkey PRIMARY KEY (anchor_id);
ALTER TABLE context.hash_batch ADD CONSTRAINT hash_batch_activity_execution_id_attempt_key UNIQUE (activity_execution_id, attempt);
ALTER TABLE context.hash_batch ADD CONSTRAINT hash_batch_attempt_check CHECK ((attempt > 0));
ALTER TABLE context.hash_batch ADD CONSTRAINT hash_batch_check1 CHECK ((((status = 'open'::text) AND (member_count IS NULL) AND (result_ref IS NULL) AND (activity_receipt_id IS NULL) AND (completed_at IS NULL)) OR ((status = 'completed'::text) AND (member_count IS NOT NULL) AND (member_count > 0) AND (result_ref IS NOT NULL) AND (activity_receipt_id IS NOT NULL) AND (completed_at IS NOT NULL)) OR ((status = 'aborted'::text) AND (member_count IS NULL) AND (result_ref IS NULL) AND (activity_receipt_id IS NULL) AND (completed_at IS NOT NULL))));
ALTER TABLE context.hash_batch ADD CONSTRAINT hash_batch_context_kind_check CHECK ((hash_kind = ANY (ARRAY['context_source_fingerprint'::text, 'context_raw_record_fingerprint'::text, 'context_raw_generation_fingerprint'::text, 'normalized_record_digest'::text, 'normalized_generation_manifest_digest'::text])));
ALTER TABLE context.hash_batch ADD CONSTRAINT hash_batch_context_subject_check CHECK ((((hash_kind = 'context_source_fingerprint'::text) AND (raw_generation_id IS NULL) AND (normalized_generation_id IS NULL)) OR ((hash_kind = ANY (ARRAY['context_raw_record_fingerprint'::text, 'context_raw_generation_fingerprint'::text])) AND (raw_generation_id IS NOT NULL) AND (normalized_generation_id IS NULL)) OR ((hash_kind = ANY (ARRAY['normalized_record_digest'::text, 'normalized_generation_manifest_digest'::text])) AND (raw_generation_id IS NULL) AND (normalized_generation_id IS NOT NULL))));
ALTER TABLE context.hash_batch ADD CONSTRAINT hash_batch_pkey PRIMARY KEY (id);
ALTER TABLE context.hash_batch ADD CONSTRAINT hash_batch_result_ref_check CHECK (((result_ref IS NULL) OR (jsonb_typeof(result_ref) = 'object'::text)));
ALTER TABLE context.hash_batch ADD CONSTRAINT hash_batch_status_check CHECK ((status = ANY (ARRAY['open'::text, 'completed'::text, 'aborted'::text])));
ALTER TABLE context.hash_batch_member ADD CONSTRAINT hash_batch_member_check CHECK ((num_nonnulls(source_version_id, raw_record_id, normalized_record_id) = 1));
ALTER TABLE context.hash_batch_member ADD CONSTRAINT hash_batch_member_construction_check CHECK ((length(btrim(construction)) > 0));
ALTER TABLE context.hash_batch_member ADD CONSTRAINT hash_batch_member_digest_check CHECK ((octet_length(digest) = 32));
ALTER TABLE context.hash_batch_member ADD CONSTRAINT hash_batch_member_ordinal_check CHECK ((ordinal >= 0));
ALTER TABLE context.hash_batch_member ADD CONSTRAINT hash_batch_member_pkey PRIMARY KEY (hash_batch_id, ordinal);
ALTER TABLE context.hash_manifest ADD CONSTRAINT hash_manifest_check1 CHECK ((((status = 'open'::text) AND (member_count IS NULL) AND (sealed_hash_receipt_id IS NULL) AND (sealed_at IS NULL)) OR ((status = 'sealed'::text) AND (member_count IS NOT NULL) AND (member_count > 0) AND (sealed_hash_receipt_id IS NOT NULL) AND (sealed_at IS NOT NULL))));
ALTER TABLE context.hash_manifest ADD CONSTRAINT hash_manifest_context_kind_check CHECK ((hash_kind = ANY (ARRAY['context_raw_generation_fingerprint'::text, 'normalized_generation_manifest_digest'::text])));
ALTER TABLE context.hash_manifest ADD CONSTRAINT hash_manifest_context_subject_check CHECK ((((hash_kind = 'context_raw_generation_fingerprint'::text) AND (raw_generation_id IS NOT NULL) AND (normalized_generation_id IS NULL)) OR ((hash_kind = 'normalized_generation_manifest_digest'::text) AND (raw_generation_id IS NULL) AND (normalized_generation_id IS NOT NULL))));
ALTER TABLE context.hash_manifest ADD CONSTRAINT hash_manifest_id_hash_kind_key UNIQUE (id, hash_kind);
ALTER TABLE context.hash_manifest ADD CONSTRAINT hash_manifest_pkey PRIMARY KEY (id);
ALTER TABLE context.hash_manifest ADD CONSTRAINT hash_manifest_status_check CHECK ((status = ANY (ARRAY['open'::text, 'sealed'::text])));
ALTER TABLE context.hash_manifest_member ADD CONSTRAINT hash_manifest_member_check CHECK (((raw_record_id IS NOT NULL) <> (normalized_record_id IS NOT NULL)));
ALTER TABLE context.hash_manifest_member ADD CONSTRAINT hash_manifest_member_member_canon_check CHECK ((length(btrim(member_canon)) > 0));
ALTER TABLE context.hash_manifest_member ADD CONSTRAINT hash_manifest_member_member_digest_check CHECK ((octet_length(member_digest) = 32));
ALTER TABLE context.hash_manifest_member ADD CONSTRAINT hash_manifest_member_ordinal_check CHECK ((ordinal >= 0));
ALTER TABLE context.hash_manifest_member ADD CONSTRAINT hash_manifest_member_pkey PRIMARY KEY (hash_manifest_id, ordinal);
ALTER TABLE context.hash_receipt ADD CONSTRAINT hash_receipt_algorithm_check CHECK ((algorithm = 'sha256'::text));
ALTER TABLE context.hash_receipt ADD CONSTRAINT hash_receipt_computed_by_check CHECK ((length(btrim(computed_by)) > 0));
ALTER TABLE context.hash_receipt ADD CONSTRAINT hash_receipt_context_canon_check CHECK ((((hash_kind = 'context_source_fingerprint'::text) AND (construction = 'context-source-fingerprint-v1'::text)) OR ((hash_kind = 'context_raw_record_fingerprint'::text) AND (construction = ANY (ARRAY['context-rawrecord-fingerprint-v1'::text, 'context-rawspan-fingerprint-v1'::text]))) OR ((hash_kind = 'context_raw_generation_fingerprint'::text) AND (construction = 'context-rawgen-fingerprint-chain-v1'::text)) OR ((hash_kind = 'normalized_record_digest'::text) AND (construction = 'normalized-record-postgresql18-jsonb-text-utf8-sha256-v1'::text)) OR ((hash_kind = 'normalized_generation_manifest_digest'::text) AND (construction = 'normalized-generation-ordered-digests-lengthframed-sha256-v1'::text))));
ALTER TABLE context.hash_receipt ADD CONSTRAINT hash_receipt_context_kind_check CHECK ((hash_kind = ANY (ARRAY['context_source_fingerprint'::text, 'context_raw_record_fingerprint'::text, 'context_raw_generation_fingerprint'::text, 'normalized_record_digest'::text, 'normalized_generation_manifest_digest'::text])));
ALTER TABLE context.hash_receipt ADD CONSTRAINT hash_receipt_context_subject_check CHECK ((((hash_kind = 'context_source_fingerprint'::text) AND (source_version_id IS NOT NULL) AND (raw_record_id IS NULL) AND (raw_generation_id IS NULL) AND (normalized_record_id IS NULL) AND (normalized_generation_id IS NULL) AND (hash_manifest_id IS NULL)) OR ((hash_kind = 'context_raw_record_fingerprint'::text) AND (source_version_id IS NULL) AND (raw_record_id IS NOT NULL) AND (raw_generation_id IS NULL) AND (normalized_record_id IS NULL) AND (normalized_generation_id IS NULL) AND (hash_manifest_id IS NULL)) OR ((hash_kind = 'context_raw_generation_fingerprint'::text) AND (source_version_id IS NULL) AND (raw_record_id IS NULL) AND (raw_generation_id IS NOT NULL) AND (normalized_record_id IS NULL) AND (normalized_generation_id IS NULL) AND (hash_manifest_id IS NOT NULL)) OR ((hash_kind = 'normalized_record_digest'::text) AND (source_version_id IS NULL) AND (raw_record_id IS NULL) AND (raw_generation_id IS NULL) AND (normalized_record_id IS NOT NULL) AND (normalized_generation_id IS NULL) AND (hash_manifest_id IS NULL)) OR ((hash_kind = 'normalized_generation_manifest_digest'::text) AND (source_version_id IS NULL) AND (raw_record_id IS NULL) AND (raw_generation_id IS NULL) AND (normalized_record_id IS NULL) AND (normalized_generation_id IS NOT NULL) AND (hash_manifest_id IS NOT NULL))));
ALTER TABLE context.hash_receipt ADD CONSTRAINT hash_receipt_digest_check CHECK ((octet_length(digest) = 32));
ALTER TABLE context.hash_receipt ADD CONSTRAINT hash_receipt_pkey PRIMARY KEY (id);
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_derivation_role_check CHECK ((derivation_role = ANY (ARRAY['primary_source'::text, 'supplementary'::text, 'merge_source'::text, 'attachment_source'::text, 'correction_source'::text])));
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_field_map_check CHECK ((jsonb_typeof(field_map) = 'array'::text));
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_normalized_record_id_raw_record_id_de_key UNIQUE (normalized_record_id, raw_record_id, derivation_role);
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_normalizer_id_check CHECK ((length(btrim(normalizer_id)) > 0));
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_normalizer_version_check CHECK ((length(btrim(normalizer_version)) > 0));
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_pkey PRIMARY KEY (id);
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_source_span_length_check CHECK (((source_span_length IS NULL) OR (source_span_length >= 0)));
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_source_span_offset_check CHECK (((source_span_offset IS NULL) OR (source_span_offset >= 0)));
ALTER TABLE context.normalized_generation ADD CONSTRAINT normalized_generation_check CHECK ((((status = 'open'::text) AND (sealed_at IS NULL) AND (sealed_by IS NULL) AND (published_at IS NULL)) OR ((status = 'sealed'::text) AND (sealed_at IS NOT NULL) AND (sealed_by IS NOT NULL) AND (published_at IS NULL)) OR ((status = 'published'::text) AND (sealed_at IS NOT NULL) AND (sealed_by IS NOT NULL) AND (published_at IS NOT NULL))));
ALTER TABLE context.normalized_generation ADD CONSTRAINT normalized_generation_generation_ordinal_check CHECK ((generation_ordinal > 0));
ALTER TABLE context.normalized_generation ADD CONSTRAINT normalized_generation_id_raw_generation_id_key UNIQUE (id, raw_generation_id);
ALTER TABLE context.normalized_generation ADD CONSTRAINT normalized_generation_id_source_version_id_key UNIQUE (id, source_version_id);
ALTER TABLE context.normalized_generation ADD CONSTRAINT normalized_generation_normalizer_id_check CHECK ((length(btrim(normalizer_id)) > 0));
ALTER TABLE context.normalized_generation ADD CONSTRAINT normalized_generation_normalizer_version_check CHECK ((length(btrim(normalizer_version)) > 0));
ALTER TABLE context.normalized_generation ADD CONSTRAINT normalized_generation_pkey PRIMARY KEY (id);
ALTER TABLE context.normalized_generation ADD CONSTRAINT normalized_generation_source_version_id_generation_ordinal_key UNIQUE (source_version_id, generation_ordinal);
ALTER TABLE context.normalized_generation ADD CONSTRAINT normalized_generation_status_check CHECK ((status = ANY (ARRAY['open'::text, 'sealed'::text, 'published'::text])));
ALTER TABLE context.normalized_generation_publication ADD CONSTRAINT normalized_generation_publication_idempotency_key_check CHECK ((length(btrim(idempotency_key)) > 0));
ALTER TABLE context.normalized_generation_publication ADD CONSTRAINT normalized_generation_publication_idempotency_key_key UNIQUE (idempotency_key);
ALTER TABLE context.normalized_generation_publication ADD CONSTRAINT normalized_generation_publication_normalized_generation_id_key UNIQUE (normalized_generation_id);
ALTER TABLE context.normalized_generation_publication ADD CONSTRAINT normalized_generation_publication_pkey PRIMARY KEY (id);
ALTER TABLE context.normalized_generation_publication ADD CONSTRAINT normalized_generation_publication_publication_ref_check CHECK ((jsonb_typeof(publication_ref) = 'object'::text));
ALTER TABLE context.normalized_record_identity ADD CONSTRAINT normalized_record_identity_canonicalization_check CHECK ((canonicalization = 'normalized-record-postgresql18-jsonb-text-utf8-sha256-v1'::text));
ALTER TABLE context.normalized_record_identity ADD CONSTRAINT normalized_record_identity_check CHECK ((canonical_bytes = convert_to((normalized_payload)::text, 'UTF8'::name)));
ALTER TABLE context.normalized_record_identity ADD CONSTRAINT normalized_record_identity_id_normalized_generation_id_key UNIQUE (id, normalized_generation_id);
ALTER TABLE context.normalized_record_identity ADD CONSTRAINT normalized_record_identity_id_source_version_id_key UNIQUE (id, source_version_id);
ALTER TABLE context.normalized_record_identity ADD CONSTRAINT normalized_record_identity_normalized_generation_id_record__key UNIQUE (normalized_generation_id, record_ordinal);
ALTER TABLE context.normalized_record_identity ADD CONSTRAINT normalized_record_identity_normalized_payload_check CHECK ((jsonb_typeof(normalized_payload) = 'object'::text));
ALTER TABLE context.normalized_record_identity ADD CONSTRAINT normalized_record_identity_pkey PRIMARY KEY (id);
ALTER TABLE context.normalized_record_identity ADD CONSTRAINT normalized_record_identity_record_ordinal_check CHECK ((record_ordinal >= 0));
ALTER TABLE context.normalized_record_identity ADD CONSTRAINT normalized_record_identity_record_type_check CHECK ((record_type = ANY (ARRAY['message'::text, 'call'::text, 'event'::text, 'media'::text, 'document'::text, 'other'::text])));
ALTER TABLE context.normalized_record_range_locator ADD CONSTRAINT normalized_record_range_locator_pkey PRIMARY KEY (source_range_locator_id);
ALTER TABLE context.raw_format_registry ADD CONSTRAINT raw_format_registry_format_id_check CHECK ((format_id ~ '^[a-z][a-z0-9_]{0,58}$'::text));
ALTER TABLE context.raw_format_registry ADD CONSTRAINT raw_format_registry_pkey PRIMARY KEY (format_id);
ALTER TABLE context.raw_format_registry ADD CONSTRAINT raw_format_registry_subtype_relation_key UNIQUE (subtype_relation);
ALTER TABLE context.raw_generation ADD CONSTRAINT raw_generation_check CHECK ((((status = 'open'::text) AND (sealed_at IS NULL) AND (sealed_by IS NULL)) OR ((status = 'sealed'::text) AND (sealed_at IS NOT NULL) AND (sealed_by IS NOT NULL))));
ALTER TABLE context.raw_generation ADD CONSTRAINT raw_generation_format_id_check CHECK ((length(btrim(format_id)) > 0));
ALTER TABLE context.raw_generation ADD CONSTRAINT raw_generation_generation_ordinal_check CHECK ((generation_ordinal > 0));
ALTER TABLE context.raw_generation ADD CONSTRAINT raw_generation_id_format_id_key UNIQUE (id, format_id);
ALTER TABLE context.raw_generation ADD CONSTRAINT raw_generation_id_source_version_id_key UNIQUE (id, source_version_id);
ALTER TABLE context.raw_generation ADD CONSTRAINT raw_generation_parser_id_check CHECK ((length(btrim(parser_id)) > 0));
ALTER TABLE context.raw_generation ADD CONSTRAINT raw_generation_parser_version_check CHECK ((length(btrim(parser_version)) > 0));
ALTER TABLE context.raw_generation ADD CONSTRAINT raw_generation_pkey PRIMARY KEY (id);
ALTER TABLE context.raw_generation ADD CONSTRAINT raw_generation_source_version_id_generation_ordinal_key UNIQUE (source_version_id, generation_ordinal);
ALTER TABLE context.raw_generation ADD CONSTRAINT raw_generation_status_check CHECK ((status = ANY (ARRAY['open'::text, 'sealed'::text])));
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_context_fingerprint_canon_check CHECK ((raw_hash_construction = ANY (ARRAY['context-rawrecord-fingerprint-v1'::text, 'context-rawspan-fingerprint-v1'::text])));
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_context_span_canon_check CHECK (((record_status <> ALL (ARRAY['envelope'::text, 'unparsed'::text])) OR (raw_hash_construction = 'context-rawspan-fingerprint-v1'::text)));
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_check CHECK (((record_status = 'parsed'::text) OR (status_reason IS NOT NULL)));
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_check2 CHECK ((((stored_bytes IS NOT NULL) AND (locator_object_id IS NULL) AND (byte_offset IS NULL) AND (byte_length IS NULL)) OR ((stored_bytes IS NULL) AND (locator_object_id IS NOT NULL) AND (byte_offset IS NOT NULL) AND (byte_offset >= 0) AND (byte_length IS NOT NULL) AND (byte_length >= 0))));
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_id_raw_generation_id_key UNIQUE (id, raw_generation_id);
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_id_source_version_id_key UNIQUE (id, source_version_id);
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_native_metadata_check CHECK ((jsonb_typeof(native_metadata) = 'object'::text));
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_pkey PRIMARY KEY (id);
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_raw_generation_id_record_ordinal_key UNIQUE (raw_generation_id, record_ordinal);
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_record_ordinal_check CHECK ((record_ordinal >= 0));
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_record_status_check CHECK ((record_status = ANY (ARRAY['parsed'::text, 'rejected'::text, 'malformed'::text, 'unknown'::text, 'unparsed'::text, 'envelope'::text])));
ALTER TABLE context.raw_record_range_locator ADD CONSTRAINT raw_record_range_locator_pkey PRIMARY KEY (source_range_locator_id);
ALTER TABLE context.reconciliation_receipt ADD CONSTRAINT reconciliation_context_raw_source_check CHECK (((reconciliation_kind <> 'raw_source_verification'::text) OR ((expected ? 'context_raw_generation_fingerprint'::text) AND (expected ? 'context_source_fingerprint'::text) AND (observed ? 'context_raw_generation_fingerprint'::text) AND (observed ? 'context_source_fingerprint'::text) AND ((expected ->> 'verification_mode'::text) = 'retained_bytes_recomputation'::text) AND ((observed ->> 'verification_mode'::text) = 'retained_bytes_recomputation'::text) AND ((status <> 'success'::text) OR ((expected -> 'context_raw_generation_fingerprint'::text) = (observed -> 'context_raw_generation_fingerprint'::text))) AND ((status <> 'success'::text) OR ((expected -> 'context_source_fingerprint'::text) = (observed -> 'context_source_fingerprint'::text))))));
ALTER TABLE context.reconciliation_receipt ADD CONSTRAINT reconciliation_receipt_check CHECK ((((reconciliation_kind = ANY (ARRAY['record_accounting'::text, 'byte_coverage'::text, 'raw_source_verification'::text])) AND (raw_generation_id IS NOT NULL) AND (normalized_generation_id IS NULL)) OR ((reconciliation_kind = ANY (ARRAY['raw_lineage_validation'::text, 'normalized_generation_verification'::text])) AND (raw_generation_id IS NULL) AND (normalized_generation_id IS NOT NULL))));
ALTER TABLE context.reconciliation_receipt ADD CONSTRAINT reconciliation_receipt_check1 CHECK ((((status = 'success'::text) AND (discrepancies = '[]'::jsonb)) OR (status = ANY (ARRAY['failed'::text, 'not_applicable'::text]))));
ALTER TABLE context.reconciliation_receipt ADD CONSTRAINT reconciliation_receipt_check2 CHECK (((status <> 'not_applicable'::text) OR (discrepancies = '[]'::jsonb)));
ALTER TABLE context.reconciliation_receipt ADD CONSTRAINT reconciliation_receipt_check4 CHECK (((reconciliation_kind <> 'normalized_generation_verification'::text) OR ((expected ? 'normalized_generation_manifest_digest'::text) AND (observed ? 'normalized_generation_manifest_digest'::text) AND ((expected ->> 'verification_mode'::text) = 'independent_recomputation'::text) AND ((observed ->> 'verification_mode'::text) = 'independent_recomputation'::text) AND ((status <> 'success'::text) OR ((expected -> 'normalized_generation_manifest_digest'::text) = (observed -> 'normalized_generation_manifest_digest'::text))))));
ALTER TABLE context.reconciliation_receipt ADD CONSTRAINT reconciliation_receipt_discrepancies_check CHECK ((jsonb_typeof(discrepancies) = 'array'::text));
ALTER TABLE context.reconciliation_receipt ADD CONSTRAINT reconciliation_receipt_expected_check CHECK ((jsonb_typeof(expected) = 'object'::text));
ALTER TABLE context.reconciliation_receipt ADD CONSTRAINT reconciliation_receipt_observed_check CHECK ((jsonb_typeof(observed) = 'object'::text));
ALTER TABLE context.reconciliation_receipt ADD CONSTRAINT reconciliation_receipt_pkey PRIMARY KEY (id);
ALTER TABLE context.reconciliation_receipt ADD CONSTRAINT reconciliation_receipt_reconciliation_kind_check CHECK ((reconciliation_kind = ANY (ARRAY['record_accounting'::text, 'byte_coverage'::text, 'raw_source_verification'::text, 'raw_lineage_validation'::text, 'normalized_generation_verification'::text])));
ALTER TABLE context.reconciliation_receipt ADD CONSTRAINT reconciliation_receipt_status_check CHECK ((status = ANY (ARRAY['success'::text, 'failed'::text, 'not_applicable'::text])));
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_anchor_key_version_ordinal_key UNIQUE (anchor_key, version_ordinal);
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_check CHECK (((upper_bound_at IS NULL) OR (lower_bound_at IS NULL) OR (upper_bound_at >= lower_bound_at)));
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_check1 CHECK (((contextual_sequence_ordinal IS NULL) OR (contextual_sequence_key IS NOT NULL)));
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_check2 CHECK (((lower_bound_at IS NOT NULL) OR (upper_bound_at IS NOT NULL) OR (last_known_before_anchor_id IS NOT NULL) OR (first_known_after_anchor_id IS NOT NULL) OR (contextual_sequence_key IS NOT NULL)));
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_check3 CHECK (((last_known_before_anchor_id IS DISTINCT FROM id) AND (first_known_after_anchor_id IS DISTINCT FROM id)));
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_check4 CHECK (((review_state <> 'approved'::text) OR ((reviewed_by IS NOT NULL) AND (reviewed_at IS NOT NULL))));
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_confidence_check CHECK (((confidence >= (0)::double precision) AND (confidence <= (1)::double precision)));
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_id_anchor_key_key UNIQUE (id, anchor_key);
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_metadata_basis_check CHECK ((length(btrim(metadata_basis)) > 0));
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_pkey PRIMARY KEY (id);
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_placement_kind_check CHECK ((placement_kind = ANY (ARRAY['before'::text, 'after'::text, 'between'::text, 'sequence_only'::text, 'metadata_approximation'::text])));
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_presentation_payload_check CHECK ((jsonb_typeof(presentation_payload) = 'object'::text));
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_provenance_digest_check CHECK ((octet_length(provenance_digest) = 32));
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_raw_metadata_check CHECK ((jsonb_typeof(raw_metadata) = 'object'::text));
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_review_state_check CHECK ((review_state = ANY (ARRAY['proposed'::text, 'approved'::text, 'rejected'::text, 'superseded'::text])));
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_version_ordinal_check CHECK ((version_ordinal > 0));
ALTER TABLE context.repair_assessment ADD CONSTRAINT repair_assessment_activity_receipt_id_key UNIQUE (activity_receipt_id);
ALTER TABLE context.repair_assessment ADD CONSTRAINT repair_assessment_declared_format_check CHECK ((length(btrim(declared_format)) > 0));
ALTER TABLE context.repair_assessment ADD CONSTRAINT repair_assessment_detection_check CHECK (((jsonb_typeof(detection) = 'object'::text) AND (octet_length((detection)::text) <= 2097152)));
ALTER TABLE context.repair_assessment ADD CONSTRAINT repair_assessment_pkey PRIMARY KEY (id);
ALTER TABLE context.repair_assessment ADD CONSTRAINT repair_assessment_preview_check CHECK (((jsonb_typeof(preview) = 'object'::text) AND (octet_length((preview)::text) <= 2097152)));
ALTER TABLE context.repair_assessment ADD CONSTRAINT repair_assessment_source_version_id_original_object_id_acti_key UNIQUE (source_version_id, original_object_id, activity_receipt_id);
ALTER TABLE context.repair_decision ADD CONSTRAINT repair_decision_actor_ref_check CHECK ((length(btrim(actor_ref)) > 0));
ALTER TABLE context.repair_decision ADD CONSTRAINT repair_decision_check CHECK (((approved AND apply_repair AND (tool_id = ANY (ARRAY['repair.write-derived'::text, 'repair.pdf-derived'::text]))) OR (approved AND (NOT apply_repair) AND (tool_id IS NULL) AND (tool_payload = '{}'::jsonb)) OR ((NOT approved) AND (NOT apply_repair) AND (tool_id IS NULL) AND (tool_payload = '{}'::jsonb))));
ALTER TABLE context.repair_decision ADD CONSTRAINT repair_decision_decision_idempotency_key_check CHECK ((length(btrim(decision_idempotency_key)) > 0));
ALTER TABLE context.repair_decision ADD CONSTRAINT repair_decision_decision_idempotency_key_key UNIQUE (decision_idempotency_key);
ALTER TABLE context.repair_decision ADD CONSTRAINT repair_decision_id_source_version_id_assessment_id_key UNIQUE (id, source_version_id, assessment_id);
ALTER TABLE context.repair_decision ADD CONSTRAINT repair_decision_pkey PRIMARY KEY (id);
ALTER TABLE context.repair_decision ADD CONSTRAINT repair_decision_tool_payload_check CHECK (((jsonb_typeof(tool_payload) = 'object'::text) AND (octet_length((tool_payload)::text) <= 65536)));
ALTER TABLE context.repair_resolution ADD CONSTRAINT repair_resolution_activity_receipt_id_key UNIQUE (activity_receipt_id);
ALTER TABLE context.repair_resolution ADD CONSTRAINT repair_resolution_actor_ref_check CHECK ((length(btrim(actor_ref)) > 0));
ALTER TABLE context.repair_resolution ADD CONSTRAINT repair_resolution_check CHECK (((applied AND (tool_id = ANY (ARRAY['repair.write-derived'::text, 'repair.pdf-derived'::text])) AND (active_object_id <> original_object_id)) OR ((NOT applied) AND (tool_id IS NULL) AND (tool_result = '{}'::jsonb) AND (active_object_id = original_object_id))));
ALTER TABLE context.repair_resolution ADD CONSTRAINT repair_resolution_decision_id_key UNIQUE (decision_id);
ALTER TABLE context.repair_resolution ADD CONSTRAINT repair_resolution_pkey PRIMARY KEY (id);
ALTER TABLE context.repair_resolution ADD CONSTRAINT repair_resolution_tool_result_check CHECK (((jsonb_typeof(tool_result) = 'object'::text) AND (octet_length((tool_result)::text) <= 2097152)));
ALTER TABLE context.retained_object ADD CONSTRAINT retained_object_byte_length_check CHECK ((byte_length >= 0));
ALTER TABLE context.retained_object ADD CONSTRAINT retained_object_check CHECK ((((storage_class = 'inline'::text) AND (inline_bytes IS NOT NULL) AND (octet_length(inline_bytes) = byte_length) AND (digest(inline_bytes, 'sha256'::text) = content_sha256)) OR ((storage_class <> 'inline'::text) AND (inline_bytes IS NULL))));
ALTER TABLE context.retained_object ADD CONSTRAINT retained_object_content_sha256_byte_length_key UNIQUE (content_sha256, byte_length);
ALTER TABLE context.retained_object ADD CONSTRAINT retained_object_content_sha256_check CHECK ((octet_length(content_sha256) = 32));
ALTER TABLE context.retained_object ADD CONSTRAINT retained_object_pkey PRIMARY KEY (id);
ALTER TABLE context.retained_object ADD CONSTRAINT retained_object_storage_class_check CHECK ((storage_class = ANY (ARRAY['immutable_object_store'::text, 'filesystem'::text, 'inline'::text])));
ALTER TABLE context.retained_object ADD CONSTRAINT retained_object_storage_class_object_uri_key UNIQUE (storage_class, object_uri);
ALTER TABLE context.source ADD CONSTRAINT source_pkey PRIMARY KEY (id);
ALTER TABLE context.source ADD CONSTRAINT source_provenance_class_check CHECK ((provenance_class = ANY (ARRAY['first_party_authored'::text, 'acquired_third_party'::text, 'system_generated'::text, 'unknown'::text])));
ALTER TABLE context.source ADD CONSTRAINT source_source_key_check CHECK ((length(btrim(source_key)) > 0));
ALTER TABLE context.source ADD CONSTRAINT source_source_key_key UNIQUE (source_key);
ALTER TABLE context.source_metadata ADD CONSTRAINT source_metadata_extractor_id_check CHECK ((length(btrim(extractor_id)) > 0));
ALTER TABLE context.source_metadata ADD CONSTRAINT source_metadata_id_source_version_id_key UNIQUE (id, source_version_id);
ALTER TABLE context.source_metadata ADD CONSTRAINT source_metadata_metadata_check CHECK ((jsonb_typeof(metadata) = 'object'::text));
ALTER TABLE context.source_metadata ADD CONSTRAINT source_metadata_metadata_class_check CHECK ((metadata_class = ANY (ARRAY['filesystem'::text, 'embedded'::text, 'container'::text, 'media_tool'::text, 'record_native'::text])));
ALTER TABLE context.source_metadata ADD CONSTRAINT source_metadata_pkey PRIMARY KEY (id);
ALTER TABLE context.source_object_range_locator ADD CONSTRAINT source_object_range_locator_pkey PRIMARY KEY (source_range_locator_id);
ALTER TABLE context.source_range_locator ADD CONSTRAINT source_range_locator_check CHECK ((range_end > range_start));
ALTER TABLE context.source_range_locator ADD CONSTRAINT source_range_locator_coordinate_system_check CHECK ((coordinate_system = ANY (ARRAY['utf8_bytes'::text, 'unicode_codepoints'::text])));
ALTER TABLE context.source_range_locator ADD CONSTRAINT source_range_locator_exact_slice_sha256_check CHECK ((octet_length(exact_slice_sha256) = 32));
ALTER TABLE context.source_range_locator ADD CONSTRAINT source_range_locator_id_source_version_id_key UNIQUE (id, source_version_id);
ALTER TABLE context.source_range_locator ADD CONSTRAINT source_range_locator_locator_projection_check CHECK ((jsonb_typeof(locator_projection) = 'object'::text));
ALTER TABLE context.source_range_locator ADD CONSTRAINT source_range_locator_pkey PRIMARY KEY (id);
ALTER TABLE context.source_range_locator ADD CONSTRAINT source_range_locator_range_start_check CHECK ((range_start >= 0));
ALTER TABLE context.source_version ADD CONSTRAINT source_version_check CHECK ((((status = 'registered'::text) AND (original_object_id IS NULL)) OR ((status = 'retained'::text) AND (original_object_id IS NOT NULL))));
ALTER TABLE context.source_version ADD CONSTRAINT source_version_declared_format_check CHECK ((length(btrim(declared_format)) > 0));
ALTER TABLE context.source_version ADD CONSTRAINT source_version_id_original_object_id_key UNIQUE (id, original_object_id);
ALTER TABLE context.source_version ADD CONSTRAINT source_version_matter_case_pair_check CHECK (((matter_id IS NULL) = (court_case_id IS NULL)));
ALTER TABLE context.source_version ADD CONSTRAINT source_version_pkey PRIMARY KEY (id);
ALTER TABLE context.source_version ADD CONSTRAINT source_version_source_id_submission_idempotency_key_key UNIQUE (source_id, submission_idempotency_key);
ALTER TABLE context.source_version ADD CONSTRAINT source_version_source_id_version_ordinal_key UNIQUE (source_id, version_ordinal);
ALTER TABLE context.source_version ADD CONSTRAINT source_version_status_check CHECK ((status = ANY (ARRAY['registered'::text, 'retained'::text])));
ALTER TABLE context.source_version ADD CONSTRAINT source_version_submission_idempotency_key_check CHECK ((length(btrim(submission_idempotency_key)) > 0));
ALTER TABLE context.source_version ADD CONSTRAINT source_version_version_ordinal_check CHECK ((version_ordinal > 0));
ALTER TABLE context.source_version ADD CONSTRAINT source_version_workflow_id_check CHECK ((length(btrim(workflow_id)) > 0));
ALTER TABLE context.source_version ADD CONSTRAINT source_version_workflow_id_key UNIQUE (workflow_id);
ALTER TABLE context.source_version_object ADD CONSTRAINT source_version_object_check CHECK (((object_role = 'original'::text) = (parent_object_id IS NULL)));
ALTER TABLE context.source_version_object ADD CONSTRAINT source_version_object_member_locator_check CHECK ((jsonb_typeof(member_locator) = 'object'::text));
ALTER TABLE context.source_version_object ADD CONSTRAINT source_version_object_object_role_check CHECK ((object_role = ANY (ARRAY['original'::text, 'container_member'::text, 'attachment'::text, 'derived_reference'::text])));
ALTER TABLE context.source_version_object ADD CONSTRAINT source_version_object_pkey PRIMARY KEY (source_version_id, object_id);
ALTER TABLE context.third_party_thread_message_relative_time_anchor ADD CONSTRAINT third_party_thread_message_relative_time_anchor_link_role_check CHECK ((link_role = ANY (ARRAY['primary_fallback'::text, 'lower_bound'::text, 'upper_bound'::text, 'sequence_context'::text])));
ALTER TABLE context.third_party_thread_message_relative_time_anchor ADD CONSTRAINT third_party_thread_message_relative_time_anchor_pkey PRIMARY KEY (anchor_id);
ALTER TABLE context.third_party_thread_source_relative_time_anchor ADD CONSTRAINT third_party_thread_source_relati_thread_source_id_anchor_id_key UNIQUE (thread_source_id, anchor_id);
ALTER TABLE context.third_party_thread_source_relative_time_anchor ADD CONSTRAINT third_party_thread_source_relative_time_anchor_link_role_check CHECK ((link_role = ANY (ARRAY['primary_fallback'::text, 'lower_bound'::text, 'upper_bound'::text, 'sequence_context'::text])));
ALTER TABLE context.third_party_thread_source_relative_time_anchor ADD CONSTRAINT third_party_thread_source_relative_time_anchor_pkey PRIMARY KEY (anchor_id);
ALTER TABLE context.third_party_thread_version_relative_time_anchor ADD CONSTRAINT third_party_thread_version_rela_thread_version_id_anchor_id_key UNIQUE (thread_version_id, anchor_id);
ALTER TABLE context.third_party_thread_version_relative_time_anchor ADD CONSTRAINT third_party_thread_version_relative_time_anchor_link_role_check CHECK ((link_role = ANY (ARRAY['primary_fallback'::text, 'lower_bound'::text, 'upper_bound'::text, 'sequence_context'::text])));
ALTER TABLE context.third_party_thread_version_relative_time_anchor ADD CONSTRAINT third_party_thread_version_relative_time_anchor_pkey PRIMARY KEY (anchor_id);
ALTER TABLE context.uiw_preview_attachment ADD CONSTRAINT uiw_preview_attachment_attachment_id_check CHECK ((length(btrim(attachment_id)) > 0));
ALTER TABLE context.uiw_preview_attachment ADD CONSTRAINT uiw_preview_attachment_byte_length_check CHECK (((byte_length IS NULL) OR (byte_length >= 0)));
ALTER TABLE context.uiw_preview_attachment ADD CONSTRAINT uiw_preview_attachment_pkey PRIMARY KEY (preview_handle, snapshot_seq, attachment_id);
ALTER TABLE context.uiw_preview_attachment ADD CONSTRAINT uiw_preview_attachment_sha256_check CHECK (((sha256 IS NULL) OR (octet_length(sha256) = 32)));
ALTER TABLE context.uiw_preview_attachment ADD CONSTRAINT uiw_preview_attachment_source_locator_ref_check CHECK ((length(btrim(source_locator_ref)) > 0));
ALTER TABLE context.uiw_preview_binding ADD CONSTRAINT uiw_preview_binding_parser_options_ref_check CHECK ((length(btrim(parser_options_ref)) > 0));
ALTER TABLE context.uiw_preview_binding ADD CONSTRAINT uiw_preview_binding_pkey PRIMARY KEY (preview_handle);
ALTER TABLE context.uiw_preview_binding ADD CONSTRAINT uiw_preview_binding_preview_handle_check CHECK ((preview_handle ~ '^[A-Za-z0-9_-]{32,128}$'::text));
ALTER TABLE context.uiw_preview_binding ADD CONSTRAINT uiw_preview_binding_request_id_check CHECK ((length(btrim(request_id)) > 0));
ALTER TABLE context.uiw_preview_binding ADD CONSTRAINT uiw_preview_binding_request_id_key UNIQUE (request_id);
ALTER TABLE context.uiw_preview_binding ADD CONSTRAINT uiw_preview_binding_run_id_check CHECK ((length(btrim(run_id)) > 0));
ALTER TABLE context.uiw_preview_binding ADD CONSTRAINT uiw_preview_binding_source_ref_check CHECK ((length(btrim(source_ref)) > 0));
ALTER TABLE context.uiw_preview_binding ADD CONSTRAINT uiw_preview_binding_workflow_id_check CHECK ((length(btrim(workflow_id)) > 0));
ALTER TABLE context.uiw_preview_decision ADD CONSTRAINT uiw_preview_decision_actor_subject_uid_check CHECK ((length(btrim(actor_subject_uid)) > 0));
ALTER TABLE context.uiw_preview_decision ADD CONSTRAINT uiw_preview_decision_decision_key_check CHECK ((octet_length(decision_key) = 32));
ALTER TABLE context.uiw_preview_decision ADD CONSTRAINT uiw_preview_decision_parser_options_ref_check CHECK ((length(btrim(parser_options_ref)) > 0));
ALTER TABLE context.uiw_preview_decision ADD CONSTRAINT uiw_preview_decision_pkey PRIMARY KEY (id);
ALTER TABLE context.uiw_preview_decision ADD CONSTRAINT uiw_preview_decision_preview_handle_decision_key_key UNIQUE (preview_handle, decision_key);
ALTER TABLE context.uiw_preview_decision ADD CONSTRAINT uiw_preview_decision_reason_check CHECK ((octet_length(reason) <= 4000));
ALTER TABLE context.uiw_preview_decision ADD CONSTRAINT uiw_preview_decision_selection_ref_check CHECK ((length(btrim(selection_ref)) > 0));
ALTER TABLE context.uiw_preview_event ADD CONSTRAINT uiw_preview_event_detail_check CHECK ((octet_length(detail) <= 4000));
ALTER TABLE context.uiw_preview_event ADD CONSTRAINT uiw_preview_event_event_id_check CHECK ((event_id >= 0));
ALTER TABLE context.uiw_preview_event ADD CONSTRAINT uiw_preview_event_event_type_check CHECK ((event_type = ANY (ARRAY['phase_changed'::text, 'receipt_recorded'::text, 'messages_available'::text, 'decision_requested'::text, 'decision_recorded'::text, 'completed'::text, 'failed'::text])));
ALTER TABLE context.uiw_preview_event ADD CONSTRAINT uiw_preview_event_message_count_check CHECK (((message_count IS NULL) OR (message_count >= 0)));
ALTER TABLE context.uiw_preview_event ADD CONSTRAINT uiw_preview_event_phase_check CHECK ((length(btrim(phase)) > 0));
ALTER TABLE context.uiw_preview_event ADD CONSTRAINT uiw_preview_event_pkey PRIMARY KEY (preview_handle, event_id);
ALTER TABLE context.uiw_preview_message ADD CONSTRAINT uiw_preview_message_body_check CHECK ((octet_length(body) <= 4000000));
ALTER TABLE context.uiw_preview_message ADD CONSTRAINT uiw_preview_message_message_id_check CHECK ((length(btrim(message_id)) > 0));
ALTER TABLE context.uiw_preview_message ADD CONSTRAINT uiw_preview_message_ordinal_check CHECK ((ordinal >= 0));
ALTER TABLE context.uiw_preview_message ADD CONSTRAINT uiw_preview_message_participant_ids_check CHECK ((cardinality(participant_ids) <= 64));
ALTER TABLE context.uiw_preview_message ADD CONSTRAINT uiw_preview_message_pkey PRIMARY KEY (preview_handle, snapshot_seq, message_id);
ALTER TABLE context.uiw_preview_message ADD CONSTRAINT uiw_preview_message_preview_handle_snapshot_seq_ordinal_key UNIQUE (preview_handle, snapshot_seq, ordinal);
ALTER TABLE context.uiw_preview_message ADD CONSTRAINT uiw_preview_message_source_locator_ref_check CHECK ((length(btrim(source_locator_ref)) > 0));
ALTER TABLE context.uiw_preview_participant ADD CONSTRAINT uiw_preview_participant_display_name_check CHECK ((length(btrim(display_name)) > 0));
ALTER TABLE context.uiw_preview_participant ADD CONSTRAINT uiw_preview_participant_participant_id_check CHECK ((length(btrim(participant_id)) > 0));
ALTER TABLE context.uiw_preview_participant ADD CONSTRAINT uiw_preview_participant_pkey PRIMARY KEY (preview_handle, snapshot_seq, participant_id);
ALTER TABLE context.uiw_preview_receipt ADD CONSTRAINT uiw_preview_receipt_digest_check CHECK (((digest IS NULL) OR (octet_length(digest) = 32)));
ALTER TABLE context.uiw_preview_receipt ADD CONSTRAINT uiw_preview_receipt_pkey PRIMARY KEY (preview_handle, snapshot_seq, receipt_type);
ALTER TABLE context.uiw_preview_receipt ADD CONSTRAINT uiw_preview_receipt_receipt_ref_check CHECK ((length(btrim(receipt_ref)) > 0));
ALTER TABLE context.uiw_preview_receipt ADD CONSTRAINT uiw_preview_receipt_receipt_type_check CHECK ((receipt_type = ANY (ARRAY['custody'::text, 'parser_selection'::text, 'parser_execution'::text, 'normalization'::text, 'storage'::text, 'completeness'::text])));
ALTER TABLE context.uiw_preview_receipt ADD CONSTRAINT uiw_preview_receipt_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'running'::text, 'completed'::text, 'failed'::text, 'skipped'::text])));
ALTER TABLE context.uiw_preview_snapshot ADD CONSTRAINT uiw_preview_snapshot_check CHECK ((((parser_id IS NULL) = (parser_version IS NULL)) AND ((parser_id IS NULL) = (parser_config_digest IS NULL))));
ALTER TABLE context.uiw_preview_snapshot ADD CONSTRAINT uiw_preview_snapshot_check1 CHECK (((parser_id IS NULL) OR ((length(btrim(parser_id)) > 0) AND (length(btrim(parser_version)) > 0))));
ALTER TABLE context.uiw_preview_snapshot ADD CONSTRAINT uiw_preview_snapshot_parser_config_digest_check CHECK (((parser_config_digest IS NULL) OR (octet_length(parser_config_digest) = 32)));
ALTER TABLE context.uiw_preview_snapshot ADD CONSTRAINT uiw_preview_snapshot_phase_check CHECK ((length(btrim(phase)) > 0));
ALTER TABLE context.uiw_preview_snapshot ADD CONSTRAINT uiw_preview_snapshot_pkey PRIMARY KEY (preview_handle, snapshot_seq);
ALTER TABLE context.uiw_preview_snapshot ADD CONSTRAINT uiw_preview_snapshot_preview_digest_check CHECK ((octet_length(preview_digest) = 32));
ALTER TABLE context.uiw_preview_snapshot ADD CONSTRAINT uiw_preview_snapshot_reason_check CHECK ((octet_length(reason) <= 4000));
ALTER TABLE context.uiw_preview_snapshot ADD CONSTRAINT uiw_preview_snapshot_snapshot_seq_check CHECK ((snapshot_seq >= 0));
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_actor_subject_uid_check CHECK ((length(btrim(actor_subject_uid)) > 0));
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_actor_username_check CHECK ((length(btrim(actor_username)) > 0));
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_assertions_check CHECK ((jsonb_typeof(assertions) = 'object'::text));
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_change_reason_check CHECK (((length(btrim(change_reason)) > 0) AND (octet_length(change_reason) <= 4000)));
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_check CHECK ((((revision = 1) AND (supersedes_ref IS NULL) AND (previous_assertions IS NULL)) OR ((revision > 1) AND (supersedes_ref IS NOT NULL) AND (previous_assertions IS NOT NULL))));
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_content_digest_check CHECK ((octet_length(content_digest) = 32));
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_idempotency_key_check CHECK ((length(btrim(idempotency_key)) > 0));
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_idempotency_key_key UNIQUE (idempotency_key);
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_observed_source_check CHECK ((jsonb_typeof(observed_source) = 'object'::text));
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_pkey PRIMARY KEY (source_context_ref);
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_previous_assertions_check CHECK (((previous_assertions IS NULL) OR (jsonb_typeof(previous_assertions) = 'object'::text)));
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_receipt_ref_check CHECK ((length(btrim(receipt_ref)) > 0));
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_receipt_ref_key UNIQUE (receipt_ref);
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_request_id_check CHECK ((length(btrim(request_id)) > 0));
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_request_id_revision_key UNIQUE (request_id, revision);
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_revision_check CHECK ((revision >= 1));
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_source_ref_check CHECK ((length(btrim(source_ref)) > 0));
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_scope_key UNIQUE (source_context_ref, matter_id, court_case_id);
ALTER TABLE evidence.acquisition ADD CONSTRAINT acquisition_asserter_identity_ck CHECK ((length(TRIM(BOTH FROM asserted_by_identity)) > 0));
ALTER TABLE evidence.acquisition ADD CONSTRAINT acquisition_human_only CHECK ((asserted_by = 'human'::text));
ALTER TABLE evidence.acquisition ADD CONSTRAINT acquisition_pkey PRIMARY KEY (id);
ALTER TABLE evidence.artifact_metadata ADD CONSTRAINT artifact_metadata_pkey PRIMARY KEY (id);
ALTER TABLE evidence.artifact_metadata ADD CONSTRAINT artifact_metadata_resolved_source_check CHECK ((resolved_source = ANY (ARRAY['embedded'::text, 'filename'::text, 'filesystem'::text, 'manual'::text])));
ALTER TABLE evidence.custody_event ADD CONSTRAINT custody_event_event_type_check CHECK ((event_type = ANY (ARRAY['collected'::text, 'sealed'::text, 'in_processing'::text, 'verified'::text, 'disputed'::text, 'released'::text, 're_hashed'::text, 'integrity_violation'::text, 'superseded'::text, 'accessed'::text])));
ALTER TABLE evidence.custody_event ADD CONSTRAINT custody_event_id_key UNIQUE (id);
ALTER TABLE evidence.custody_event ADD CONSTRAINT custody_event_pkey PRIMARY KEY (seq);
ALTER TABLE evidence.evidence_hash ADD CONSTRAINT evidence_hash_check CHECK (((algo <> 'sha256'::text) OR (octet_length(digest) = 32)));
ALTER TABLE evidence.evidence_hash ADD CONSTRAINT evidence_hash_level_check CHECK ((level = ANY (ARRAY['H1'::text, 'H2'::text, 'H3'::text])));
ALTER TABLE evidence.evidence_hash ADD CONSTRAINT evidence_hash_pkey PRIMARY KEY (id);
ALTER TABLE evidence.evidence_hash ADD CONSTRAINT evidence_hash_subject_ck CHECK (((level = 'H3'::text) OR (source_id IS NOT NULL) OR (file_node_id IS NOT NULL))) NOT VALID;
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_authentication_method_check CHECK (((authentication_method IS NULL) OR (authentication_method = ANY (ARRAY['witness_with_knowledge'::text, 'distinctive_characteristics'::text, 'process_or_system'::text, 'public_record'::text, 'hash_chain_of_custody'::text, 'self_authenticating'::text, 'stipulation'::text]))));
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_case_id_exhibit_number_key UNIQUE (case_id, exhibit_number);
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_case_management_scope_ck CHECK (((matter_id IS NULL) = (court_case_id IS NULL)));
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_case_management_scope_key UNIQUE (id, matter_id, court_case_id);
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_conf_tier_ck CHECK (((confidence_tier <> 'high'::text) OR (confidence IS NULL) OR ((confidence)::numeric >= 0.60)));
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_confidence_tier_check CHECK ((confidence_tier = ANY (ARRAY['high'::text, 'medium'::text, 'low'::text])));
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_evidence_type_check CHECK ((evidence_type = ANY (ARRAY['communication'::text, 'document'::text, 'photo'::text, 'record'::text, 'media'::text, 'screenshot'::text, 'transcript'::text, 'metadata'::text, 'other'::text])));
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_pkey PRIMARY KEY (id);
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_privacy_sensitivity_check CHECK ((privacy_sensitivity = ANY (ARRAY['none'::text, 'pii'::text, 'minor'::text, 'sensitive_pii'::text])));
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_redaction_status_check CHECK ((redaction_status = ANY (ARRAY['none'::text, 'required'::text, 'applied'::text])));
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_safe_ck CHECK (((safe_for_legal_use = false) OR ((review_status = 'approved'::review_state) AND (is_authenticated = true) AND (is_hypothesis = false) AND (redaction_status <> 'required'::text))));
ALTER TABLE evidence.ingest_run ADD CONSTRAINT ingest_run_notes_check CHECK ((jsonb_typeof(notes) = 'object'::text));
ALTER TABLE evidence.ingest_run ADD CONSTRAINT ingest_run_pkey PRIMARY KEY (id);
ALTER TABLE evidence.ingest_run ADD CONSTRAINT ingest_run_source_sha256_check CHECK ((octet_length(source_sha256) = 32));
ALTER TABLE evidence.ingest_run ADD CONSTRAINT ingest_run_status_check CHECK ((status = ANY (ARRAY['running'::text, 'committed'::text, 'rolled_back'::text, 'failed'::text])));
ALTER TABLE evidence.source ADD CONSTRAINT source_acquisition_method_check CHECK (((acquisition_method IS NULL) OR (acquisition_method = ANY (ARRAY['forensic_image'::text, 'manual_export'::text, 'cloud_pull'::text, 'photograph'::text, 'scan'::text, 'backup'::text]))));
ALTER TABLE evidence.source ADD CONSTRAINT source_custody_status_check CHECK ((custody_status = ANY (ARRAY['collected'::text, 'sealed'::text, 'in_processing'::text, 'verified'::text, 'disputed'::text, 'released'::text])));
ALTER TABLE evidence.source ADD CONSTRAINT source_export_status_check CHECK ((export_status = ANY (ARRAY['not_exported'::text, 'in_package'::text, 'exported'::text, 'withdrawn'::text])));
ALTER TABLE evidence.source ADD CONSTRAINT source_extraction_status_check CHECK ((extraction_status = ANY (ARRAY['pending'::text, 'running'::text, 'done'::text, 'failed'::text, 'n/a'::text])));
ALTER TABLE evidence.source ADD CONSTRAINT source_legal_sensitivity_check CHECK ((legal_sensitivity = ANY (ARRAY['none'::text, 'privileged'::text, 'confidential'::text, 'in_camera'::text])));
ALTER TABLE evidence.source ADD CONSTRAINT source_pkey PRIMARY KEY (id);
ALTER TABLE evidence.source ADD CONSTRAINT source_privacy_sensitivity_check CHECK ((privacy_sensitivity = ANY (ARRAY['none'::text, 'pii'::text, 'minor'::text, 'sensitive_pii'::text])));
ALTER TABLE evidence.source ADD CONSTRAINT source_processing_status_check CHECK ((processing_status = ANY (ARRAY['pending'::text, 'enriched'::text, 'analyzed'::text, 'failed'::text])));
ALTER TABLE evidence.source ADD CONSTRAINT source_provenance_tier_check CHECK ((provenance_tier = ANY (ARRAY['r2_canonical'::text, 'backup_corroborating'::text])));
ALTER TABLE evidence.source ADD CONSTRAINT source_review_status_check CHECK ((review_status = ANY (ARRAY['not_reviewed'::text, 'in_review'::text, 'reviewed'::text, 'flagged'::text])));
ALTER TABLE evidence.source ADD CONSTRAINT source_sha256_len CHECK ((octet_length(sha256) = 32));
ALTER TABLE evidence.source ADD CONSTRAINT source_sha256_uniq UNIQUE (sha256);
ALTER TABLE evidence.source ADD CONSTRAINT source_source_type_check CHECK ((source_type = ANY (ARRAY['device_dump'::text, 'chat_export'::text, 'screenshot'::text, 'call_log'::text, 'pdf'::text, 'media'::text, 'takeout'::text, 'social_export'::text, 'document'::text, 'other'::text])));
ALTER TABLE ops.audit_ledger ADD CONSTRAINT audit_ledger_action_type_check CHECK ((action_type = ANY (ARRAY['decision'::text, 'write'::text, 'read'::text, 'tool_call'::text, 'approval'::text, 'derivation'::text])));
ALTER TABLE ops.audit_ledger ADD CONSTRAINT audit_ledger_pkey PRIMARY KEY (id);
ALTER TABLE ops.migration_ledger ADD CONSTRAINT migration_ledger_ddl_sha256_check CHECK ((octet_length(ddl_sha256) = 32));
ALTER TABLE ops.migration_ledger ADD CONSTRAINT migration_ledger_pkey PRIMARY KEY (migration_id);
ALTER TABLE ops.processing_run ADD CONSTRAINT processing_run_pkey PRIMARY KEY (run_id);
ALTER TABLE ops.processing_run ADD CONSTRAINT processing_run_replayable_needs_code_ref CHECK (((NOT replayable) OR (code_ref IS NOT NULL))) NOT VALID;
ALTER TABLE ops.processing_run ADD CONSTRAINT processing_run_run_type_check CHECK ((run_type = ANY (ARRAY['acquisition'::text, 'file_scan'::text, 'repository_scan'::text, 'evidence_ingestion'::text, 'extraction'::text, 'ingestion'::text, 'ocr'::text, 'transcription'::text, 'message_parsing'::text, 'entity_extraction'::text, 'temporal_extraction'::text, 'location_extraction'::text, 'gps_processing'::text, 'embedding'::text, 'graph_projection'::text, 'surreal_consolidation'::text, 'ontology_merge'::text, 'schema_generation'::text, 'classification'::text, 'pattern_analysis'::text, 'legal_issue_mapping'::text, 'scoring'::text, 'model_analysis'::text, 'evidence_task_generation'::text, 'redaction'::text, 'export'::text, 'review'::text])));
ALTER TABLE ops.processing_run ADD CONSTRAINT processing_run_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'ok'::text, 'failed'::text, 'partial'::text, 'cancelled'::text, 'superseded'::text])));
ALTER TABLE ops.tool_call_ledger ADD CONSTRAINT tool_call_ledger_human_approval_status_check CHECK ((human_approval_status = ANY (ARRAY['n/a'::text, 'pending'::text, 'approved'::text, 'denied'::text])));
ALTER TABLE ops.tool_call_ledger ADD CONSTRAINT tool_call_ledger_pkey PRIMARY KEY (tool_call_id);
ALTER TABLE ops.tool_call_ledger ADD CONSTRAINT tool_call_ledger_replayability_status_check CHECK ((replayability_status = ANY (ARRAY['replayable'::text, 'inputs_lost'::text, 'nondeterministic'::text])));
ALTER TABLE ops.tool_call_ledger ADD CONSTRAINT tool_call_ledger_tool_category_check CHECK ((tool_category = ANY (ARRAY['read'::text, 'analysis'::text, 'write'::text, 'transfer'::text, 'deploy'::text, 'llm'::text, 'mcp'::text])));
ALTER TABLE ops.workflow_run ADD CONSTRAINT workflow_run_custody_tier_check CHECK ((custody_tier = ANY (ARRAY['full'::text, 'light'::text])));
ALTER TABLE ops.workflow_run ADD CONSTRAINT workflow_run_gate_state_check CHECK (((gate_state = ANY (ARRAY['waiting'::text, 'released'::text, 'abort'::text])) OR (gate_state IS NULL)));
ALTER TABLE ops.workflow_run ADD CONSTRAINT workflow_run_mode_check CHECK ((mode = ANY (ARRAY['auto'::text, 'supervised'::text])));
ALTER TABLE ops.workflow_run ADD CONSTRAINT workflow_run_pkey PRIMARY KEY (run_id);
ALTER TABLE ops.workflow_run ADD CONSTRAINT workflow_run_source_context_ck CHECK ((jsonb_typeof(source_context) = 'object'::text));
ALTER TABLE ops.workflow_run ADD CONSTRAINT workflow_run_status_check CHECK ((status = ANY (ARRAY['running'::text, 'paused'::text, 'completed'::text, 'failed'::text])));
ALTER TABLE ops.workflow_run_review_action ADD CONSTRAINT workflow_run_review_action_action_type_check CHECK ((action_type = ANY (ARRAY['acknowledge'::text, 'approve'::text, 'override'::text, 'continue'::text, 'abort'::text, 'retry'::text])));
ALTER TABLE ops.workflow_run_review_action ADD CONSTRAINT workflow_run_review_action_pkey PRIMARY KEY (action_id);
ALTER TABLE ops.workflow_run_review_action ADD CONSTRAINT workflow_run_review_action_reason_check CHECK ((length(btrim(reason)) > 0));
ALTER TABLE ops.workflow_run_stage ADD CONSTRAINT workflow_run_stage_pkey PRIMARY KEY (stage_id);
ALTER TABLE ops.workflow_run_stage ADD CONSTRAINT workflow_run_stage_run_id_seq_key UNIQUE (run_id, seq);
ALTER TABLE ops.workflow_run_stage ADD CONSTRAINT workflow_run_stage_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'running'::text, 'success'::text, 'failed'::text, 'skipped'::text])));
ALTER TABLE ops.workflow_run_stage ADD CONSTRAINT workflow_run_stage_terminal_reason CHECK ((((status = ANY (ARRAY['pending'::text, 'running'::text])) AND (outcome_reason_code IS NULL)) OR ((status = ANY (ARRAY['success'::text, 'failed'::text, 'skipped'::text])) AND (outcome_reason_code IS NOT NULL))));
ALTER TABLE public.app_setting ADD CONSTRAINT app_setting_pkey PRIMARY KEY (key);
ALTER TABLE public.canon_registry ADD CONSTRAINT canon_registry_canon_name_key UNIQUE (canon_name);
ALTER TABLE public.canon_registry ADD CONSTRAINT canon_registry_pkey PRIMARY KEY (id);
ALTER TABLE public.canon_registry ADD CONSTRAINT canon_registry_status_check CHECK ((status = ANY (ARRAY['active'::text, 'superseded'::text, 'lost'::text])));
ALTER TABLE public.change_log ADD CONSTRAINT change_log_change_origin_check CHECK ((change_origin = ANY (ARRAY['model_generated'::text, 'human_approved'::text, 'system'::text])));
ALTER TABLE public.change_log ADD CONSTRAINT change_log_pkey PRIMARY KEY (change_id);
ALTER TABLE public.classification_version ADD CONSTRAINT classification_version_pkey PRIMARY KEY (classification_version_id);
ALTER TABLE public.classification_version ADD CONSTRAINT classification_version_review_status_check CHECK ((review_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
ALTER TABLE public.classification_version ADD CONSTRAINT classification_version_version_label_scheme_key UNIQUE (version_label, scheme);
ALTER TABLE public.decision_log ADD CONSTRAINT decision_log_decision_type_check CHECK ((decision_type = ANY (ARRAY['schema'::text, 'ontology'::text, 'legal_relevance'::text, 'evidence_classification'::text, 'tooling'::text, 'storage'::text, 'privacy'::text, 'export'::text, 'human_review'::text])));
ALTER TABLE public.decision_log ADD CONSTRAINT decision_log_pkey PRIMARY KEY (decision_id);
ALTER TABLE public.decision_log ADD CONSTRAINT decision_log_reversibility_check CHECK ((reversibility = ANY (ARRAY['reversible'::text, 'costly'::text, 'irreversible'::text])));
ALTER TABLE public.decision_log ADD CONSTRAINT decision_log_review_status_check CHECK ((review_status = ANY (ARRAY['none'::text, 'pending'::text, 'approved'::text, 'rejected'::text])));
ALTER TABLE public.decision_precedent ADD CONSTRAINT decision_precedent_pkey PRIMARY KEY (precedent_id);
ALTER TABLE public.decision_precedent ADD CONSTRAINT decision_precedent_relationship_type_check CHECK ((relationship_type = ANY (ARRAY['similar_scenario'::text, 'same_policy'::text, 'exception_precedent'::text])));
ALTER TABLE public.memory_items ADD CONSTRAINT memory_items_memory_type_check CHECK ((memory_type = ANY (ARRAY['user_preference'::text, 'project_fact'::text, 'evidence_fact'::text, 'hypothesis'::text, 'analysis_finding'::text, 'design_decision'::text, 'open_question'::text, 'warning'::text, 'artifact_summary'::text, 'run_summary'::text, 'deprecated_memory'::text])));
ALTER TABLE public.memory_items ADD CONSTRAINT memory_items_pkey PRIMARY KEY (memory_id);
ALTER TABLE public.memory_items ADD CONSTRAINT memory_items_review_status_check CHECK ((review_status = ANY (ARRAY['none'::text, 'pending'::text, 'approved'::text, 'rejected'::text])));
ALTER TABLE public.memory_items ADD CONSTRAINT memory_items_status_check CHECK ((status = ANY (ARRAY['active'::text, 'draft'::text, 'needs_review'::text, 'superseded'::text, 'deprecated'::text, 'rejected'::text, 'archived'::text])));
ALTER TABLE public.model_version ADD CONSTRAINT model_version_model_id_role_version_key UNIQUE (model_id, role, version);
ALTER TABLE public.model_version ADD CONSTRAINT model_version_pkey PRIMARY KEY (model_version_id);
ALTER TABLE public.model_version ADD CONSTRAINT model_version_role_check CHECK ((role = ANY (ARRAY['llm'::text, 'embedder'::text, 'reranker'::text, 'ocr'::text, 'asr'::text])));
ALTER TABLE public.ontology_version ADD CONSTRAINT ontology_version_pkey PRIMARY KEY (ontology_version_id);
ALTER TABLE public.ontology_version ADD CONSTRAINT ontology_version_review_status_check CHECK ((review_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
ALTER TABLE public.ontology_version ADD CONSTRAINT ontology_version_version_label_source_key UNIQUE (version_label, source);
ALTER TABLE public.open_questions ADD CONSTRAINT open_questions_category_check CHECK ((category = ANY (ARRAY['data_gap'::text, 'schema'::text, 'ontology'::text, 'legal_relevance'::text, 'corroboration_needed'::text, 'privacy'::text, 'technical'::text])));
ALTER TABLE public.open_questions ADD CONSTRAINT open_questions_pkey PRIMARY KEY (question_id);
ALTER TABLE public.open_questions ADD CONSTRAINT open_questions_status_check CHECK ((status = ANY (ARRAY['open'::text, 'investigating'::text, 'answered'::text, 'wont_fix'::text, 'superseded'::text])));
ALTER TABLE public.platform_consolidation_receipt_claim ADD CONSTRAINT platform_consolidation_receipt_claim_check CHECK ((((claim_kind = 'verified'::text) AND (checkpoint_id IS NOT NULL) AND (successor_receipt_id IS NULL)) OR ((claim_kind = 'superseded'::text) AND (checkpoint_id IS NULL) AND (successor_receipt_id IS NOT NULL))));
ALTER TABLE public.platform_consolidation_receipt_claim ADD CONSTRAINT platform_consolidation_receipt_claim_claim_kind_check CHECK ((claim_kind = ANY (ARRAY['verified'::text, 'superseded'::text])));
ALTER TABLE public.platform_consolidation_receipt_claim ADD CONSTRAINT platform_consolidation_receipt_claim_pkey PRIMARY KEY (receipt_id);
ALTER TABLE public.prompt_registry ADD CONSTRAINT prompt_registry_pkey PRIMARY KEY (prompt_id);
ALTER TABLE public.prompt_registry ADD CONSTRAINT prompt_registry_prompt_name_prompt_version_key UNIQUE (prompt_name, prompt_version);
ALTER TABLE public.prompt_registry ADD CONSTRAINT prompt_registry_prompt_type_check CHECK ((prompt_type = ANY (ARRAY['extraction'::text, 'classification'::text, 'summary'::text, 'agent_instruction'::text, 'tone_style'::text, 'review'::text, 'export'::text])));
ALTER TABLE public.prompt_registry ADD CONSTRAINT prompt_registry_status_check CHECK ((status = ANY (ARRAY['active'::text, 'superseded'::text, 'deprecated'::text])));
ALTER TABLE public.schema_version ADD CONSTRAINT schema_version_pkey PRIMARY KEY (schema_version_id);
ALTER TABLE public.schema_version ADD CONSTRAINT schema_version_status_check CHECK ((status = ANY (ARRAY['active'::text, 'superseded'::text, 'deprecated'::text])));
ALTER TABLE public.schema_version ADD CONSTRAINT schema_version_version_label_applies_to_key UNIQUE (version_label, applies_to);
ALTER TABLE public.session_summaries ADD CONSTRAINT session_summaries_pkey PRIMARY KEY (session_id);
ALTER TABLE public.transcript_insight ADD CONSTRAINT transcript_insight_pkey PRIMARY KEY (id);
ALTER TABLE raw.file_node ADD CONSTRAINT file_node_node_kind_check CHECK ((node_kind = ANY (ARRAY['file'::text, 'archive_member'::text, 'page'::text, 'frame'::text, 'region'::text, 'screenshot'::text, 'ocr_block'::text, 'attachment'::text, 'message_unit'::text, 'event_unit'::text])));
ALTER TABLE raw.file_node ADD CONSTRAINT file_node_pkey PRIMARY KEY (id);
ALTER TABLE raw.file_node ADD CONSTRAINT file_node_sha_len CHECK (((sha256 IS NULL) OR (octet_length(sha256) = 32)));
ALTER TABLE raw.gps_point ADD CONSTRAINT gps_point_data_tier_check CHECK ((data_tier = 'raw'::evidence_tier));
ALTER TABLE raw.gps_point ADD CONSTRAINT gps_point_pkey PRIMARY KEY (id);
ALTER TABLE raw.raw_activity ADD CONSTRAINT raw_activity_data_tier_check CHECK ((data_tier = 'raw'::evidence_tier));
ALTER TABLE raw.raw_activity ADD CONSTRAINT raw_activity_pkey PRIMARY KEY (id);
ALTER TABLE raw.raw_ai_chat ADD CONSTRAINT raw_ai_chat_pkey PRIMARY KEY (id);
ALTER TABLE raw.raw_csv ADD CONSTRAINT raw_csv_pkey PRIMARY KEY (id);
ALTER TABLE raw.raw_facebook ADD CONSTRAINT raw_facebook_pkey PRIMARY KEY (id);
ALTER TABLE raw.raw_imessage ADD CONSTRAINT raw_imessage_pkey PRIMARY KEY (id);
ALTER TABLE raw.raw_path ADD CONSTRAINT raw_path_data_tier_check CHECK ((data_tier = 'raw'::evidence_tier));
ALTER TABLE raw.raw_path ADD CONSTRAINT raw_path_pkey PRIMARY KEY (id);
ALTER TABLE raw.raw_phone ADD CONSTRAINT raw_phone_pkey PRIMARY KEY (id);
ALTER TABLE raw.raw_rejected ADD CONSTRAINT raw_rejected_pkey PRIMARY KEY (id);
ALTER TABLE raw.raw_rejected ADD CONSTRAINT raw_rejected_reason_check CHECK ((reason = ANY (ARRAY['no_timestamp_no_counterparty'::text, 'dedup_duplicate_in_source'::text, 'parser_returned_none'::text, 'unmapped_element'::text, 'malformed'::text, 'operator_excluded'::text])));
ALTER TABLE raw.raw_rejected ADD CONSTRAINT raw_rejected_source_sha256_check CHECK ((octet_length(source_sha256) = 32));
ALTER TABLE raw.raw_sms ADD CONSTRAINT raw_sms_pkey PRIMARY KEY (id);
ALTER TABLE raw.raw_trip ADD CONSTRAINT raw_trip_data_tier_check CHECK ((data_tier = 'raw'::evidence_tier));
ALTER TABLE raw.raw_trip ADD CONSTRAINT raw_trip_pkey PRIMARY KEY (id);
ALTER TABLE raw.raw_visit ADD CONSTRAINT raw_visit_data_tier_check CHECK ((data_tier = 'raw'::evidence_tier));
ALTER TABLE raw.raw_visit ADD CONSTRAINT raw_visit_pkey PRIMARY KEY (id);
ALTER TABLE reference.behavior_category ADD CONSTRAINT behavior_category_pkey PRIMARY KEY (category_id);
ALTER TABLE reference.behavior_category ADD CONSTRAINT behavior_category_sev_chk CHECK (((default_severity >= 0) AND (default_severity <= 10)));
ALTER TABLE reference.behavior_category_mcl ADD CONSTRAINT behavior_category_mcl_pkey PRIMARY KEY (category_id, factor_code);
ALTER TABLE reference.claim_type ADD CONSTRAINT claim_type_description_check CHECK ((length(btrim(description)) > 0));
ALTER TABLE reference.claim_type ADD CONSTRAINT claim_type_label_check CHECK ((length(btrim(label)) > 0));
ALTER TABLE reference.claim_type ADD CONSTRAINT claim_type_pkey PRIMARY KEY (slug);
ALTER TABLE reference.claim_type ADD CONSTRAINT claim_type_slug_check CHECK (((slug = lower(slug)) AND (slug ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'::text)));
ALTER TABLE reference.custody_factor ADD CONSTRAINT custody_factor_pkey PRIMARY KEY (factor);
ALTER TABLE reference.detection_pattern ADD CONSTRAINT detection_pattern_pattern_set_id_category_id_match_type_pat_key UNIQUE (pattern_set_id, category_id, match_type, pattern);
ALTER TABLE reference.detection_pattern ADD CONSTRAINT detection_pattern_pkey PRIMARY KEY (id);
ALTER TABLE reference.detection_pattern ADD CONSTRAINT detection_pattern_score_chk CHECK (((score IS NULL) OR ((score >= 1) AND (score <= 10))));
ALTER TABLE reference.detection_pattern ADD CONSTRAINT detection_pattern_sev_chk CHECK (((severity >= 0) AND (severity <= 10)));
ALTER TABLE reference.detection_pattern_set ADD CONSTRAINT detection_pattern_set_name_version_key UNIQUE (name, version);
ALTER TABLE reference.detection_pattern_set ADD CONSTRAINT detection_pattern_set_pkey PRIMARY KEY (id);
ALTER TABLE reference.format_resolver ADD CONSTRAINT format_resolver_pkey PRIMARY KEY (id);
ALTER TABLE reference.format_resolver ADD CONSTRAINT format_resolver_source_signature_target_schema_key UNIQUE (source_signature, target_schema);
ALTER TABLE reference.knowledge_tag ADD CONSTRAINT knowledge_tag_label_check CHECK ((length(label) > 0));
ALTER TABLE reference.knowledge_tag ADD CONSTRAINT knowledge_tag_pkey PRIMARY KEY (id);
ALTER TABLE reference.knowledge_tag ADD CONSTRAINT knowledge_tag_slug_check CHECK (((slug = lower(slug)) AND (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'::text)));
ALTER TABLE reference.knowledge_tag ADD CONSTRAINT knowledge_tag_slug_key UNIQUE (slug);
ALTER TABLE reference.legal_issue ADD CONSTRAINT legal_issue_case_id_issue_key_key UNIQUE (case_id, issue_key);
ALTER TABLE reference.legal_issue ADD CONSTRAINT legal_issue_issue_type_check CHECK ((issue_type = ANY (ARRAY['custody'::text, 'parenting_time'::text, 'support'::text, 'relocation'::text, 'protective_order'::text, 'property'::text, 'contempt'::text, 'other'::text])));
ALTER TABLE reference.legal_issue ADD CONSTRAINT legal_issue_pkey PRIMARY KEY (id);
ALTER TABLE reference.legal_issue_factor ADD CONSTRAINT legal_issue_factor_pkey PRIMARY KEY (legal_issue_id, factor);
ALTER TABLE reference.lexicon_sync ADD CONSTRAINT lexicon_sync_level_check CHECK (((level IS NULL) OR (level = ANY (ARRAY['conservative'::text, 'inclusive'::text]))));
ALTER TABLE reference.lexicon_sync ADD CONSTRAINT lexicon_sync_pkey PRIMARY KEY (id);
ALTER TABLE reference.lexicon_sync ADD CONSTRAINT lexicon_sync_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'syncing'::text, 'success'::text, 'error'::text])));
ALTER TABLE reference.pattern_lexicon ADD CONSTRAINT pattern_lexicon_pkey PRIMARY KEY (id);
ALTER TABLE reference.pattern_lexicon ADD CONSTRAINT pattern_lexicon_sev_chk CHECK (((severity >= 0) AND (severity <= 10)));
ALTER TABLE reference.relative_rule ADD CONSTRAINT relative_rule_pkey PRIMARY KEY (rule_id);
ALTER TABLE reference.score_band_config ADD CONSTRAINT score_band_config_pkey PRIMARY KEY (config_version);
ALTER TABLE reference.topic_code ADD CONSTRAINT topic_code_pkey PRIMARY KEY (code);
ALTER TABLE registry.court_case ADD CONSTRAINT court_case_caption_check CHECK ((length(btrim(caption)) > 0));
ALTER TABLE registry.court_case ADD CONSTRAINT court_case_created_by_check CHECK ((length(btrim(created_by)) > 0));
ALTER TABLE registry.court_case ADD CONSTRAINT court_case_dates_ck CHECK (((closed_on IS NULL) OR (filed_on IS NULL) OR (closed_on >= filed_on)));
ALTER TABLE registry.court_case ADD CONSTRAINT court_case_id_matter_key UNIQUE (id, matter_id);
ALTER TABLE registry.court_case ADD CONSTRAINT court_case_pkey PRIMARY KEY (id);
ALTER TABLE registry.court_case ADD CONSTRAINT court_case_status_check CHECK ((status = ANY (ARRAY['pre_filing'::text, 'active'::text, 'stayed'::text, 'closed'::text, 'appealed'::text, 'archived'::text])));
ALTER TABLE registry.court_case ADD CONSTRAINT court_case_verification_state_check CHECK ((verification_state = ANY (ARRAY['proposed'::text, 'confirmed'::text, 'disputed'::text])));
ALTER TABLE registry.device ADD CONSTRAINT device_pkey PRIMARY KEY (id);
ALTER TABLE registry.device ADD CONSTRAINT device_verification_state_check CHECK ((verification_state = ANY (ARRAY['proposed'::text, 'confirmed'::text, 'disputed'::text])));
ALTER TABLE registry.entity ADD CONSTRAINT entity_not_self_merge CHECK ((merged_into_id IS DISTINCT FROM id));
ALTER TABLE registry.entity ADD CONSTRAINT entity_pkey PRIMARY KEY (id);
ALTER TABLE registry.entity_alias ADD CONSTRAINT entity_alias_alias_kind_check CHECK ((alias_kind = ANY (ARRAY['nickname'::text, 'legal'::text, 'maiden'::text, 'handle'::text, 'misspelling'::text, 'phonetic'::text, 'initials'::text, 'other'::text])));
ALTER TABLE registry.entity_alias ADD CONSTRAINT entity_alias_pkey PRIMARY KEY (id);
ALTER TABLE registry.id_xref ADD CONSTRAINT id_xref_pkey PRIMARY KEY (id);
ALTER TABLE registry.id_xref ADD CONSTRAINT uq_xref_pair UNIQUE (system_a, native_id_a, system_b, native_id_b);
ALTER TABLE registry.location ADD CONSTRAINT location_data_tier_check CHECK ((data_tier = ANY (ARRAY['extracted'::evidence_tier, 'inferred'::evidence_tier, 'analytical'::evidence_tier])));
ALTER TABLE registry.location ADD CONSTRAINT location_pkey PRIMARY KEY (id);
ALTER TABLE registry.location ADD CONSTRAINT location_verification_state_check CHECK ((verification_state = ANY (ARRAY['proposed'::text, 'confirmed'::text, 'disputed'::text])));
ALTER TABLE registry.matter ADD CONSTRAINT matter_created_by_check CHECK ((length(btrim(created_by)) > 0));
ALTER TABLE registry.matter ADD CONSTRAINT matter_pkey PRIMARY KEY (id);
ALTER TABLE registry.matter ADD CONSTRAINT matter_status_check CHECK ((status = ANY (ARRAY['active'::text, 'closed'::text, 'archived'::text])));
ALTER TABLE registry.matter ADD CONSTRAINT matter_title_check CHECK ((length(btrim(title)) > 0));
ALTER TABLE registry.matter ADD CONSTRAINT matter_verification_state_check CHECK ((verification_state = ANY (ARRAY['proposed'::text, 'confirmed'::text, 'disputed'::text])));
ALTER TABLE registry.person ADD CONSTRAINT person_connection_to_check CHECK ((connection_to = ANY (ARRAY['petitioner'::text, 'respondent'::text, 'child'::text, 'mutual'::text, 'third_party'::text, 'unknown'::text])));
ALTER TABLE registry.person ADD CONSTRAINT person_pkey PRIMARY KEY (id);
ALTER TABLE registry.person ADD CONSTRAINT person_role_in_case_check CHECK ((role_in_case = ANY (ARRAY['user'::text, 'partner'::text, 'child'::text, 'witness'::text, 'evaluator'::text, 'attorney'::text, 'third_party'::text, 'neutral'::text, 'unknown'::text])));
ALTER TABLE registry.person ADD CONSTRAINT person_verification_state_check CHECK ((verification_state = ANY (ARRAY['proposed'::text, 'confirmed'::text, 'disputed'::text])));
ALTER TABLE timeline.event_candidate ADD CONSTRAINT event_candidate_pkey PRIMARY KEY (id);
ALTER TABLE timeline.event_candidate ADD CONSTRAINT event_candidate_source_identity_uq UNIQUE (source_system, source_record_id, source_record_version);
ALTER TABLE timeline.event_candidate ADD CONSTRAINT event_candidate_temporal_confidence_check CHECK (((temporal_confidence IS NULL) OR ((temporal_confidence >= (0)::double precision) AND (temporal_confidence <= (1)::double precision))));
ALTER TABLE timeline.event_candidate ADD CONSTRAINT event_candidate_temporal_precision_check CHECK ((temporal_precision = ANY (ARRAY['point'::text, 'interval'::text, 'uncertain'::text])));
ALTER TABLE timeline.event_candidate_relative_time_anchor ADD CONSTRAINT event_candidate_relative_time_anchor_anchor_role_check CHECK ((anchor_role = ANY (ARRAY['occurred_at'::text, 'valid_from'::text, 'valid_to'::text, 'source_available_from'::text, 'realizable_from'::text])));
ALTER TABLE timeline.event_candidate_relative_time_anchor ADD CONSTRAINT event_candidate_relative_time_anchor_pkey PRIMARY KEY (event_candidate_id, anchor_id, anchor_role);
ALTER TABLE timeline.event_candidate_source_range ADD CONSTRAINT event_candidate_source_range_event_candidate_id_member_ordi_key UNIQUE (event_candidate_id, member_ordinal);
ALTER TABLE timeline.event_candidate_source_range ADD CONSTRAINT event_candidate_source_range_extractor_id_check CHECK ((length(btrim(extractor_id)) > 0));
ALTER TABLE timeline.event_candidate_source_range ADD CONSTRAINT event_candidate_source_range_extractor_version_check CHECK ((length(btrim(extractor_version)) > 0));
ALTER TABLE timeline.event_candidate_source_range ADD CONSTRAINT event_candidate_source_range_member_ordinal_check CHECK ((member_ordinal >= 0));
ALTER TABLE timeline.event_candidate_source_range ADD CONSTRAINT event_candidate_source_range_pkey PRIMARY KEY (id);
ALTER TABLE timeline.event_candidate_source_range ADD CONSTRAINT event_candidate_source_range_schema_manifest_digest_check CHECK ((octet_length(schema_manifest_digest) = 32));
ALTER TABLE timeline.timeline_collection ADD CONSTRAINT timeline_collection_pkey PRIMARY KEY (id);
ALTER TABLE timeline.timeline_collection ADD CONSTRAINT timeline_collection_slug_key UNIQUE (slug);
ALTER TABLE timeline.timeline_member ADD CONSTRAINT timeline_member_authority_shape_ck CHECK ((((member_authority = 'candidate_context'::text) AND (candidate_id IS NOT NULL) AND (governed_source_schema IS NULL) AND (governed_source_table IS NULL) AND (governed_source_pk IS NULL)) OR ((member_authority = 'evidence_approved'::text) AND (candidate_id IS NULL) AND (governed_source_schema IS NOT NULL) AND (governed_source_table IS NOT NULL) AND (governed_source_pk IS NOT NULL))));
ALTER TABLE timeline.timeline_member ADD CONSTRAINT timeline_member_member_authority_check CHECK ((member_authority = ANY (ARRAY['candidate_context'::text, 'evidence_approved'::text])));
ALTER TABLE timeline.timeline_member ADD CONSTRAINT timeline_member_pkey PRIMARY KEY (id);
ALTER TABLE timeline.timeline_projection_activation ADD CONSTRAINT timeline_projection_activation_pkey PRIMARY KEY (id);
ALTER TABLE timeline.timeline_projection_generation ADD CONSTRAINT timeline_projection_generation_idempotency_key_key UNIQUE (idempotency_key);
ALTER TABLE timeline.timeline_projection_generation ADD CONSTRAINT timeline_projection_generation_pkey PRIMARY KEY (id);
ALTER TABLE timeline.timeline_projection_generation ADD CONSTRAINT timeline_projection_generation_status_check CHECK ((status = ANY (ARRAY['sealed'::text, 'superseded'::text, 'quarantined'::text])));
ALTER TABLE timeline.timeline_projection_member ADD CONSTRAINT timeline_projection_member_amendment_shape_ck CHECK ((((authority_state = 'amendment_candidate'::text) AND (amends_stable_member_id IS NOT NULL)) OR ((authority_state <> 'amendment_candidate'::text) AND (amends_stable_member_id IS NULL))));
ALTER TABLE timeline.timeline_projection_member ADD CONSTRAINT timeline_projection_member_authority_state_check CHECK ((authority_state = ANY (ARRAY['candidate_context'::text, 'evidence_approved'::text, 'amendment_candidate'::text])));
ALTER TABLE timeline.timeline_projection_member ADD CONSTRAINT timeline_projection_member_change_class_check CHECK ((change_class = ANY (ARRAY['core'::text, 'annotation'::text, 'unchanged'::text])));
ALTER TABLE timeline.timeline_projection_member ADD CONSTRAINT timeline_projection_member_generation_uq UNIQUE (generation_id, stable_member_id);
ALTER TABLE timeline.timeline_projection_member ADD CONSTRAINT timeline_projection_member_pkey PRIMARY KEY (id);
ALTER TABLE timeline.timeline_projection_member ADD CONSTRAINT timeline_projection_member_temporal_confidence_check CHECK (((temporal_confidence IS NULL) OR ((temporal_confidence >= (0)::double precision) AND (temporal_confidence <= (1)::double precision))));
ALTER TABLE timeline.timeline_projection_member ADD CONSTRAINT timeline_projection_member_temporal_precision_check CHECK ((temporal_precision = ANY (ARRAY['point'::text, 'interval'::text, 'uncertain'::text])));
ALTER TABLE timeline.timeline_projection_member ADD CONSTRAINT timeline_projection_member_verification_state_check CHECK ((verification_state = ANY (ARRAY['unverified'::text, 'disputed'::text, 'verified'::text, 'revoked'::text, 'superseded'::text])));
ALTER TABLE timeline.timeline_projection_receipt ADD CONSTRAINT timeline_projection_receipt_pkey PRIMARY KEY (id);
ALTER TABLE timeline.timeline_projection_receipt ADD CONSTRAINT timeline_projection_receipt_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'attempted'::text, 'succeeded'::text, 'failed_retryable'::text, 'failed_terminal'::text, 'quarantined'::text, 'superseded'::text])));
ALTER TABLE working.account ADD CONSTRAINT account_pkey PRIMARY KEY (id);
ALTER TABLE working.artifact_registry ADD CONSTRAINT artifact_registry_check CHECK (((status <> 'archived'::text) OR (archive_reason IS NOT NULL)));
ALTER TABLE working.artifact_registry ADD CONSTRAINT artifact_registry_pkey PRIMARY KEY (artifact_id);
ALTER TABLE working.artifact_registry ADD CONSTRAINT artifact_registry_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'needs_review'::text, 'active'::text, 'approved'::text, 'promoted'::text, 'rejected'::text, 'superseded'::text, 'archived'::text])));
ALTER TABLE working.attachment ADD CONSTRAINT attachment_file_sha256_check CHECK (((file_sha256 IS NULL) OR (octet_length(file_sha256) = 32)));
ALTER TABLE working.attachment ADD CONSTRAINT attachment_pkey PRIMARY KEY (id);
ALTER TABLE working.call_log ADD CONSTRAINT call_log_call_type_check CHECK ((call_type = ANY (ARRAY['incoming'::text, 'outgoing'::text, 'missed'::text, 'rejected'::text, 'blocked_incoming'::text, 'blocked_outgoing'::text, 'voicemail'::text])));
ALTER TABLE working.call_log ADD CONSTRAINT call_log_direction_check CHECK ((direction = ANY (ARRAY['inbound'::text, 'outbound'::text, 'unknown'::text])));
ALTER TABLE working.call_log ADD CONSTRAINT call_log_pkey PRIMARY KEY (id);
ALTER TABLE working.candidate_entity ADD CONSTRAINT candidate_entity_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text));
ALTER TABLE working.candidate_entity ADD CONSTRAINT candidate_entity_case_id_ck CHECK ((length(case_id) > 0));
ALTER TABLE working.candidate_entity ADD CONSTRAINT candidate_entity_confidence_check CHECK (((confidence >= (0)::double precision) AND (confidence <= (1)::double precision)));
ALTER TABLE working.candidate_entity ADD CONSTRAINT candidate_entity_content_sha256_check CHECK ((octet_length(content_sha256) = 32));
ALTER TABLE working.candidate_entity ADD CONSTRAINT candidate_entity_domain_ck CHECK ((domain = ANY (ARRAY['evidence'::text, 'legal'::text, 'behavioral'::text, 'platform_design'::text, 'context'::text])));
ALTER TABLE working.candidate_entity ADD CONSTRAINT candidate_entity_entity_type_check CHECK ((entity_type = ANY (ARRAY['person'::text, 'organization'::text, 'location'::text, 'device'::text, 'account'::text, 'other'::text])));
ALTER TABLE working.candidate_entity ADD CONSTRAINT candidate_entity_name_check CHECK ((length(name) > 0));
ALTER TABLE working.candidate_entity ADD CONSTRAINT candidate_entity_normalized_name_check CHECK ((length(normalized_name) > 0));
ALTER TABLE working.candidate_entity ADD CONSTRAINT candidate_entity_pkey PRIMARY KEY (id);
ALTER TABLE working.candidate_entity ADD CONSTRAINT candidate_entity_promotion_is_complete CHECK ((((promoted_at IS NULL) AND (promoted_to_table IS NULL) AND (promoted_to_id IS NULL)) OR ((promoted_at IS NOT NULL) AND (promoted_to_table IS NOT NULL) AND (promoted_to_id IS NOT NULL))));
ALTER TABLE working.candidate_entity ADD CONSTRAINT candidate_entity_promotion_requires_approval CHECK (((promoted_at IS NULL) OR (review_state = 'approved'::text)));
ALTER TABLE working.candidate_entity ADD CONSTRAINT candidate_entity_review_state_check CHECK ((review_state = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'needs_info'::text, 'superseded'::text])));
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text));
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_case_id_ck CHECK ((length(case_id) > 0));
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_confidence_check CHECK (((confidence >= (0)::double precision) AND (confidence <= (1)::double precision)));
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_content_sha256_check CHECK ((octet_length(content_sha256) = 32));
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_domain_ck CHECK ((domain = ANY (ARRAY['evidence'::text, 'legal'::text, 'behavioral'::text, 'platform_design'::text, 'context'::text])));
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_event_type_check CHECK ((length(event_type) > 0));
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_has_some_time CHECK (((occurred_at IS NOT NULL) OR (validity IS NOT NULL)));
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_pkey PRIMARY KEY (id);
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_promotion_is_complete CHECK ((((promoted_at IS NULL) AND (promoted_to_table IS NULL) AND (promoted_to_id IS NULL)) OR ((promoted_at IS NOT NULL) AND (promoted_to_table IS NOT NULL) AND (promoted_to_id IS NOT NULL))));
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_promotion_requires_approval CHECK (((promoted_at IS NULL) OR (review_state = 'approved'::text)));
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_review_state_check CHECK ((review_state = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'needs_info'::text, 'superseded'::text])));
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_summary_check CHECK ((length(summary) > 0));
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_temporal_confidence_check CHECK (((temporal_confidence >= (0)::double precision) AND (temporal_confidence <= (1)::double precision)));
ALTER TABLE working.candidate_fact ADD CONSTRAINT candidate_fact_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text));
ALTER TABLE working.candidate_fact ADD CONSTRAINT candidate_fact_case_id_ck CHECK ((length(case_id) > 0));
ALTER TABLE working.candidate_fact ADD CONSTRAINT candidate_fact_confidence_check CHECK (((confidence >= (0)::double precision) AND (confidence <= (1)::double precision)));
ALTER TABLE working.candidate_fact ADD CONSTRAINT candidate_fact_content_sha256_check CHECK ((octet_length(content_sha256) = 32));
ALTER TABLE working.candidate_fact ADD CONSTRAINT candidate_fact_domain_ck CHECK ((domain = ANY (ARRAY['evidence'::text, 'legal'::text, 'behavioral'::text, 'platform_design'::text, 'context'::text])));
ALTER TABLE working.candidate_fact ADD CONSTRAINT candidate_fact_pkey PRIMARY KEY (id);
ALTER TABLE working.candidate_fact ADD CONSTRAINT candidate_fact_predicate_check CHECK ((length(predicate) > 0));
ALTER TABLE working.candidate_fact ADD CONSTRAINT candidate_fact_promotion_is_complete CHECK ((((promoted_at IS NULL) AND (promoted_to_table IS NULL) AND (promoted_to_id IS NULL)) OR ((promoted_at IS NOT NULL) AND (promoted_to_table IS NOT NULL) AND (promoted_to_id IS NOT NULL))));
ALTER TABLE working.candidate_fact ADD CONSTRAINT candidate_fact_promotion_requires_approval CHECK (((promoted_at IS NULL) OR (review_state = 'approved'::text)));
ALTER TABLE working.candidate_fact ADD CONSTRAINT candidate_fact_review_state_check CHECK ((review_state = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'needs_info'::text, 'superseded'::text])));
ALTER TABLE working.candidate_fact ADD CONSTRAINT candidate_fact_statement_check CHECK ((length(statement) > 0));
ALTER TABLE working.chat_conversation ADD CONSTRAINT chat_conversation_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text));
ALTER TABLE working.chat_conversation ADD CONSTRAINT chat_conversation_pkey PRIMARY KEY (id);
ALTER TABLE working.chat_conversation ADD CONSTRAINT chat_conversation_source_external_id_key UNIQUE (source, external_id);
ALTER TABLE working.chat_message ADD CONSTRAINT chat_message_attachments_check CHECK ((jsonb_typeof(attachments) = 'array'::text));
ALTER TABLE working.chat_message ADD CONSTRAINT chat_message_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text));
ALTER TABLE working.chat_message ADD CONSTRAINT chat_message_content_hash_check CHECK ((length(content_hash) = 64));
ALTER TABLE working.chat_message ADD CONSTRAINT chat_message_conversation_id_message_index_key UNIQUE (conversation_id, message_index);
ALTER TABLE working.chat_message ADD CONSTRAINT chat_message_message_index_check CHECK ((message_index >= 0));
ALTER TABLE working.chat_message ADD CONSTRAINT chat_message_pkey PRIMARY KEY (id);
ALTER TABLE working.chat_message ADD CONSTRAINT chat_message_role_check CHECK ((role = ANY (ARRAY['user'::text, 'assistant'::text, 'system'::text, 'tool'::text, 'unknown'::text])));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_assistant_is_proposal CHECK (((speaker_role = 'assistant'::text) = (claim_class = 'AI_PROPOSAL'::text)));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_body_check CHECK ((length(btrim(body)) > 0));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_check CHECK (((span_end IS NULL) OR (span_end >= span_start)));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_claim_class_check CHECK ((claim_class = ANY (ARRAY['SELF_ACCOUNT'::text, 'SELF_ALLEGATION'::text, 'REPORTED_SPEECH'::text, 'DOCUMENT_QUOTE'::text, 'AI_PROPOSAL'::text, 'UNKNOWN'::text])));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_confidence_check CHECK (((confidence IS NULL) OR ((confidence >= (0)::double precision) AND (confidence <= (1)::double precision))));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_content_sha256_check CHECK ((octet_length(content_sha256) = 32));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_extractor_check CHECK ((length(btrim(extractor)) > 0));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_extractor_version_check CHECK ((length(btrim(extractor_version)) > 0));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_fingerprint_check CHECK ((length(btrim(fingerprint)) > 0));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_hedge_consistency CHECK ((hedged OR (cardinality(hedge_terms) = 0)));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_message_ordinal_check CHECK ((message_ordinal >= 0));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_pkey PRIMARY KEY (id);
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_review_is_attributed CHECK (((review_state = 'pending'::text) OR ((reviewed_by IS NOT NULL) AND (reviewed_at IS NOT NULL))));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_review_state_check CHECK ((review_state = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'needs_info'::text, 'superseded'::text])));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_span_start_check CHECK (((span_start IS NULL) OR (span_start >= 0)));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_speaker_role_check CHECK ((speaker_role = ANY (ARRAY['human'::text, 'assistant'::text, 'system'::text, 'unknown'::text])));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_title_check CHECK ((length(btrim(title)) > 0));
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_verbatim_check CHECK (((length(verbatim) >= 1) AND (length(verbatim) <= 300)));
ALTER TABLE working.claim_temporal_edge ADD CONSTRAINT claim_temporal_edge_as_stated_verbatim_check CHECK (((length(as_stated_verbatim) >= 1) AND (length(as_stated_verbatim) <= 300)));
ALTER TABLE working.claim_temporal_edge ADD CONSTRAINT claim_temporal_edge_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text));
ALTER TABLE working.claim_temporal_edge ADD CONSTRAINT claim_temporal_edge_confidence_check CHECK (((confidence IS NULL) OR ((confidence >= (0)::double precision) AND (confidence <= (1)::double precision))));
ALTER TABLE working.claim_temporal_edge ADD CONSTRAINT claim_temporal_edge_no_self_reference CHECK (((from_claim_id IS DISTINCT FROM to_claim_id) AND (from_claim_id IS DISTINCT FROM resolved_claim_id)));
ALTER TABLE working.claim_temporal_edge ADD CONSTRAINT claim_temporal_edge_pkey PRIMARY KEY (id);
ALTER TABLE working.claim_temporal_edge ADD CONSTRAINT claim_temporal_edge_relation_check CHECK ((relation = ANY (ARRAY['before'::text, 'after'::text, 'same_window'::text, 'during'::text, 'approximately_at'::text])));
ALTER TABLE working.claim_temporal_edge ADD CONSTRAINT claim_temporal_edge_resolution_is_complete CHECK ((((resolved_claim_id IS NULL) AND (resolved_by IS NULL) AND (resolved_at IS NULL)) OR ((resolved_claim_id IS NOT NULL) AND (resolved_by IS NOT NULL) AND (resolved_at IS NOT NULL) AND (target_kind = 'unresolved_phrase'::text))));
ALTER TABLE working.claim_temporal_edge ADD CONSTRAINT claim_temporal_edge_review_state_check CHECK ((review_state = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'needs_info'::text, 'superseded'::text])));
ALTER TABLE working.claim_temporal_edge ADD CONSTRAINT claim_temporal_edge_target_is_complete CHECK ((((target_kind = 'claim'::text) AND (to_claim_id IS NOT NULL) AND (target_phrase IS NULL)) OR ((target_kind = 'unresolved_phrase'::text) AND (to_claim_id IS NULL) AND (target_phrase IS NOT NULL) AND (length(btrim(target_phrase)) > 0))));
ALTER TABLE working.claim_temporal_edge ADD CONSTRAINT claim_temporal_edge_target_kind_check CHECK ((target_kind = ANY (ARRAY['claim'::text, 'unresolved_phrase'::text])));
ALTER TABLE working.content_chunk ADD CONSTRAINT content_chunk_check CHECK ((digest(convert_to(content, 'UTF8'::name), 'sha256'::text) = content_sha256));
ALTER TABLE working.content_chunk ADD CONSTRAINT content_chunk_chunk_index_check CHECK ((chunk_index >= 0));
ALTER TABLE working.content_chunk ADD CONSTRAINT content_chunk_content_check CHECK ((length(content) > 0));
ALTER TABLE working.content_chunk ADD CONSTRAINT content_chunk_content_sha256_check CHECK ((octet_length(content_sha256) = 32));
ALTER TABLE working.content_chunk ADD CONSTRAINT content_chunk_derivation_mode_check CHECK ((derivation_mode = ANY (ARRAY['verbatim_span'::text, 'composed'::text, 'unverified_derived'::text])));
ALTER TABLE working.content_chunk ADD CONSTRAINT content_chunk_generation_id_chunk_index_key UNIQUE (generation_id, chunk_index);
ALTER TABLE working.content_chunk ADD CONSTRAINT content_chunk_id_generation_id_source_version_id_key UNIQUE (id, generation_id, source_version_id);
ALTER TABLE working.content_chunk ADD CONSTRAINT content_chunk_pkey PRIMARY KEY (id);
ALTER TABLE working.content_chunk ADD CONSTRAINT content_chunk_token_count_check CHECK (((token_count IS NULL) OR (token_count >= 0)));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_check CHECK ((((status = 'open'::text) AND (sealed_at IS NULL) AND (sealed_by IS NULL) AND (aborted_at IS NULL) AND (abort_reason IS NULL) AND (chunk_count IS NULL) AND (member_count IS NULL) AND (manifest_sha256 IS NULL)) OR ((status = 'sealed'::text) AND (sealed_at IS NOT NULL) AND (length(btrim(sealed_by)) > 0) AND (aborted_at IS NULL) AND (abort_reason IS NULL) AND (chunk_count IS NOT NULL) AND (member_count IS NOT NULL) AND (manifest_sha256 IS NOT NULL)) OR ((status = 'aborted'::text) AND (sealed_at IS NULL) AND (sealed_by IS NULL) AND (aborted_at IS NOT NULL) AND (length(btrim(abort_reason)) > 0))));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_chunk_count_check CHECK (((chunk_count IS NULL) OR (chunk_count >= 0)));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_chunker_id_check CHECK ((length(btrim(chunker_id)) > 0));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_chunker_version_check CHECK ((length(btrim(chunker_version)) > 0));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_completeness_scope_check CHECK ((completeness_scope = 'complete'::text));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_config_digest_check CHECK ((octet_length(config_digest) = 32));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_generation_ordinal_check CHECK ((generation_ordinal > 0));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_id_source_version_id_key UNIQUE (id, source_version_id);
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_implementation_digest_check CHECK ((octet_length(implementation_digest) = 32));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_manifest_sha256_check CHECK (((manifest_sha256 IS NULL) OR (octet_length(manifest_sha256) = 32)));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_member_count_check CHECK (((member_count IS NULL) OR (member_count >= 0)));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_pkey PRIMARY KEY (id);
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_policy_id_check CHECK ((length(btrim(policy_id)) > 0));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_policy_version_check CHECK ((length(btrim(policy_version)) > 0));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_schema_version_check CHECK ((length(btrim(schema_version)) > 0));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_source_byte_length_check CHECK ((source_byte_length >= 0));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_source_canonicalization_check CHECK ((length(btrim(source_canonicalization)) > 0));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_source_codepoint_length_check CHECK (((source_codepoint_length IS NULL) OR (source_codepoint_length >= 0)));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_source_sha256_check CHECK ((octet_length(source_sha256) = 32));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_source_version_id_generation_ordin_key UNIQUE (source_version_id, generation_ordinal);
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_source_view_check CHECK ((length(btrim(source_view)) > 0));
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_status_check CHECK ((status = ANY (ARRAY['open'::text, 'sealed'::text, 'aborted'::text])));
ALTER TABLE working.content_chunk_projection ADD CONSTRAINT content_chunk_projection_chunk_id_sink_key UNIQUE (chunk_id, sink);
ALTER TABLE working.content_chunk_projection ADD CONSTRAINT content_chunk_projection_pkey PRIMARY KEY (id);
ALTER TABLE working.content_chunk_projection ADD CONSTRAINT content_chunk_projection_sink_check CHECK ((sink = ANY (ARRAY['weaviate'::text, 'semantica'::text, 'sat_temporal'::text, 'opensearch'::text, 'surrealdb'::text])));
ALTER TABLE working.content_chunk_projection ADD CONSTRAINT content_chunk_projection_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'projected'::text, 'failed'::text, 'skipped'::text])));
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_check CHECK ((covered_range_end >= covered_range_start));
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_check1 CHECK (((verification_result <> 'exact'::text) OR ((source_sha256 = reassembled_sha256) AND (source_byte_length = reassembled_byte_length) AND (covered_range_end = source_byte_length) AND (gap_count = 0) AND (overlap_count = 0))));
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_chunk_count_check CHECK ((chunk_count >= 0));
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_covered_range_start_check CHECK ((covered_range_start = 0));
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_gap_count_check CHECK ((gap_count >= 0));
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_generation_id_key UNIQUE (generation_id);
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_member_count_check CHECK ((member_count >= 0));
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_overlap_count_check CHECK ((overlap_count >= 0));
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_pkey PRIMARY KEY (id);
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_reassembled_byte_length_check CHECK ((reassembled_byte_length >= 0));
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_reassembled_sha256_check CHECK ((octet_length(reassembled_sha256) = 32));
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_source_byte_length_check CHECK ((source_byte_length >= 0));
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_source_sha256_check CHECK ((octet_length(source_sha256) = 32));
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_verification_result_check CHECK ((verification_result = ANY (ARRAY['exact'::text, 'mismatch'::text, 'incomplete'::text, 'not_applicable'::text])));
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_verifier_id_check CHECK ((length(btrim(verifier_id)) > 0));
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_verifier_version_check CHECK ((length(btrim(verifier_version)) > 0));
ALTER TABLE working.content_chunk_source_span ADD CONSTRAINT content_chunk_source_span_chunk_id_member_ordinal_key UNIQUE (chunk_id, member_ordinal);
ALTER TABLE working.content_chunk_source_span ADD CONSTRAINT content_chunk_source_span_member_ordinal_check CHECK ((member_ordinal >= 0));
ALTER TABLE working.content_chunk_source_span ADD CONSTRAINT content_chunk_source_span_pkey PRIMARY KEY (id);
ALTER TABLE working.context_archive ADD CONSTRAINT context_archive_pkey PRIMARY KEY (id);
ALTER TABLE working.context_archive ADD CONSTRAINT uq_ctxarchive_sha UNIQUE (archive_sha256);
ALTER TABLE working.context_asset ADD CONSTRAINT context_asset_asset_category_check CHECK ((asset_category = ANY (ARRAY['document'::text, 'code'::text, 'image'::text, 'data'::text, 'other'::text])));
ALTER TABLE working.context_asset ADD CONSTRAINT context_asset_extraction_confidence_check CHECK (((extraction_confidence IS NULL) OR ((extraction_confidence >= (0)::double precision) AND (extraction_confidence <= (1)::double precision))));
ALTER TABLE working.context_asset ADD CONSTRAINT context_asset_extraction_status_check CHECK ((extraction_status = ANY (ARRAY['pending'::text, 'completed'::text, 'low_confidence'::text, 'unsupported'::text, 'failed'::text])));
ALTER TABLE working.context_asset ADD CONSTRAINT context_asset_modality_check CHECK ((modality = ANY (ARRAY['text'::text, 'code'::text, 'image'::text, 'audio'::text, 'video'::text, 'binary'::text])));
ALTER TABLE working.context_asset ADD CONSTRAINT context_asset_origin_kind_check CHECK ((origin_kind = ANY (ARRAY['generated_work'::text, 'attachment'::text, 'export_asset'::text, 'derived'::text])));
ALTER TABLE working.context_asset ADD CONSTRAINT context_asset_pkey PRIMARY KEY (id);
ALTER TABLE working.context_asset ADD CONSTRAINT uq_ctxasset_hash UNIQUE (content_hash);
ALTER TABLE working.context_asset_derivation ADD CONSTRAINT context_asset_derivation_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text));
ALTER TABLE working.context_asset_derivation ADD CONSTRAINT context_asset_derivation_check CHECK ((parent_asset_id <> child_asset_id));
ALTER TABLE working.context_asset_derivation ADD CONSTRAINT context_asset_derivation_derivation_type_check CHECK ((derivation_type = ANY (ARRAY['ocr'::text, 'transcript'::text, 'keyframe'::text, 'thumbnail'::text, 'text_extract'::text, 'conversion'::text])));
ALTER TABLE working.context_asset_derivation ADD CONSTRAINT context_asset_derivation_pkey PRIMARY KEY (parent_asset_id, child_asset_id, derivation_type);
ALTER TABLE working.context_asset_message ADD CONSTRAINT context_asset_message_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text));
ALTER TABLE working.context_asset_message ADD CONSTRAINT context_asset_message_pkey PRIMARY KEY (asset_id, message_id, relationship);
ALTER TABLE working.context_asset_message ADD CONSTRAINT context_asset_message_relationship_check CHECK ((relationship = ANY (ARRAY['generated_by'::text, 'attached_to'::text, 'referenced'::text])));
ALTER TABLE working.context_record ADD CONSTRAINT context_record_lane_check CHECK ((lane = 'context'::text));
ALTER TABLE working.context_record ADD CONSTRAINT context_record_pkey PRIMARY KEY (id);
ALTER TABLE working.context_record ADD CONSTRAINT context_record_record_type_check CHECK ((record_type = ANY (ARRAY['message'::text, 'call'::text, 'event'::text, 'media'::text])));
ALTER TABLE working.context_record ADD CONSTRAINT uq_ctxrec_content_hash UNIQUE (content_hash);
ALTER TABLE working.email ADD CONSTRAINT email_pkey PRIMARY KEY (id);
ALTER TABLE working.entity_mention ADD CONSTRAINT entity_mention_mention_kind_check CHECK ((mention_kind = ANY (ARRAY['name'::text, 'phone'::text, 'handle'::text, 'email'::text, 'pronoun'::text, 'partial'::text, 'address'::text, 'device'::text, 'other'::text])));
ALTER TABLE working.entity_mention ADD CONSTRAINT entity_mention_pkey PRIMARY KEY (id);
ALTER TABLE working.entity_resolution ADD CONSTRAINT entity_resolution_pkey PRIMARY KEY (id);
ALTER TABLE working.entity_resolution ADD CONSTRAINT entity_resolution_resolved_by_check CHECK ((resolved_by = ANY (ARRAY['rule'::text, 'model'::text, 'human'::text])));
ALTER TABLE working.event_source_record ADD CONSTRAINT esr_has_source CHECK (((record_id IS NOT NULL) OR (source_id IS NOT NULL) OR (raw_ref IS NOT NULL)));
ALTER TABLE working.event_source_record ADD CONSTRAINT event_source_record_has_anchor CHECK (((event_id IS NOT NULL) OR (record_id IS NOT NULL)));
ALTER TABLE working.event_source_record ADD CONSTRAINT event_source_record_pkey PRIMARY KEY (link_id);
ALTER TABLE working.event_source_record ADD CONSTRAINT event_source_record_role_check CHECK ((role = ANY (ARRAY['primary'::text, 'corroborating'::text, 'context'::text, 'contradicting'::text])));
ALTER TABLE working.evidence_vector_projection_job ADD CONSTRAINT evidence_vector_projection_job_attempts_check CHECK ((attempts >= 0));
ALTER TABLE working.evidence_vector_projection_job ADD CONSTRAINT evidence_vector_projection_job_authority_state_check CHECK ((authority_state = ANY (ARRAY['active'::text, 'revoked'::text, 'superseded'::text])));
ALTER TABLE working.evidence_vector_projection_job ADD CONSTRAINT evidence_vector_projection_job_check CHECK (((locked_at IS NULL) = (locked_by IS NULL)));
ALTER TABLE working.evidence_vector_projection_job ADD CONSTRAINT evidence_vector_projection_job_chunk_id_projection_version_key UNIQUE (chunk_id, projection_version);
ALTER TABLE working.evidence_vector_projection_job ADD CONSTRAINT evidence_vector_projection_job_generation_check CHECK ((generation >= 0));
ALTER TABLE working.evidence_vector_projection_job ADD CONSTRAINT evidence_vector_projection_job_pkey PRIMARY KEY (id);
ALTER TABLE working.evidence_vector_projection_job ADD CONSTRAINT evidence_vector_projection_job_projection_version_check CHECK ((length(projection_version) > 0));
ALTER TABLE working.evidence_vector_projection_job ADD CONSTRAINT evidence_vector_projection_job_reason_check CHECK ((length(reason) > 0));
ALTER TABLE working.evidence_vector_projection_job ADD CONSTRAINT evidence_vector_projection_job_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'completed'::text, 'failed'::text])));
ALTER TABLE working.extraction_run ADD CONSTRAINT extraction_run_finished_after_start CHECK (((finished_at IS NULL) OR (finished_at >= started_at)));
ALTER TABLE working.extraction_run ADD CONSTRAINT extraction_run_lifecycle_ck CHECK ((((status <> 'completed'::text) OR (finished_at IS NOT NULL)) AND ((status <> 'failed'::text) OR (error IS NOT NULL))));
ALTER TABLE working.extraction_run ADD CONSTRAINT extraction_run_pkey PRIMARY KEY (id);
ALTER TABLE working.extraction_run ADD CONSTRAINT extraction_run_stats_check CHECK ((jsonb_typeof(stats) = 'object'::text));
ALTER TABLE working.extraction_run ADD CONSTRAINT extraction_run_status_check CHECK ((status = ANY (ARRAY['running'::text, 'completed'::text, 'failed'::text])));
ALTER TABLE working.extraction_window ADD CONSTRAINT extraction_window_claims_emitted_check CHECK ((claims_emitted >= 0));
ALTER TABLE working.extraction_window ADD CONSTRAINT extraction_window_extraction_run_id_chat_conversation_id_or_key UNIQUE (extraction_run_id, chat_conversation_id, ordinal_range);
ALTER TABLE working.extraction_window ADD CONSTRAINT extraction_window_pkey PRIMARY KEY (id);
ALTER TABLE working.extraction_window ADD CONSTRAINT extraction_window_read_mode_check CHECK ((read_mode = ANY (ARRAY['full'::text, 'targeted_retrieval'::text, 'partial_truncated'::text])));
ALTER TABLE working.first_party_context_thread ADD CONSTRAINT first_party_context_thread_case_key_check CHECK ((case_key = 'primary'::text));
ALTER TABLE working.first_party_context_thread ADD CONSTRAINT first_party_context_thread_pkey PRIMARY KEY (context_thread_id);
ALTER TABLE working.first_party_context_thread_message ADD CONSTRAINT first_party_context_thread_me_thread_version_id_thread_ordi_key UNIQUE (thread_version_id, thread_ordinal);
ALTER TABLE working.first_party_context_thread_message ADD CONSTRAINT first_party_context_thread_message_check CHECK ((NOT (source_available_from IS DISTINCT FROM occurred_at)));
ALTER TABLE working.first_party_context_thread_message ADD CONSTRAINT first_party_context_thread_message_membership_confidence_check CHECK (((membership_confidence >= (0)::double precision) AND (membership_confidence <= (1)::double precision)));
ALTER TABLE working.first_party_context_thread_message ADD CONSTRAINT first_party_context_thread_message_pkey PRIMARY KEY (thread_version_id, message_id);
ALTER TABLE working.first_party_context_thread_message ADD CONSTRAINT first_party_context_thread_message_thread_ordinal_check CHECK ((thread_ordinal >= 0));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_so_thread_version_id_source_anch_key UNIQUE (thread_version_id, source_anchor_ordinal);
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_so_thread_version_id_source_vers_key UNIQUE (thread_version_id, source_version_id, assertion_version);
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_sou_metadata_extractor_version_check CHECK ((length(btrim(metadata_extractor_version)) > 0));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_sour_platform_conversation_key_check CHECK ((length(btrim(platform_conversation_key)) > 0));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_asserted_by_check CHECK ((length(btrim(asserted_by)) > 0));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_assertion_version_check CHECK ((assertion_version > 0));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_capture_kind_check CHECK ((length(btrim(capture_kind)) > 0));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_check CHECK (((coverage_last_occurred_at IS NULL) OR (coverage_first_occurred_at IS NULL) OR (coverage_last_occurred_at >= coverage_first_occurred_at)));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_check1 CHECK ((NOT (source_available_from IS DISTINCT FROM coverage_last_occurred_at)));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_confidence_check CHECK (((confidence >= (0)::double precision) AND (confidence <= (1)::double precision)));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_coverage_message_count_check CHECK (((coverage_message_count IS NULL) OR (coverage_message_count >= 0)));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_declared_format_check CHECK ((length(btrim(declared_format)) > 0));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_id_thread_version_id_key UNIQUE (id, thread_version_id);
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_metadata_clock_basis_check CHECK ((length(btrim(metadata_clock_basis)) > 0));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_metadata_clock_kind_check CHECK ((metadata_clock_kind = ANY (ARRAY['screenshot_capture'::text, 'export_created'::text, 'filesystem_observed'::text, 'other'::text])));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_metadata_confidence_check CHECK (((metadata_confidence IS NULL) OR ((metadata_confidence >= (0)::double precision) AND (metadata_confidence <= (1)::double precision))));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_metadata_extractor_id_check CHECK ((length(btrim(metadata_extractor_id)) > 0));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_metadata_review_state_check CHECK ((metadata_review_state = ANY (ARRAY['unreviewed'::text, 'approved'::text, 'rejected'::text, 'ambiguous'::text])));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_pkey PRIMARY KEY (id);
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_platform_check CHECK ((length(btrim(platform)) > 0));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_provenance_digest_check CHECK ((octet_length(provenance_digest) = 32));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_raw_metadata_check CHECK ((jsonb_typeof(raw_metadata) = 'object'::text));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_representation_kind_check CHECK ((representation_kind = ANY (ARRAY['native_export'::text, 'screenshot'::text, 'ocr_derived'::text, 'pdf'::text, 'html'::text, 'json'::text, 'xml'::text, 'csv'::text, 'other'::text])));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_review_state_check CHECK ((review_state = ANY (ARRAY['proposed'::text, 'approved'::text, 'rejected'::text, 'superseded'::text])));
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_source_anchor_ordinal_check CHECK ((source_anchor_ordinal >= 0));
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_ve_context_thread_id_version_ord_key UNIQUE (context_thread_id, version_ordinal);
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_version_assertion_digest_check CHECK ((octet_length(assertion_digest) = 32));
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_version_check CHECK (((first_occurred_at IS NULL) = (last_occurred_at IS NULL)));
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_version_check1 CHECK (((last_occurred_at IS NULL) OR (last_occurred_at >= first_occurred_at)));
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_version_check2 CHECK (((knowledge_available_from IS NULL) OR (first_occurred_at IS NULL) OR (knowledge_available_from >= first_occurred_at)));
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_version_check3 CHECK (((review_state <> 'approved'::text) OR ((reviewed_by IS NOT NULL) AND (reviewed_at IS NOT NULL))));
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_version_classifier_id_check CHECK ((length(btrim(classifier_id)) > 0));
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_version_classifier_version_check CHECK ((length(btrim(classifier_version)) > 0));
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_version_confidence_check CHECK (((confidence >= (0)::double precision) AND (confidence <= (1)::double precision)));
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_version_id_context_thread_id_key UNIQUE (id, context_thread_id);
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_version_pkey PRIMARY KEY (id);
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_version_review_state_check CHECK ((review_state = ANY (ARRAY['proposed'::text, 'approved'::text, 'rejected'::text, 'superseded'::text])));
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_version_version_ordinal_check CHECK ((version_ordinal > 0));
ALTER TABLE working.handle ADD CONSTRAINT handle_pkey PRIMARY KEY (id);
ALTER TABLE working.message ADD CONSTRAINT message_content_sha256_check CHECK (((content_sha256 IS NULL) OR (octet_length(content_sha256) = 32)));
ALTER TABLE working.message ADD CONSTRAINT message_direction_check CHECK ((direction = ANY (ARRAY['inbound'::text, 'outbound'::text, 'unknown'::text])));
ALTER TABLE working.message ADD CONSTRAINT message_pkey PRIMARY KEY (id);
ALTER TABLE working.message ADD CONSTRAINT message_projection_kind_ck CHECK ((projection_kind = 'first_party'::text));
ALTER TABLE working.message ADD CONSTRAINT message_requires_spine_ck CHECK ((derived_from_record_id IS NOT NULL)) NOT VALID;
ALTER TABLE working.message ADD CONSTRAINT uq_message_thread_extid UNIQUE (conversation_id, external_id);
ALTER TABLE working.message_participant ADD CONSTRAINT message_participant_pkey PRIMARY KEY (id);
ALTER TABLE working.message_participant ADD CONSTRAINT message_participant_role_check CHECK ((role = ANY (ARRAY['from'::text, 'to'::text, 'cc'::text, 'bcc'::text, 'group'::text, 'third_party'::text])));
ALTER TABLE working.message_participant ADD CONSTRAINT uq_msg_part UNIQUE (message_id, role, participant_raw);
ALTER TABLE working.message_projection_route ADD CONSTRAINT message_projection_route_basis_check CHECK ((jsonb_typeof(basis) = 'object'::text));
ALTER TABLE working.message_projection_route ADD CONSTRAINT message_projection_route_check CHECK (((approved_at IS NULL) = (decision_state = 'proposed'::text)));
ALTER TABLE working.message_projection_route ADD CONSTRAINT message_projection_route_check1 CHECK (((approved_by IS NULL) = (decision_state = 'proposed'::text)));
ALTER TABLE working.message_projection_route ADD CONSTRAINT message_projection_route_decision_state_check CHECK ((decision_state = ANY (ARRAY['proposed'::text, 'approved'::text])));
ALTER TABLE working.message_projection_route ADD CONSTRAINT message_projection_route_deriver_version_check CHECK ((length(deriver_version) > 0));
ALTER TABLE working.message_projection_route ADD CONSTRAINT message_projection_route_normalized_record_id_projection_ki_key UNIQUE (normalized_record_id, projection_kind);
ALTER TABLE working.message_projection_route ADD CONSTRAINT message_projection_route_pkey PRIMARY KEY (normalized_record_id);
ALTER TABLE working.message_projection_route ADD CONSTRAINT message_projection_route_projection_kind_check CHECK ((projection_kind = ANY (ARRAY['first_party'::text, 'acquired_third_party'::text])));
ALTER TABLE working.message_projection_route ADD CONSTRAINT message_projection_route_proposed_by_check CHECK ((length(proposed_by) > 0));
ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_case_id_ck CHECK ((length(case_id) > 0));
ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_disclosure_tier_check CHECK ((disclosure_tier = ANY (ARRAY['contemporaneous'::text, 'hindsight'::text, 'discovered'::text])));
ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_domain_ck CHECK ((domain = ANY (ARRAY['evidence'::text, 'legal'::text, 'behavioral'::text, 'platform_design'::text, 'context'::text])));
ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_message_corpus_ck CHECK (((message_corpus IS NULL) OR (message_corpus = ANY (ARRAY['first_party'::text, 'acquired_third_party'::text]))));
ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_pkey PRIMARY KEY (id);
ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_recipients_ck CHECK ((jsonb_typeof(recipients) = 'array'::text));
ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_record_type_check CHECK ((record_type = ANY (ARRAY['message'::text, 'call'::text, 'event'::text, 'media'::text])));
ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_source_hash_ck CHECK (((source_content_sha256 IS NULL) OR (octet_length(source_content_sha256) = 32)));
ALTER TABLE working.normalized_record ADD CONSTRAINT normrec_clock_ordering CHECK ((((realized_at IS NULL) OR (occurred_at IS NULL) OR (realized_at >= occurred_at)) AND ((acquired_at IS NULL) OR (occurred_at IS NULL) OR (acquired_at >= occurred_at)))) NOT VALID;
ALTER TABLE working.organization ADD CONSTRAINT organization_pkey PRIMARY KEY (id);
ALTER TABLE working.phone ADD CONSTRAINT phone_pkey PRIMARY KEY (id);
ALTER TABLE working.promotion ADD CONSTRAINT promotion_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text));
ALTER TABLE working.promotion ADD CONSTRAINT promotion_candidate_kind_check CHECK ((candidate_kind = ANY (ARRAY['entity'::text, 'fact'::text, 'event'::text])));
ALTER TABLE working.promotion ADD CONSTRAINT promotion_lane_check CHECK ((lane = ANY (ARRAY['as_lived'::text, 'hindsight'::text, 'consolidated'::text, 'support'::text])));
ALTER TABLE working.promotion ADD CONSTRAINT promotion_lane_matches_target CHECK (((lane = 'support'::text) OR ((lane = 'as_lived'::text) AND (target_system = 'graphiti_memory'::text)) OR ((lane = 'hindsight'::text) AND (target_system = ANY (ARRAY['semantica_graph'::text, 'postgres'::text]))) OR ((lane = 'consolidated'::text) AND (target_system = ANY (ARRAY['surrealdb'::text, 'postgres'::text])))));
ALTER TABLE working.promotion ADD CONSTRAINT promotion_pkey PRIMARY KEY (id);
ALTER TABLE working.promotion ADD CONSTRAINT promotion_revocation_has_reason CHECK (((revoked_at IS NULL) OR (revoked_reason IS NOT NULL)));
ALTER TABLE working.promotion ADD CONSTRAINT promotion_target_system_check CHECK ((target_system = ANY (ARRAY['postgres'::text, 'surrealdb'::text, 'semantica_graph'::text, 'graphiti_memory'::text, 'weaviate'::text])));
ALTER TABLE working.realization_event ADD CONSTRAINT realization_event_approval_state_check CHECK ((approval_state = ANY (ARRAY['proposed'::text, 'approved'::text, 'superseded'::text])));
ALTER TABLE working.realization_event ADD CONSTRAINT realization_event_case_id_check CHECK ((length(case_id) > 0));
ALTER TABLE working.realization_event ADD CONSTRAINT realization_event_check CHECK (((approved_at IS NULL) = (approval_state = 'proposed'::text)));
ALTER TABLE working.realization_event ADD CONSTRAINT realization_event_check1 CHECK (((approved_by IS NULL) = (approval_state = 'proposed'::text)));
ALTER TABLE working.realization_event ADD CONSTRAINT realization_event_evidence_pointer_check CHECK ((jsonb_typeof(evidence_pointer) = 'object'::text));
ALTER TABLE working.realization_event ADD CONSTRAINT realization_event_kind_check CHECK ((kind = ANY (ARRAY['contradiction'::text, 'export_read'::text, 'told_by_person'::text, 'manual'::text, 'betrayal'::text, 'deceit'::text, 'gaslighting'::text, 'pattern_recognition'::text])));
ALTER TABLE working.realization_event ADD CONSTRAINT realization_event_pkey PRIMARY KEY (id);
ALTER TABLE working.realization_event ADD CONSTRAINT realization_event_proposer_check CHECK ((proposer = ANY (ARRAY['algorithm'::text, 'owner'::text])));
ALTER TABLE working.realization_event_record ADD CONSTRAINT realization_event_record_case_id_check CHECK ((length(case_id) > 0));
ALTER TABLE working.realization_event_record ADD CONSTRAINT realization_event_record_pkey PRIMARY KEY (realization_event_id, normalized_record_id);
ALTER TABLE working.record_visible_from ADD CONSTRAINT record_visible_from_pkey PRIMARY KEY (record_id);
ALTER TABLE working.record_visible_from ADD CONSTRAINT record_visible_from_source_clock_hash_check CHECK ((length(source_clock_hash) = 64));
ALTER TABLE working.source_provenance ADD CONSTRAINT source_provenance_acquisition_authority_check CHECK ((acquisition_authority = ANY (ARRAY['device_owner'::text, 'parent_guardian'::text, 'account_holder'::text, 'consent_given'::text, 'court_order'::text, 'unclear'::text])));
ALTER TABLE working.source_provenance ADD CONSTRAINT source_provenance_acquisition_method_check CHECK ((acquisition_method = ANY (ARRAY['own_device'::text, 'household_device'::text, 'voluntary_third_party'::text, 'legal_process'::text, 'public_source'::text, 'unknown'::text])));
ALTER TABLE working.source_provenance ADD CONSTRAINT source_provenance_artifact_clock_order CHECK ((((export_created_at IS NULL) OR (acquired_at IS NULL) OR (acquired_at >= export_created_at)) AND ((acquired_at IS NULL) OR (ingested_at IS NULL) OR (ingested_at >= acquired_at))));
ALTER TABLE working.source_provenance ADD CONSTRAINT source_provenance_asserted_by_kind_check CHECK ((asserted_by_kind = 'human'::text));
ALTER TABLE working.source_provenance ADD CONSTRAINT source_provenance_pkey PRIMARY KEY (id);
ALTER TABLE working.source_provenance ADD CONSTRAINT source_provenance_realized_after_acquired CHECK (((realized_at IS NULL) OR (acquired_at IS NULL) OR (realized_at >= acquired_at)));
ALTER TABLE working.source_provenance ADD CONSTRAINT source_provenance_realized_at_state_check CHECK ((realized_at_state = ANY (ARRAY['unset'::text, 'proposed'::text, 'confirmed'::text, 'corrected'::text])));
ALTER TABLE working.source_provenance ADD CONSTRAINT source_provenance_realized_state_agrees CHECK (((realized_at IS NULL) = (realized_at_state = 'unset'::text)));
ALTER TABLE working.source_provenance ADD CONSTRAINT source_provenance_revision_check CHECK ((revision > 0));
ALTER TABLE working.temporal_anchor ADD CONSTRAINT anchor_ordering CHECK ((valid_earliest <= valid_latest));
ALTER TABLE working.temporal_anchor ADD CONSTRAINT temporal_anchor_anchor_key_key UNIQUE (anchor_key);
ALTER TABLE working.temporal_anchor ADD CONSTRAINT temporal_anchor_pkey PRIMARY KEY (anchor_id);
ALTER TABLE working.third_party_context_thread ADD CONSTRAINT third_party_context_thread_case_key_check CHECK ((case_key = 'primary'::text));
ALTER TABLE working.third_party_context_thread ADD CONSTRAINT third_party_context_thread_pkey PRIMARY KEY (context_thread_id);
ALTER TABLE working.third_party_context_thread_message ADD CONSTRAINT third_party_context_thread_me_thread_version_id_thread_ordi_key UNIQUE (thread_version_id, thread_ordinal);
ALTER TABLE working.third_party_context_thread_message ADD CONSTRAINT third_party_context_thread_message_membership_confidence_check CHECK (((membership_confidence >= (0)::double precision) AND (membership_confidence <= (1)::double precision)));
ALTER TABLE working.third_party_context_thread_message ADD CONSTRAINT third_party_context_thread_message_pkey PRIMARY KEY (thread_version_id, message_id);
ALTER TABLE working.third_party_context_thread_message ADD CONSTRAINT third_party_context_thread_message_thread_ordinal_check CHECK ((thread_ordinal >= 0));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_so_thread_version_id_source_anch_key UNIQUE (thread_version_id, source_anchor_ordinal);
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_so_thread_version_id_source_vers_key UNIQUE (thread_version_id, source_version_id, assertion_version);
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_sou_metadata_extractor_version_check CHECK ((length(btrim(metadata_extractor_version)) > 0));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_sour_platform_conversation_key_check CHECK ((length(btrim(platform_conversation_key)) > 0));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_asserted_by_check CHECK ((length(btrim(asserted_by)) > 0));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_assertion_version_check CHECK ((assertion_version > 0));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_capture_kind_check CHECK ((length(btrim(capture_kind)) > 0));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_check CHECK (((coverage_last_occurred_at IS NULL) OR (coverage_first_occurred_at IS NULL) OR (coverage_last_occurred_at >= coverage_first_occurred_at)));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_confidence_check CHECK (((confidence >= (0)::double precision) AND (confidence <= (1)::double precision)));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_coverage_message_count_check CHECK (((coverage_message_count IS NULL) OR (coverage_message_count >= 0)));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_declared_format_check CHECK ((length(btrim(declared_format)) > 0));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_id_thread_version_id_key UNIQUE (id, thread_version_id);
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_metadata_clock_basis_check CHECK ((length(btrim(metadata_clock_basis)) > 0));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_metadata_clock_kind_check CHECK ((metadata_clock_kind = ANY (ARRAY['screenshot_capture'::text, 'export_created'::text, 'filesystem_observed'::text, 'other'::text])));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_metadata_confidence_check CHECK (((metadata_confidence IS NULL) OR ((metadata_confidence >= (0)::double precision) AND (metadata_confidence <= (1)::double precision))));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_metadata_extractor_id_check CHECK ((length(btrim(metadata_extractor_id)) > 0));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_metadata_review_state_check CHECK ((metadata_review_state = ANY (ARRAY['unreviewed'::text, 'approved'::text, 'rejected'::text, 'ambiguous'::text])));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_pkey PRIMARY KEY (id);
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_platform_check CHECK ((length(btrim(platform)) > 0));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_provenance_digest_check CHECK ((octet_length(provenance_digest) = 32));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_raw_metadata_check CHECK ((jsonb_typeof(raw_metadata) = 'object'::text));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_representation_kind_check CHECK ((representation_kind = ANY (ARRAY['native_export'::text, 'screenshot'::text, 'ocr_derived'::text, 'pdf'::text, 'html'::text, 'json'::text, 'xml'::text, 'csv'::text, 'other'::text])));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_review_state_check CHECK ((review_state = ANY (ARRAY['proposed'::text, 'approved'::text, 'rejected'::text, 'superseded'::text])));
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_source_anchor_ordinal_check CHECK ((source_anchor_ordinal >= 0));
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_ve_context_thread_id_version_ord_key UNIQUE (context_thread_id, version_ordinal);
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_version_assertion_digest_check CHECK ((octet_length(assertion_digest) = 32));
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_version_check CHECK (((first_occurred_at IS NULL) = (last_occurred_at IS NULL)));
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_version_check1 CHECK (((last_occurred_at IS NULL) OR (last_occurred_at >= first_occurred_at)));
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_version_check2 CHECK (((knowledge_available_from IS NULL) OR (first_occurred_at IS NULL) OR (knowledge_available_from >= first_occurred_at)));
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_version_check3 CHECK (((review_state <> 'approved'::text) OR ((reviewed_by IS NOT NULL) AND (reviewed_at IS NOT NULL))));
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_version_classifier_id_check CHECK ((length(btrim(classifier_id)) > 0));
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_version_classifier_version_check CHECK ((length(btrim(classifier_version)) > 0));
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_version_confidence_check CHECK (((confidence >= (0)::double precision) AND (confidence <= (1)::double precision)));
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_version_id_context_thread_id_key UNIQUE (id, context_thread_id);
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_version_pkey PRIMARY KEY (id);
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_version_review_state_check CHECK ((review_state = ANY (ARRAY['proposed'::text, 'approved'::text, 'rejected'::text, 'superseded'::text])));
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_version_version_ordinal_check CHECK ((version_ordinal > 0));
ALTER TABLE working.third_party_conversation ADD CONSTRAINT third_party_conversation_case_id_check CHECK ((length(case_id) > 0));
ALTER TABLE working.third_party_conversation ADD CONSTRAINT third_party_conversation_check CHECK (((ended_at IS NULL) OR (started_at IS NULL) OR (ended_at >= started_at)));
ALTER TABLE working.third_party_conversation ADD CONSTRAINT third_party_conversation_deriver_version_check CHECK ((length(deriver_version) > 0));
ALTER TABLE working.third_party_conversation ADD CONSTRAINT third_party_conversation_external_thread_key_check CHECK ((length(external_thread_key) > 0));
ALTER TABLE working.third_party_conversation ADD CONSTRAINT third_party_conversation_message_count_check CHECK ((message_count >= 0));
ALTER TABLE working.third_party_conversation ADD CONSTRAINT third_party_conversation_pkey PRIMARY KEY (id);
ALTER TABLE working.third_party_conversation ADD CONSTRAINT third_party_conversation_platform_attrs_check CHECK ((jsonb_typeof(platform_attrs) = 'object'::text));
ALTER TABLE working.third_party_conversation ADD CONSTRAINT third_party_conversation_platform_check CHECK ((length(platform) > 0));
ALTER TABLE working.third_party_conversation ADD CONSTRAINT third_party_conversation_review_status_check CHECK ((review_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
ALTER TABLE working.third_party_conversation ADD CONSTRAINT third_party_conversation_source_artifact_id_platform_extern_key UNIQUE (source_artifact_id, platform, external_thread_key);
ALTER TABLE working.third_party_conversation_acquisition ADD CONSTRAINT third_party_conversation_acqu_conversation_id_acquisition_i_key UNIQUE (conversation_id, acquisition_id);
ALTER TABLE working.third_party_conversation_acquisition ADD CONSTRAINT third_party_conversation_acquisition_approval_state_check CHECK ((approval_state = ANY (ARRAY['proposed'::text, 'approved'::text, 'superseded'::text])));
ALTER TABLE working.third_party_conversation_acquisition ADD CONSTRAINT third_party_conversation_acquisition_check CHECK (((approved_at IS NULL) = (approval_state = 'proposed'::text)));
ALTER TABLE working.third_party_conversation_acquisition ADD CONSTRAINT third_party_conversation_acquisition_check1 CHECK (((approved_by IS NULL) = (approval_state = 'proposed'::text)));
ALTER TABLE working.third_party_conversation_acquisition ADD CONSTRAINT third_party_conversation_acquisition_pkey PRIMARY KEY (id);
ALTER TABLE working.third_party_conversation_acquisition ADD CONSTRAINT third_party_conversation_acquisition_proposed_by_check CHECK ((length(proposed_by) > 0));
ALTER TABLE working.third_party_message ADD CONSTRAINT third_party_message_content_sha256_check CHECK (((content_sha256 IS NULL) OR (octet_length(content_sha256) = 32)));
ALTER TABLE working.third_party_message ADD CONSTRAINT third_party_message_deriver_version_check CHECK ((length(deriver_version) > 0));
ALTER TABLE working.third_party_message ADD CONSTRAINT third_party_message_message_type_check CHECK ((length(message_type) > 0));
ALTER TABLE working.third_party_message ADD CONSTRAINT third_party_message_normalized_record_id_key UNIQUE (normalized_record_id);
ALTER TABLE working.third_party_message ADD CONSTRAINT third_party_message_pkey PRIMARY KEY (id);
ALTER TABLE working.third_party_message ADD CONSTRAINT third_party_message_platform_attrs_check CHECK ((jsonb_typeof(platform_attrs) = 'object'::text));
ALTER TABLE working.third_party_message ADD CONSTRAINT third_party_message_platform_check CHECK ((length(platform) > 0));
ALTER TABLE working.third_party_message ADD CONSTRAINT third_party_message_projection_kind_check CHECK ((projection_kind = 'acquired_third_party'::text));
ALTER TABLE working.third_party_message_participant ADD CONSTRAINT third_party_message_participant_deriver_version_check CHECK ((length(deriver_version) > 0));
ALTER TABLE working.third_party_message_participant ADD CONSTRAINT third_party_message_participant_message_id_entity_id_role_key UNIQUE (message_id, entity_id, role);
ALTER TABLE working.third_party_message_participant ADD CONSTRAINT third_party_message_participant_participant_raw_check CHECK ((length(participant_raw) > 0));
ALTER TABLE working.third_party_message_participant ADD CONSTRAINT third_party_message_participant_pkey PRIMARY KEY (id);
ALTER TABLE working.third_party_message_participant ADD CONSTRAINT third_party_message_participant_role_check CHECK ((role = ANY (ARRAY['from'::text, 'to'::text, 'cc'::text, 'bcc'::text, 'group'::text])));
ALTER TABLE working.walk_checkpoint ADD CONSTRAINT walk_checkpoint_base_version_check CHECK ((length(base_version) > 0));
ALTER TABLE working.walk_checkpoint ADD CONSTRAINT walk_checkpoint_belief_state_check CHECK ((jsonb_typeof(belief_state) = 'object'::text));
ALTER TABLE working.walk_checkpoint ADD CONSTRAINT walk_checkpoint_chain_hash_check CHECK ((length(chain_hash) = 64));
ALTER TABLE working.walk_checkpoint ADD CONSTRAINT walk_checkpoint_check CHECK ((((checkpoint_kind = 'healthy'::text) AND is_resumable AND (failure IS NULL)) OR ((checkpoint_kind = 'failure_seal'::text) AND (NOT is_resumable) AND (failure IS NOT NULL))));
ALTER TABLE working.walk_checkpoint ADD CONSTRAINT walk_checkpoint_checkpoint_kind_check CHECK ((checkpoint_kind = ANY (ARRAY['healthy'::text, 'failure_seal'::text])));
ALTER TABLE working.walk_checkpoint ADD CONSTRAINT walk_checkpoint_checkpoint_no_check CHECK ((checkpoint_no >= 0));
ALTER TABLE working.walk_checkpoint ADD CONSTRAINT walk_checkpoint_cursor_check CHECK ((jsonb_typeof(cursor) = 'object'::text));
ALTER TABLE working.walk_checkpoint ADD CONSTRAINT walk_checkpoint_failure_check CHECK (((failure IS NULL) OR (jsonb_typeof(failure) = 'object'::text)));
ALTER TABLE working.walk_checkpoint ADD CONSTRAINT walk_checkpoint_horizon_hash_check CHECK ((length(horizon_hash) = 64));
ALTER TABLE working.walk_checkpoint ADD CONSTRAINT walk_checkpoint_id_walk_run_id_key UNIQUE (id, walk_run_id);
ALTER TABLE working.walk_checkpoint ADD CONSTRAINT walk_checkpoint_last_completed_step_no_check CHECK ((last_completed_step_no >= 0));
ALTER TABLE working.walk_checkpoint ADD CONSTRAINT walk_checkpoint_pkey PRIMARY KEY (id);
ALTER TABLE working.walk_checkpoint ADD CONSTRAINT walk_checkpoint_walk_run_id_checkpoint_no_key UNIQUE (walk_run_id, checkpoint_no);
ALTER TABLE working.walk_run ADD CONSTRAINT walk_run_case_id_check CHECK ((length(case_id) > 0));
ALTER TABLE working.walk_run ADD CONSTRAINT walk_run_check CHECK (((horizon_policy <> 'custom'::text) OR (horizon_ceiling IS NOT NULL)));
ALTER TABLE working.walk_run ADD CONSTRAINT walk_run_horizon_policy_check CHECK ((horizon_policy = ANY (ARRAY['ignorant'::text, 'hindsight'::text, 'custom'::text])));
ALTER TABLE working.walk_run ADD CONSTRAINT walk_run_parameters_check CHECK ((jsonb_typeof(parameters) = 'object'::text));
ALTER TABLE working.walk_run ADD CONSTRAINT walk_run_pkey PRIMARY KEY (id);
ALTER TABLE working.walk_run ADD CONSTRAINT walk_run_status_check CHECK ((status = ANY (ARRAY['running'::text, 'paused'::text, 'completed'::text, 'sealed'::text, 'failed'::text, 'invalidated'::text])));
ALTER TABLE working.walk_step ADD CONSTRAINT walk_step_belief_check CHECK (((belief IS NULL) OR (jsonb_typeof(belief) = 'object'::text)));
ALTER TABLE working.walk_step ADD CONSTRAINT walk_step_confidence_check CHECK (((confidence IS NULL) OR ((confidence >= (0)::double precision) AND (confidence <= (1)::double precision))));
ALTER TABLE working.walk_step ADD CONSTRAINT walk_step_pkey PRIMARY KEY (id);
ALTER TABLE working.walk_step ADD CONSTRAINT walk_step_walk_run_id_step_no_key UNIQUE (walk_run_id, step_no);
ALTER TABLE working.walk_step_realization_retrieval ADD CONSTRAINT walk_step_realization_retriev_walk_step_id_realization_even_key UNIQUE (walk_step_id, realization_event_id, store);
ALTER TABLE working.walk_step_realization_retrieval ADD CONSTRAINT walk_step_realization_retrieval_pkey PRIMARY KEY (id);
ALTER TABLE working.walk_step_realization_retrieval ADD CONSTRAINT walk_step_realization_retrieval_store_check CHECK ((store = ANY (ARRAY['postgres'::text, 'weaviate'::text, 'graphiti'::text, 'neo4j'::text, 'other'::text])));
ALTER TABLE working.walk_step_retrieval ADD CONSTRAINT walk_step_retrieval_pkey PRIMARY KEY (id);
ALTER TABLE working.walk_step_retrieval ADD CONSTRAINT walk_step_retrieval_store_check CHECK ((store = ANY (ARRAY['postgres'::text, 'weaviate'::text, 'graphiti'::text, 'neo4j'::text, 'other'::text])));
ALTER TABLE working.walk_step_retrieval ADD CONSTRAINT walk_step_retrieval_walk_step_id_record_id_store_key UNIQUE (walk_step_id, record_id, store);

-- ============ foreign keys (after all tables exist) ============
ALTER TABLE ai.agno_component_configs ADD CONSTRAINT agno_component_configs_component_id_fkey FOREIGN KEY (component_id) REFERENCES agno_components(component_id);
ALTER TABLE ai.agno_component_links ADD CONSTRAINT agno_component_links_child_component_id_fkey FOREIGN KEY (child_component_id) REFERENCES agno_components(component_id);
ALTER TABLE ai.agno_component_links ADD CONSTRAINT agno_component_links_parent_component_id_parent_version_fkey FOREIGN KEY (parent_component_id, parent_version) REFERENCES agno_component_configs(component_id, version);
ALTER TABLE ai.agno_schedule_runs ADD CONSTRAINT agno_schedule_runs_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES agno_schedules(id) ON DELETE CASCADE;
ALTER TABLE ai.agno_spans ADD CONSTRAINT agno_spans_trace_id_fkey FOREIGN KEY (trace_id) REFERENCES agno_traces(trace_id);
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_case_scope_fk FOREIGN KEY (court_case_id, matter_id) REFERENCES registry.court_case(id, matter_id) ON DELETE RESTRICT;
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_partition_scope_fk FOREIGN KEY (partition_key, matter_id) REFERENCES analysis.matter_knowledge_partition(partition_key, matter_id) ON DELETE RESTRICT;
ALTER TABLE analysis.case_registry_import_receipt ADD CONSTRAINT case_registry_import_receipt_matter_id_fkey FOREIGN KEY (matter_id) REFERENCES registry.matter(id) ON DELETE RESTRICT;
ALTER TABLE analysis.claim_assertion ADD CONSTRAINT claim_assertion_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES analysis.claim_assertion(id) ON DELETE RESTRICT;
ALTER TABLE analysis.claim_assertion_member ADD CONSTRAINT claim_assertion_member_assertion_id_fkey FOREIGN KEY (assertion_id) REFERENCES analysis.claim_assertion(id) ON DELETE CASCADE;
ALTER TABLE analysis.claim_assertion_member ADD CONSTRAINT claim_assertion_member_claim_candidate_id_fkey FOREIGN KEY (claim_candidate_id) REFERENCES working.claim_candidate(id) ON DELETE RESTRICT;
ALTER TABLE analysis.claim_assertion_synthesis_member ADD CONSTRAINT claim_assertion_synthesis_member_synthesis_id_fkey FOREIGN KEY (synthesis_id) REFERENCES analysis.claim_assertion(id) ON DELETE CASCADE;
ALTER TABLE analysis.claim_assertion_synthesis_member ADD CONSTRAINT synthesis_member_is_generation_one FOREIGN KEY (member_assertion_id, member_generation) REFERENCES analysis.claim_assertion(id, assertion_generation) ON DELETE RESTRICT;
ALTER TABLE analysis.completion_evidence ADD CONSTRAINT completion_evidence_evidence_hash_id_fkey FOREIGN KEY (evidence_hash_id) REFERENCES evidence.evidence_hash(id);
ALTER TABLE analysis.completion_evidence ADD CONSTRAINT completion_evidence_evidence_item_id_fkey FOREIGN KEY (evidence_item_id) REFERENCES evidence.evidence_item(id);
ALTER TABLE analysis.completion_evidence ADD CONSTRAINT completion_evidence_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE analysis.completion_evidence ADD CONSTRAINT completion_evidence_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.evidence_task(id);
ALTER TABLE analysis.content_chunk_classification_decision ADD CONSTRAINT content_chunk_classification_decision_chunk_id_fkey FOREIGN KEY (chunk_id) REFERENCES working.content_chunk(id) ON DELETE RESTRICT;
ALTER TABLE analysis.content_chunk_classification_decision ADD CONSTRAINT content_chunk_classification_decision_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES analysis.content_chunk_classification_decision(id) ON DELETE RESTRICT;
ALTER TABLE analysis.discovery_request ADD CONSTRAINT discovery_request_target_person_id_fkey FOREIGN KEY (target_person_id) REFERENCES registry.person(id);
ALTER TABLE analysis.discovery_request ADD CONSTRAINT discovery_request_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.evidence_task(id);
ALTER TABLE analysis.discovery_request_revision ADD CONSTRAINT discovery_request_revision_request_id_fkey FOREIGN KEY (request_id) REFERENCES analysis.discovery_request(id);
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_finding_id_fkey FOREIGN KEY (finding_id) REFERENCES analysis.finding(id);
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_likely_source_id_fkey FOREIGN KEY (likely_source_id) REFERENCES evidence.source(id);
ALTER TABLE analysis.evidence_task ADD CONSTRAINT evidence_task_source_run_id_fkey FOREIGN KEY (source_run_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE analysis.export ADD CONSTRAINT export_export_run_fkey FOREIGN KEY (export_run) REFERENCES ops.processing_run(run_id);
ALTER TABLE analysis.export_item ADD CONSTRAINT export_item_evidence_item_id_fkey FOREIGN KEY (evidence_item_id) REFERENCES evidence.evidence_item(id);
ALTER TABLE analysis.export_item ADD CONSTRAINT export_item_package_id_fkey FOREIGN KEY (package_id) REFERENCES analysis.export_package(id);
ALTER TABLE analysis.factor_citation ADD CONSTRAINT factor_citation_evidence_item_id_fkey FOREIGN KEY (evidence_item_id) REFERENCES evidence.evidence_item(id);
ALTER TABLE analysis.factor_citation ADD CONSTRAINT factor_citation_factor_fkey FOREIGN KEY (factor) REFERENCES reference.custody_factor(factor);
ALTER TABLE analysis.factor_citation ADD CONSTRAINT factor_citation_legal_issue_id_fkey FOREIGN KEY (legal_issue_id) REFERENCES reference.legal_issue(id);
ALTER TABLE analysis.factor_citation ADD CONSTRAINT factor_citation_supersedes_citation_id_fkey FOREIGN KEY (supersedes_citation_id) REFERENCES analysis.factor_citation(id);
ALTER TABLE analysis.finding ADD CONSTRAINT finding_contradicts_finding_id_fkey FOREIGN KEY (contradicts_finding_id) REFERENCES analysis.finding(id);
ALTER TABLE analysis.finding ADD CONSTRAINT finding_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE analysis.finding_version ADD CONSTRAINT finding_version_finding_id_fkey FOREIGN KEY (finding_id) REFERENCES analysis.finding(id);
ALTER TABLE analysis.graphrag_comparison_join ADD CONSTRAINT graphrag_comparison_join_manifest_id_fkey FOREIGN KEY (manifest_id) REFERENCES analysis.graphrag_eligibility_manifest(id) ON DELETE CASCADE;
ALTER TABLE analysis.graphrag_comparison_join ADD CONSTRAINT graphrag_comparison_join_run_id_fkey FOREIGN KEY (run_id) REFERENCES analysis.graphrag_comparison_run(id) ON DELETE CASCADE;
ALTER TABLE analysis.graphrag_comparison_join ADD CONSTRAINT graphrag_comparison_join_sat_temporal_receipt_id_fkey FOREIGN KEY (sat_temporal_receipt_id) REFERENCES analysis.graphrag_lane_receipt(id) ON DELETE SET NULL;
ALTER TABLE analysis.graphrag_comparison_join ADD CONSTRAINT graphrag_comparison_join_semantica_receipt_id_fkey FOREIGN KEY (semantica_receipt_id) REFERENCES analysis.graphrag_lane_receipt(id) ON DELETE SET NULL;
ALTER TABLE analysis.graphrag_eligibility_manifest ADD CONSTRAINT graphrag_eligibility_manifest_run_id_fkey FOREIGN KEY (run_id) REFERENCES analysis.graphrag_comparison_run(id) ON DELETE CASCADE;
ALTER TABLE analysis.graphrag_eligibility_manifest_member ADD CONSTRAINT graphrag_eligibility_manifest_member_manifest_id_fkey FOREIGN KEY (manifest_id) REFERENCES analysis.graphrag_eligibility_manifest(id) ON DELETE CASCADE;
ALTER TABLE analysis.graphrag_lane_candidate ADD CONSTRAINT graphrag_lane_candidate_lane_result_id_fkey FOREIGN KEY (lane_result_id) REFERENCES analysis.graphrag_lane_result(id) ON DELETE CASCADE;
ALTER TABLE analysis.graphrag_lane_receipt ADD CONSTRAINT graphrag_lane_receipt_lane_result_id_fkey FOREIGN KEY (lane_result_id) REFERENCES analysis.graphrag_lane_result(id) ON DELETE SET NULL;
ALTER TABLE analysis.graphrag_lane_receipt ADD CONSTRAINT graphrag_lane_receipt_manifest_id_fkey FOREIGN KEY (manifest_id) REFERENCES analysis.graphrag_eligibility_manifest(id) ON DELETE CASCADE;
ALTER TABLE analysis.graphrag_lane_receipt ADD CONSTRAINT graphrag_lane_receipt_run_id_fkey FOREIGN KEY (run_id) REFERENCES analysis.graphrag_comparison_run(id) ON DELETE CASCADE;
ALTER TABLE analysis.graphrag_lane_result ADD CONSTRAINT graphrag_lane_result_manifest_id_fkey FOREIGN KEY (manifest_id) REFERENCES analysis.graphrag_eligibility_manifest(id) ON DELETE CASCADE;
ALTER TABLE analysis.graphrag_lane_result ADD CONSTRAINT graphrag_lane_result_run_id_fkey FOREIGN KEY (run_id) REFERENCES analysis.graphrag_comparison_run(id) ON DELETE CASCADE;
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_case_fkey FOREIGN KEY (court_case_id, matter_id) REFERENCES registry.court_case(id, matter_id) ON DELETE RESTRICT;
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_file_node_fkey FOREIGN KEY (file_node_id) REFERENCES raw.file_node(id) ON DELETE RESTRICT;
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_hash_fkey FOREIGN KEY (evidence_hash_id) REFERENCES evidence.evidence_hash(id) ON DELETE RESTRICT;
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_item_scope_fkey FOREIGN KEY (evidence_item_id, matter_id, court_case_id) REFERENCES evidence.evidence_item(id, matter_id, court_case_id) ON DELETE RESTRICT;
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_partition_fkey FOREIGN KEY (partition_key, matter_id) REFERENCES analysis.matter_knowledge_partition(partition_key, matter_id) ON DELETE RESTRICT;
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_record_fkey FOREIGN KEY (normalized_record_id) REFERENCES working.normalized_record(id) ON DELETE RESTRICT;
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_run_fkey FOREIGN KEY (source_run_id) REFERENCES ops.processing_run(run_id) ON DELETE RESTRICT;
ALTER TABLE analysis.knowledge_evidence_promotion ADD CONSTRAINT knowledge_evidence_promotion_source_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id) ON DELETE RESTRICT;
ALTER TABLE analysis.location_assertion ADD CONSTRAINT location_assertion_location_id_fkey FOREIGN KEY (location_id) REFERENCES registry.location(id);
ALTER TABLE analysis.location_assertion ADD CONSTRAINT location_assertion_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE analysis.location_contradiction ADD CONSTRAINT location_contradiction_claimed_assertion_id_fkey FOREIGN KEY (claimed_assertion_id) REFERENCES analysis.location_assertion(id);
ALTER TABLE analysis.location_contradiction ADD CONSTRAINT location_contradiction_observed_assertion_id_fkey FOREIGN KEY (observed_assertion_id) REFERENCES analysis.location_assertion(id);
ALTER TABLE analysis.location_contradiction ADD CONSTRAINT location_contradiction_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE analysis.matter_knowledge_partition ADD CONSTRAINT matter_knowledge_partition_default_case_fkey FOREIGN KEY (default_court_case_id, matter_id) REFERENCES registry.court_case(id, matter_id) ON DELETE RESTRICT;
ALTER TABLE analysis.matter_knowledge_partition ADD CONSTRAINT matter_knowledge_partition_matter_fkey FOREIGN KEY (matter_id) REFERENCES registry.matter(id) ON DELETE RESTRICT;
ALTER TABLE analysis.pattern_finding ADD CONSTRAINT pattern_finding_category_id_fkey FOREIGN KEY (category_id) REFERENCES reference.behavior_category(category_id);
ALTER TABLE analysis.pattern_finding ADD CONSTRAINT pattern_finding_finding_id_fkey FOREIGN KEY (finding_id) REFERENCES analysis.finding(id);
ALTER TABLE analysis.pattern_finding ADD CONSTRAINT pattern_finding_pattern_id_fkey FOREIGN KEY (pattern_id) REFERENCES reference.detection_pattern(id);
ALTER TABLE analysis.pattern_finding ADD CONSTRAINT pattern_finding_pattern_set_id_fkey FOREIGN KEY (pattern_set_id) REFERENCES reference.detection_pattern_set(id);
ALTER TABLE analysis.pattern_finding ADD CONSTRAINT pattern_finding_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE analysis.redaction ADD CONSTRAINT redaction_redacted_artifact_fkey FOREIGN KEY (redacted_artifact) REFERENCES working.artifact_registry(artifact_id);
ALTER TABLE analysis.redaction ADD CONSTRAINT redaction_redaction_run_fkey FOREIGN KEY (redaction_run) REFERENCES ops.processing_run(run_id);
ALTER TABLE analysis.redaction ADD CONSTRAINT redaction_source_artifact_fkey FOREIGN KEY (source_artifact) REFERENCES working.artifact_registry(artifact_id);
ALTER TABLE analysis.relational_classification ADD CONSTRAINT relational_classification_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE analysis.resolution_evidence ADD CONSTRAINT resolution_evidence_resolution_id_fkey FOREIGN KEY (resolution_id) REFERENCES working.entity_resolution(id);
ALTER TABLE analysis.review_decision ADD CONSTRAINT review_decision_ontology_version_id_fkey FOREIGN KEY (ontology_version_id) REFERENCES ontology_version(ontology_version_id);
ALTER TABLE analysis.review_decision ADD CONSTRAINT review_decision_prompt_version_id_fkey FOREIGN KEY (prompt_version_id) REFERENCES prompt_registry(prompt_id);
ALTER TABLE analysis.review_decision ADD CONSTRAINT review_decision_schema_version_id_fkey FOREIGN KEY (schema_version_id) REFERENCES schema_version(schema_version_id);
ALTER TABLE analysis.review_decision ADD CONSTRAINT review_decision_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.review_task(task_id);
ALTER TABLE analysis.score ADD CONSTRAINT score_config_version_fkey FOREIGN KEY (config_version) REFERENCES reference.score_band_config(config_version);
ALTER TABLE analysis.score ADD CONSTRAINT score_scoring_run_id_fkey FOREIGN KEY (scoring_run_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE analysis.score ADD CONSTRAINT score_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES analysis.score(score_id);
ALTER TABLE analysis.task_dependency ADD CONSTRAINT task_dependency_depends_on_fkey FOREIGN KEY (depends_on) REFERENCES analysis.evidence_task(id);
ALTER TABLE analysis.task_dependency ADD CONSTRAINT task_dependency_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.evidence_task(id);
ALTER TABLE analysis.task_event ADD CONSTRAINT task_event_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.evidence_task(id);
ALTER TABLE analysis.task_legal_link ADD CONSTRAINT task_legal_link_factor_fkey FOREIGN KEY (factor) REFERENCES reference.custody_factor(factor);
ALTER TABLE analysis.task_legal_link ADD CONSTRAINT task_legal_link_legal_issue_id_fkey FOREIGN KEY (legal_issue_id) REFERENCES reference.legal_issue(id);
ALTER TABLE analysis.task_legal_link ADD CONSTRAINT task_legal_link_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.evidence_task(id);
ALTER TABLE analysis.task_person ADD CONSTRAINT task_person_person_id_fkey FOREIGN KEY (person_id) REFERENCES registry.person(id);
ALTER TABLE analysis.task_person ADD CONSTRAINT task_person_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.evidence_task(id);
ALTER TABLE analysis.task_revision ADD CONSTRAINT task_revision_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.evidence_task(id);
ALTER TABLE analysis.time_assertion ADD CONSTRAINT time_assertion_discovery_source_fkey FOREIGN KEY (discovery_source) REFERENCES evidence.evidence_hash(id);
ALTER TABLE analysis.time_assertion ADD CONSTRAINT time_assertion_event_id_fkey FOREIGN KEY (event_id) REFERENCES analysis.timeline_event(event_id) ON DELETE CASCADE;
ALTER TABLE analysis.time_assertion ADD CONSTRAINT time_assertion_ingest_run_id_fkey FOREIGN KEY (ingest_run_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE analysis.time_assertion ADD CONSTRAINT time_assertion_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES analysis.time_assertion(assertion_id);
ALTER TABLE analysis.timeline_event ADD CONSTRAINT timeline_event_ingest_run_id_fkey FOREIGN KEY (ingest_run_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE analysis.timeline_event ADD CONSTRAINT timeline_event_location_id_fkey FOREIGN KEY (location_id) REFERENCES registry.location(id);
ALTER TABLE analysis.timeline_event ADD CONSTRAINT timeline_event_primary_record_id_fkey FOREIGN KEY (primary_record_id) REFERENCES working.normalized_record(id);
ALTER TABLE analysis.timeline_event ADD CONSTRAINT timeline_event_source_artifact_id_fkey FOREIGN KEY (source_artifact_id) REFERENCES evidence.evidence_hash(id);
ALTER TABLE analysis.workflow_run ADD CONSTRAINT workflow_run_parent_run_id_fkey FOREIGN KEY (parent_run_id) REFERENCES analysis.workflow_run(run_id);
ALTER TABLE analysis.workflow_run_stage ADD CONSTRAINT workflow_run_stage_run_id_fkey FOREIGN KEY (run_id) REFERENCES analysis.workflow_run(run_id) ON DELETE CASCADE;
ALTER TABLE canon.canonical_table ADD CONSTRAINT canonical_table_default_tier_fkey FOREIGN KEY (default_tier) REFERENCES canon.change_tier(tier);
ALTER TABLE canon.change_application ADD CONSTRAINT change_application_decision_id_fkey FOREIGN KEY (decision_id) REFERENCES canon.change_decision(id);
ALTER TABLE canon.change_application ADD CONSTRAINT change_application_proposal_id_fkey FOREIGN KEY (proposal_id) REFERENCES canon.change_proposal(id);
ALTER TABLE canon.change_decision ADD CONSTRAINT change_decision_proposal_id_fkey FOREIGN KEY (proposal_id) REFERENCES canon.change_proposal(id);
ALTER TABLE canon.change_proposal ADD CONSTRAINT change_proposal_canonical_table_id_fkey FOREIGN KEY (canonical_table_id) REFERENCES canon.canonical_table(id);
ALTER TABLE canon.change_proposal ADD CONSTRAINT change_proposal_tier_fkey FOREIGN KEY (tier) REFERENCES canon.change_tier(tier);
ALTER TABLE canon.recompute_queue ADD CONSTRAINT recompute_queue_application_id_fkey FOREIGN KEY (application_id) REFERENCES canon.change_application(id);
ALTER TABLE canon.recompute_queue ADD CONSTRAINT recompute_queue_canonical_table_id_fkey FOREIGN KEY (canonical_table_id) REFERENCES canon.canonical_table(id);
ALTER TABLE context.activity_execution ADD CONSTRAINT activity_execution_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.activity_receipt ADD CONSTRAINT activity_receipt_activity_execution_id_fkey FOREIGN KEY (activity_execution_id) REFERENCES context.activity_execution(id) ON DELETE RESTRICT;
ALTER TABLE context.first_party_thread_message_relative_time_anchor ADD CONSTRAINT first_party_thread_message_re_thread_version_id_message_id_fkey FOREIGN KEY (thread_version_id, message_id) REFERENCES working.first_party_context_thread_message(thread_version_id, message_id) ON DELETE RESTRICT;
ALTER TABLE context.first_party_thread_message_relative_time_anchor ADD CONSTRAINT first_party_thread_message_relative_time_anchor_anchor_id_fkey FOREIGN KEY (anchor_id) REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT;
ALTER TABLE context.first_party_thread_source_relative_time_anchor ADD CONSTRAINT first_party_thread_source_relative_time_a_thread_source_id_fkey FOREIGN KEY (thread_source_id) REFERENCES working.first_party_context_thread_source(id) ON DELETE RESTRICT;
ALTER TABLE context.first_party_thread_source_relative_time_anchor ADD CONSTRAINT first_party_thread_source_relative_time_anchor_anchor_id_fkey FOREIGN KEY (anchor_id) REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT;
ALTER TABLE context.first_party_thread_version_relative_time_anchor ADD CONSTRAINT first_party_thread_version_relative_time_anchor_anchor_id_fkey FOREIGN KEY (anchor_id) REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT;
ALTER TABLE context.first_party_thread_version_relative_time_anchor ADD CONSTRAINT first_party_thread_version_relative_time_thread_version_id_fkey FOREIGN KEY (thread_version_id) REFERENCES working.first_party_context_thread_version(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_batch ADD CONSTRAINT hash_batch_activity_execution_id_fkey FOREIGN KEY (activity_execution_id) REFERENCES context.activity_execution(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_batch ADD CONSTRAINT hash_batch_activity_receipt_id_fkey FOREIGN KEY (activity_receipt_id) REFERENCES context.activity_receipt(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_batch ADD CONSTRAINT hash_batch_normalized_generation_id_fkey FOREIGN KEY (normalized_generation_id) REFERENCES context.normalized_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_batch ADD CONSTRAINT hash_batch_raw_generation_id_fkey FOREIGN KEY (raw_generation_id) REFERENCES context.raw_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_batch ADD CONSTRAINT hash_batch_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_batch_member ADD CONSTRAINT hash_batch_member_hash_batch_id_fkey FOREIGN KEY (hash_batch_id) REFERENCES context.hash_batch(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_batch_member ADD CONSTRAINT hash_batch_member_normalized_record_id_fkey FOREIGN KEY (normalized_record_id) REFERENCES context.normalized_record_identity(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_batch_member ADD CONSTRAINT hash_batch_member_raw_record_id_fkey FOREIGN KEY (raw_record_id) REFERENCES context.raw_record_identity(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_batch_member ADD CONSTRAINT hash_batch_member_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_manifest ADD CONSTRAINT hash_manifest_normalized_generation_id_fkey FOREIGN KEY (normalized_generation_id) REFERENCES context.normalized_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_manifest ADD CONSTRAINT hash_manifest_raw_generation_id_fkey FOREIGN KEY (raw_generation_id) REFERENCES context.raw_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_manifest ADD CONSTRAINT hash_manifest_sealed_receipt_fk FOREIGN KEY (sealed_hash_receipt_id) REFERENCES context.hash_receipt(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_manifest_member ADD CONSTRAINT hash_manifest_member_hash_manifest_id_fkey FOREIGN KEY (hash_manifest_id) REFERENCES context.hash_manifest(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_manifest_member ADD CONSTRAINT hash_manifest_member_normalized_record_id_fkey FOREIGN KEY (normalized_record_id) REFERENCES context.normalized_record_identity(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_manifest_member ADD CONSTRAINT hash_manifest_member_raw_record_id_fkey FOREIGN KEY (raw_record_id) REFERENCES context.raw_record_identity(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_receipt ADD CONSTRAINT hash_receipt_activity_receipt_id_fkey FOREIGN KEY (activity_receipt_id) REFERENCES context.activity_receipt(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_receipt ADD CONSTRAINT hash_receipt_hash_manifest_id_fkey FOREIGN KEY (hash_manifest_id) REFERENCES context.hash_manifest(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_receipt ADD CONSTRAINT hash_receipt_normalized_generation_id_fkey FOREIGN KEY (normalized_generation_id) REFERENCES context.normalized_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_receipt ADD CONSTRAINT hash_receipt_normalized_record_id_fkey FOREIGN KEY (normalized_record_id) REFERENCES context.normalized_record_identity(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_receipt ADD CONSTRAINT hash_receipt_raw_generation_id_fkey FOREIGN KEY (raw_generation_id) REFERENCES context.raw_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_receipt ADD CONSTRAINT hash_receipt_raw_record_id_fkey FOREIGN KEY (raw_record_id) REFERENCES context.raw_record_identity(id) ON DELETE RESTRICT;
ALTER TABLE context.hash_receipt ADD CONSTRAINT hash_receipt_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_normalized_generation_id_fkey FOREIGN KEY (normalized_generation_id) REFERENCES context.normalized_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_normalized_generation_id_raw_generat_fkey FOREIGN KEY (normalized_generation_id, raw_generation_id) REFERENCES context.normalized_generation(id, raw_generation_id) ON DELETE RESTRICT;
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_normalized_record_id_fkey FOREIGN KEY (normalized_record_id) REFERENCES context.normalized_record_identity(id) ON DELETE RESTRICT;
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_normalized_record_id_normalized_gene_fkey FOREIGN KEY (normalized_record_id, normalized_generation_id) REFERENCES context.normalized_record_identity(id, normalized_generation_id) ON DELETE RESTRICT;
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_raw_generation_id_fkey FOREIGN KEY (raw_generation_id) REFERENCES context.raw_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_raw_record_id_fkey FOREIGN KEY (raw_record_id) REFERENCES context.raw_record_identity(id) ON DELETE RESTRICT;
ALTER TABLE context.normalization_lineage ADD CONSTRAINT normalization_lineage_raw_record_id_raw_generation_id_fkey FOREIGN KEY (raw_record_id, raw_generation_id) REFERENCES context.raw_record_identity(id, raw_generation_id) ON DELETE RESTRICT;
ALTER TABLE context.normalized_generation ADD CONSTRAINT normalized_generation_raw_generation_id_fkey FOREIGN KEY (raw_generation_id) REFERENCES context.raw_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.normalized_generation ADD CONSTRAINT normalized_generation_raw_generation_id_source_version_id_fkey FOREIGN KEY (raw_generation_id, source_version_id) REFERENCES context.raw_generation(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE context.normalized_generation ADD CONSTRAINT normalized_generation_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.normalized_generation_publication ADD CONSTRAINT normalized_generation_publication_activity_receipt_id_fkey FOREIGN KEY (activity_receipt_id) REFERENCES context.activity_receipt(id) ON DELETE RESTRICT;
ALTER TABLE context.normalized_generation_publication ADD CONSTRAINT normalized_generation_publication_normalized_generation_id_fkey FOREIGN KEY (normalized_generation_id) REFERENCES context.normalized_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.normalized_record_identity ADD CONSTRAINT normalized_record_identity_normalized_generation_id_fkey FOREIGN KEY (normalized_generation_id) REFERENCES context.normalized_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.normalized_record_identity ADD CONSTRAINT normalized_record_identity_normalized_generation_id_source_fkey FOREIGN KEY (normalized_generation_id, source_version_id) REFERENCES context.normalized_generation(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE context.normalized_record_identity ADD CONSTRAINT normalized_record_identity_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.normalized_record_range_locator ADD CONSTRAINT normalized_record_range_locat_normalized_record_id_source__fkey FOREIGN KEY (normalized_record_id, source_version_id) REFERENCES context.normalized_record_identity(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE context.normalized_record_range_locator ADD CONSTRAINT normalized_record_range_locat_source_range_locator_id_sour_fkey FOREIGN KEY (source_range_locator_id, source_version_id) REFERENCES context.source_range_locator(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE context.raw_generation ADD CONSTRAINT raw_generation_extraction_bundle_object_id_fkey FOREIGN KEY (extraction_bundle_object_id) REFERENCES context.retained_object(id) ON DELETE RESTRICT;
ALTER TABLE context.raw_generation ADD CONSTRAINT raw_generation_format_registry_fk FOREIGN KEY (format_id) REFERENCES context.raw_format_registry(format_id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE context.raw_generation ADD CONSTRAINT raw_generation_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_format_id_fkey FOREIGN KEY (format_id) REFERENCES context.raw_format_registry(format_id) ON DELETE RESTRICT;
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_raw_generation_id_fkey FOREIGN KEY (raw_generation_id) REFERENCES context.raw_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_raw_generation_id_format_id_fkey FOREIGN KEY (raw_generation_id, format_id) REFERENCES context.raw_generation(id, format_id) ON DELETE RESTRICT;
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_raw_generation_id_source_version_id_fkey FOREIGN KEY (raw_generation_id, source_version_id) REFERENCES context.raw_generation(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.raw_record_identity ADD CONSTRAINT raw_record_identity_source_version_id_locator_object_id_fkey FOREIGN KEY (source_version_id, locator_object_id) REFERENCES context.source_version_object(source_version_id, object_id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE context.raw_record_range_locator ADD CONSTRAINT raw_record_range_locator_raw_record_id_source_version_id_fkey FOREIGN KEY (raw_record_id, source_version_id) REFERENCES context.raw_record_identity(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE context.raw_record_range_locator ADD CONSTRAINT raw_record_range_locator_source_range_locator_id_source_ve_fkey FOREIGN KEY (source_range_locator_id, source_version_id) REFERENCES context.source_range_locator(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE context.reconciliation_receipt ADD CONSTRAINT reconciliation_receipt_activity_receipt_id_fkey FOREIGN KEY (activity_receipt_id) REFERENCES context.activity_receipt(id) ON DELETE RESTRICT;
ALTER TABLE context.reconciliation_receipt ADD CONSTRAINT reconciliation_receipt_normalized_generation_id_fkey FOREIGN KEY (normalized_generation_id) REFERENCES context.normalized_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.reconciliation_receipt ADD CONSTRAINT reconciliation_receipt_raw_generation_id_fkey FOREIGN KEY (raw_generation_id) REFERENCES context.raw_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_first_known_after_anchor_id_fkey FOREIGN KEY (first_known_after_anchor_id) REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT;
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_last_known_before_anchor_id_fkey FOREIGN KEY (last_known_before_anchor_id) REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT;
ALTER TABLE context.relative_time_anchor ADD CONSTRAINT relative_time_anchor_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT;
ALTER TABLE context.repair_assessment ADD CONSTRAINT repair_assessment_activity_receipt_id_fkey FOREIGN KEY (activity_receipt_id) REFERENCES context.activity_receipt(id) ON DELETE RESTRICT;
ALTER TABLE context.repair_assessment ADD CONSTRAINT repair_assessment_original_object_id_fkey FOREIGN KEY (original_object_id) REFERENCES context.retained_object(id) ON DELETE RESTRICT;
ALTER TABLE context.repair_assessment ADD CONSTRAINT repair_assessment_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.repair_decision ADD CONSTRAINT repair_decision_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES context.repair_assessment(id) ON DELETE RESTRICT;
ALTER TABLE context.repair_decision ADD CONSTRAINT repair_decision_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.repair_resolution ADD CONSTRAINT repair_resolution_active_object_id_fkey FOREIGN KEY (active_object_id) REFERENCES context.retained_object(id) ON DELETE RESTRICT;
ALTER TABLE context.repair_resolution ADD CONSTRAINT repair_resolution_activity_receipt_id_fkey FOREIGN KEY (activity_receipt_id) REFERENCES context.activity_receipt(id) ON DELETE RESTRICT;
ALTER TABLE context.repair_resolution ADD CONSTRAINT repair_resolution_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES context.repair_assessment(id) ON DELETE RESTRICT;
ALTER TABLE context.repair_resolution ADD CONSTRAINT repair_resolution_decision_id_fkey FOREIGN KEY (decision_id) REFERENCES context.repair_decision(id) ON DELETE RESTRICT;
ALTER TABLE context.repair_resolution ADD CONSTRAINT repair_resolution_original_object_id_fkey FOREIGN KEY (original_object_id) REFERENCES context.retained_object(id) ON DELETE RESTRICT;
ALTER TABLE context.repair_resolution ADD CONSTRAINT repair_resolution_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.source_metadata ADD CONSTRAINT source_metadata_extraction_receipt_fk FOREIGN KEY (extraction_activity_receipt_id) REFERENCES context.activity_receipt(id) ON DELETE RESTRICT;
ALTER TABLE context.source_metadata ADD CONSTRAINT source_metadata_raw_record_id_fkey FOREIGN KEY (raw_record_id) REFERENCES context.raw_record_identity(id) ON DELETE RESTRICT;
ALTER TABLE context.source_metadata ADD CONSTRAINT source_metadata_raw_record_id_source_version_id_fkey FOREIGN KEY (raw_record_id, source_version_id) REFERENCES context.raw_record_identity(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE context.source_metadata ADD CONSTRAINT source_metadata_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.source_object_range_locator ADD CONSTRAINT source_object_range_locator_source_range_locator_id_source_fkey FOREIGN KEY (source_range_locator_id, source_version_id) REFERENCES context.source_range_locator(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE context.source_object_range_locator ADD CONSTRAINT source_object_range_locator_source_version_id_source_objec_fkey FOREIGN KEY (source_version_id, source_object_id) REFERENCES context.source_version_object(source_version_id, object_id) ON DELETE RESTRICT;
ALTER TABLE context.source_range_locator ADD CONSTRAINT source_range_locator_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.source_range_locator ADD CONSTRAINT source_range_locator_verification_activity_receipt_id_fkey FOREIGN KEY (verification_activity_receipt_id) REFERENCES context.activity_receipt(id) ON DELETE RESTRICT;
ALTER TABLE context.source_version ADD CONSTRAINT source_version_court_case_scope_fk FOREIGN KEY (court_case_id, matter_id) REFERENCES registry.court_case(id, matter_id) ON DELETE RESTRICT;
ALTER TABLE context.source_version ADD CONSTRAINT source_version_original_object_id_fkey FOREIGN KEY (original_object_id) REFERENCES context.retained_object(id) ON DELETE RESTRICT;
ALTER TABLE context.source_version ADD CONSTRAINT source_version_original_object_membership_fk FOREIGN KEY (id, original_object_id) REFERENCES context.source_version_object(source_version_id, object_id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE context.source_version ADD CONSTRAINT source_version_source_context_ref_fkey FOREIGN KEY (source_context_ref) REFERENCES context.uiw_source_context_revision(source_context_ref) ON DELETE RESTRICT;
ALTER TABLE context.source_version ADD CONSTRAINT source_version_source_context_scope_fk FOREIGN KEY (source_context_ref, matter_id, court_case_id) REFERENCES context.uiw_source_context_revision(source_context_ref, matter_id, court_case_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE context.source_version ADD CONSTRAINT source_version_source_id_fkey FOREIGN KEY (source_id) REFERENCES context.source(id) ON DELETE RESTRICT;
ALTER TABLE context.source_version_object ADD CONSTRAINT source_version_object_object_id_fkey FOREIGN KEY (object_id) REFERENCES context.retained_object(id) ON DELETE RESTRICT;
ALTER TABLE context.source_version_object ADD CONSTRAINT source_version_object_parent_object_id_fkey FOREIGN KEY (parent_object_id) REFERENCES context.retained_object(id) ON DELETE RESTRICT;
ALTER TABLE context.source_version_object ADD CONSTRAINT source_version_object_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.source_version_object ADD CONSTRAINT source_version_object_source_version_id_parent_object_id_fkey FOREIGN KEY (source_version_id, parent_object_id) REFERENCES context.source_version_object(source_version_id, object_id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE context.third_party_thread_message_relative_time_anchor ADD CONSTRAINT third_party_thread_message_re_thread_version_id_message_id_fkey FOREIGN KEY (thread_version_id, message_id) REFERENCES working.third_party_context_thread_message(thread_version_id, message_id) ON DELETE RESTRICT;
ALTER TABLE context.third_party_thread_message_relative_time_anchor ADD CONSTRAINT third_party_thread_message_relative_time_anchor_anchor_id_fkey FOREIGN KEY (anchor_id) REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT;
ALTER TABLE context.third_party_thread_source_relative_time_anchor ADD CONSTRAINT third_party_thread_source_relative_time_a_thread_source_id_fkey FOREIGN KEY (thread_source_id) REFERENCES working.third_party_context_thread_source(id) ON DELETE RESTRICT;
ALTER TABLE context.third_party_thread_source_relative_time_anchor ADD CONSTRAINT third_party_thread_source_relative_time_anchor_anchor_id_fkey FOREIGN KEY (anchor_id) REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT;
ALTER TABLE context.third_party_thread_version_relative_time_anchor ADD CONSTRAINT third_party_thread_version_relative_time_anchor_anchor_id_fkey FOREIGN KEY (anchor_id) REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT;
ALTER TABLE context.third_party_thread_version_relative_time_anchor ADD CONSTRAINT third_party_thread_version_relative_time_thread_version_id_fkey FOREIGN KEY (thread_version_id) REFERENCES working.third_party_context_thread_version(id) ON DELETE RESTRICT;
ALTER TABLE context.uiw_preview_attachment ADD CONSTRAINT uiw_preview_attachment_preview_handle_snapshot_seq_message_fkey FOREIGN KEY (preview_handle, snapshot_seq, message_id) REFERENCES context.uiw_preview_message(preview_handle, snapshot_seq, message_id) ON DELETE RESTRICT;
ALTER TABLE context.uiw_preview_decision ADD CONSTRAINT uiw_preview_decision_preview_handle_fkey FOREIGN KEY (preview_handle) REFERENCES context.uiw_preview_binding(preview_handle) ON DELETE RESTRICT;
ALTER TABLE context.uiw_preview_event ADD CONSTRAINT uiw_preview_event_preview_handle_fkey FOREIGN KEY (preview_handle) REFERENCES context.uiw_preview_binding(preview_handle) ON DELETE RESTRICT;
ALTER TABLE context.uiw_preview_message ADD CONSTRAINT uiw_preview_message_preview_handle_snapshot_seq_fkey FOREIGN KEY (preview_handle, snapshot_seq) REFERENCES context.uiw_preview_snapshot(preview_handle, snapshot_seq) ON DELETE RESTRICT;
ALTER TABLE context.uiw_preview_message ADD CONSTRAINT uiw_preview_message_preview_handle_snapshot_seq_sender_par_fkey FOREIGN KEY (preview_handle, snapshot_seq, sender_participant_id) REFERENCES context.uiw_preview_participant(preview_handle, snapshot_seq, participant_id) ON DELETE RESTRICT;
ALTER TABLE context.uiw_preview_participant ADD CONSTRAINT uiw_preview_participant_preview_handle_snapshot_seq_fkey FOREIGN KEY (preview_handle, snapshot_seq) REFERENCES context.uiw_preview_snapshot(preview_handle, snapshot_seq) ON DELETE RESTRICT;
ALTER TABLE context.uiw_preview_receipt ADD CONSTRAINT uiw_preview_receipt_preview_handle_snapshot_seq_fkey FOREIGN KEY (preview_handle, snapshot_seq) REFERENCES context.uiw_preview_snapshot(preview_handle, snapshot_seq) ON DELETE RESTRICT;
ALTER TABLE context.uiw_preview_snapshot ADD CONSTRAINT uiw_preview_snapshot_normalized_generation_id_fkey FOREIGN KEY (normalized_generation_id) REFERENCES context.normalized_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.uiw_preview_snapshot ADD CONSTRAINT uiw_preview_snapshot_preview_handle_fkey FOREIGN KEY (preview_handle) REFERENCES context.uiw_preview_binding(preview_handle) ON DELETE RESTRICT;
ALTER TABLE context.uiw_preview_snapshot ADD CONSTRAINT uiw_preview_snapshot_raw_generation_id_fkey FOREIGN KEY (raw_generation_id) REFERENCES context.raw_generation(id) ON DELETE RESTRICT;
ALTER TABLE context.uiw_preview_snapshot ADD CONSTRAINT uiw_preview_snapshot_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_court_case_scope_fk FOREIGN KEY (court_case_id, matter_id) REFERENCES registry.court_case(id, matter_id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_matter_fk FOREIGN KEY (matter_id) REFERENCES registry.matter(id) ON DELETE RESTRICT NOT VALID;
ALTER TABLE context.uiw_source_context_revision ADD CONSTRAINT uiw_source_context_revision_supersedes_ref_fkey FOREIGN KEY (supersedes_ref) REFERENCES context.uiw_source_context_revision(source_context_ref) ON DELETE RESTRICT;
ALTER TABLE evidence.acquisition ADD CONSTRAINT acquisition_device_id_fkey FOREIGN KEY (device_id) REFERENCES registry.device(id);
ALTER TABLE evidence.acquisition ADD CONSTRAINT acquisition_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES evidence.acquisition(id);
ALTER TABLE evidence.artifact_metadata ADD CONSTRAINT artifact_metadata_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);
ALTER TABLE evidence.artifact_metadata ADD CONSTRAINT artifact_metadata_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE evidence.custody_event ADD CONSTRAINT custody_event_evidence_hash_id_fkey FOREIGN KEY (evidence_hash_id) REFERENCES evidence.evidence_hash(id);
ALTER TABLE evidence.custody_event ADD CONSTRAINT custody_event_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES raw.file_node(id);
ALTER TABLE evidence.custody_event ADD CONSTRAINT custody_event_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE evidence.evidence_hash ADD CONSTRAINT evidence_hash_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES raw.file_node(id);
ALTER TABLE evidence.evidence_hash ADD CONSTRAINT evidence_hash_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_court_case_matter_fkey FOREIGN KEY (court_case_id, matter_id) REFERENCES registry.court_case(id, matter_id) ON DELETE RESTRICT;
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_evidence_hash_id_fkey FOREIGN KEY (evidence_hash_id) REFERENCES evidence.evidence_hash(id);
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES raw.file_node(id);
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_matter_fkey FOREIGN KEY (matter_id) REFERENCES registry.matter(id) ON DELETE RESTRICT;
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_normalized_record_id_fkey FOREIGN KEY (normalized_record_id) REFERENCES working.normalized_record(id);
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_source_run_id_fkey FOREIGN KEY (source_run_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE evidence.evidence_item ADD CONSTRAINT evidence_item_supersedes_item_id_fkey FOREIGN KEY (supersedes_item_id) REFERENCES evidence.evidence_item(id);
ALTER TABLE evidence.ingest_run ADD CONSTRAINT ingest_run_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE evidence.source ADD CONSTRAINT source_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);
ALTER TABLE evidence.source ADD CONSTRAINT source_supersedes_source_id_fkey FOREIGN KEY (supersedes_source_id) REFERENCES evidence.source(id);
ALTER TABLE ops.processing_run ADD CONSTRAINT processing_run_classification_version_id_fkey FOREIGN KEY (classification_version_id) REFERENCES classification_version(classification_version_id);
ALTER TABLE ops.processing_run ADD CONSTRAINT processing_run_model_version_id_fkey FOREIGN KEY (model_version_id) REFERENCES model_version(model_version_id);
ALTER TABLE ops.processing_run ADD CONSTRAINT processing_run_ontology_version_id_fkey FOREIGN KEY (ontology_version_id) REFERENCES ontology_version(ontology_version_id);
ALTER TABLE ops.processing_run ADD CONSTRAINT processing_run_prompt_version_id_fkey FOREIGN KEY (prompt_version_id) REFERENCES prompt_registry(prompt_id);
ALTER TABLE ops.processing_run ADD CONSTRAINT processing_run_schema_version_id_fkey FOREIGN KEY (schema_version_id) REFERENCES schema_version(schema_version_id);
ALTER TABLE ops.processing_run ADD CONSTRAINT processing_run_supersedes_run_fkey FOREIGN KEY (supersedes_run) REFERENCES ops.processing_run(run_id);
ALTER TABLE ops.tool_call_ledger ADD CONSTRAINT tool_call_ledger_run_id_fkey FOREIGN KEY (run_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE ops.workflow_run ADD CONSTRAINT workflow_run_parent_run_id_fkey FOREIGN KEY (parent_run_id) REFERENCES ops.workflow_run(run_id);
ALTER TABLE ops.workflow_run_review_action ADD CONSTRAINT workflow_run_review_action_run_id_fkey FOREIGN KEY (run_id) REFERENCES ops.workflow_run(run_id);
ALTER TABLE ops.workflow_run_stage ADD CONSTRAINT workflow_run_stage_run_id_fkey FOREIGN KEY (run_id) REFERENCES ops.workflow_run(run_id) ON DELETE CASCADE;
ALTER TABLE public.canon_registry ADD CONSTRAINT canon_registry_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES canon_registry(id);
ALTER TABLE public.change_log ADD CONSTRAINT change_log_related_decision_id_fkey FOREIGN KEY (related_decision_id) REFERENCES decision_log(decision_id);
ALTER TABLE public.change_log ADD CONSTRAINT change_log_related_run_id_fkey FOREIGN KEY (related_run_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE public.classification_version ADD CONSTRAINT classification_version_supersedes_fkey FOREIGN KEY (supersedes) REFERENCES classification_version(classification_version_id);
ALTER TABLE public.decision_log ADD CONSTRAINT decision_log_supersedes_fkey FOREIGN KEY (supersedes) REFERENCES decision_log(decision_id);
ALTER TABLE public.decision_precedent ADD CONSTRAINT decision_precedent_decision_id_fkey FOREIGN KEY (decision_id) REFERENCES decision_log(decision_id);
ALTER TABLE public.decision_precedent ADD CONSTRAINT decision_precedent_source_decision_id_fkey FOREIGN KEY (source_decision_id) REFERENCES decision_log(decision_id);
ALTER TABLE public.memory_items ADD CONSTRAINT memory_items_related_ontology_id_fkey FOREIGN KEY (related_ontology_id) REFERENCES ontology_version(ontology_version_id);
ALTER TABLE public.memory_items ADD CONSTRAINT memory_items_related_schema_id_fkey FOREIGN KEY (related_schema_id) REFERENCES schema_version(schema_version_id);
ALTER TABLE public.memory_items ADD CONSTRAINT memory_items_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES memory_items(memory_id);
ALTER TABLE public.ontology_version ADD CONSTRAINT ontology_version_supersedes_fkey FOREIGN KEY (supersedes) REFERENCES ontology_version(ontology_version_id);
ALTER TABLE public.open_questions ADD CONSTRAINT open_questions_related_run_id_fkey FOREIGN KEY (related_run_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE public.prompt_registry ADD CONSTRAINT prompt_registry_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES prompt_registry(prompt_id);
ALTER TABLE public.schema_version ADD CONSTRAINT schema_version_supersedes_fkey FOREIGN KEY (supersedes) REFERENCES schema_version(schema_version_id);
ALTER TABLE raw.file_node ADD CONSTRAINT file_node_parent_node_id_fkey FOREIGN KEY (parent_node_id) REFERENCES raw.file_node(id);
ALTER TABLE raw.file_node ADD CONSTRAINT file_node_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE raw.gps_point ADD CONSTRAINT gps_point_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES raw.file_node(id);
ALTER TABLE raw.gps_point ADD CONSTRAINT gps_point_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE raw.raw_activity ADD CONSTRAINT raw_activity_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES raw.file_node(id);
ALTER TABLE raw.raw_activity ADD CONSTRAINT raw_activity_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE raw.raw_ai_chat ADD CONSTRAINT raw_ai_chat_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);
ALTER TABLE raw.raw_ai_chat ADD CONSTRAINT raw_ai_chat_device_id_fkey FOREIGN KEY (device_id) REFERENCES registry.device(id);
ALTER TABLE raw.raw_ai_chat ADD CONSTRAINT raw_ai_chat_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE raw.raw_csv ADD CONSTRAINT raw_csv_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);
ALTER TABLE raw.raw_csv ADD CONSTRAINT raw_csv_device_id_fkey FOREIGN KEY (device_id) REFERENCES registry.device(id);
ALTER TABLE raw.raw_csv ADD CONSTRAINT raw_csv_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE raw.raw_facebook ADD CONSTRAINT raw_facebook_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);
ALTER TABLE raw.raw_facebook ADD CONSTRAINT raw_facebook_device_id_fkey FOREIGN KEY (device_id) REFERENCES registry.device(id);
ALTER TABLE raw.raw_facebook ADD CONSTRAINT raw_facebook_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE raw.raw_imessage ADD CONSTRAINT raw_imessage_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);
ALTER TABLE raw.raw_imessage ADD CONSTRAINT raw_imessage_device_id_fkey FOREIGN KEY (device_id) REFERENCES registry.device(id);
ALTER TABLE raw.raw_imessage ADD CONSTRAINT raw_imessage_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE raw.raw_path ADD CONSTRAINT raw_path_aligned_activity_id_fkey FOREIGN KEY (aligned_activity_id) REFERENCES raw.raw_activity(id);
ALTER TABLE raw.raw_path ADD CONSTRAINT raw_path_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES raw.file_node(id);
ALTER TABLE raw.raw_path ADD CONSTRAINT raw_path_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES raw.raw_path(id);
ALTER TABLE raw.raw_path ADD CONSTRAINT raw_path_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE raw.raw_phone ADD CONSTRAINT raw_phone_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);
ALTER TABLE raw.raw_phone ADD CONSTRAINT raw_phone_device_id_fkey FOREIGN KEY (device_id) REFERENCES registry.device(id);
ALTER TABLE raw.raw_phone ADD CONSTRAINT raw_phone_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE raw.raw_rejected ADD CONSTRAINT raw_rejected_ingest_run_id_fkey FOREIGN KEY (ingest_run_id) REFERENCES evidence.ingest_run(id) ON DELETE RESTRICT;
ALTER TABLE raw.raw_sms ADD CONSTRAINT raw_sms_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);
ALTER TABLE raw.raw_sms ADD CONSTRAINT raw_sms_device_id_fkey FOREIGN KEY (device_id) REFERENCES registry.device(id);
ALTER TABLE raw.raw_sms ADD CONSTRAINT raw_sms_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE raw.raw_trip ADD CONSTRAINT raw_trip_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES raw.file_node(id);
ALTER TABLE raw.raw_trip ADD CONSTRAINT raw_trip_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES raw.raw_trip(id);
ALTER TABLE raw.raw_trip ADD CONSTRAINT raw_trip_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE raw.raw_visit ADD CONSTRAINT raw_visit_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES raw.file_node(id);
ALTER TABLE raw.raw_visit ADD CONSTRAINT raw_visit_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES raw.raw_visit(id);
ALTER TABLE raw.raw_visit ADD CONSTRAINT raw_visit_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE reference.behavior_category_mcl ADD CONSTRAINT behavior_category_mcl_category_id_fkey FOREIGN KEY (category_id) REFERENCES reference.behavior_category(category_id);
ALTER TABLE reference.claim_type ADD CONSTRAINT claim_type_parent_slug_fkey FOREIGN KEY (parent_slug) REFERENCES reference.claim_type(slug) ON DELETE RESTRICT;
ALTER TABLE reference.detection_pattern ADD CONSTRAINT detection_pattern_category_id_fkey FOREIGN KEY (category_id) REFERENCES reference.behavior_category(category_id);
ALTER TABLE reference.detection_pattern ADD CONSTRAINT detection_pattern_pattern_set_id_fkey FOREIGN KEY (pattern_set_id) REFERENCES reference.detection_pattern_set(id);
ALTER TABLE reference.detection_pattern_set ADD CONSTRAINT detection_pattern_set_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE reference.knowledge_tag ADD CONSTRAINT knowledge_tag_parent_tag_id_fkey FOREIGN KEY (parent_tag_id) REFERENCES reference.knowledge_tag(id);
ALTER TABLE reference.legal_issue_factor ADD CONSTRAINT legal_issue_factor_factor_fkey FOREIGN KEY (factor) REFERENCES reference.custody_factor(factor);
ALTER TABLE reference.legal_issue_factor ADD CONSTRAINT legal_issue_factor_legal_issue_id_fkey FOREIGN KEY (legal_issue_id) REFERENCES reference.legal_issue(id);
ALTER TABLE reference.lexicon_sync ADD CONSTRAINT lexicon_sync_pattern_set_id_fkey FOREIGN KEY (pattern_set_id) REFERENCES reference.detection_pattern_set(id);
ALTER TABLE reference.pattern_lexicon ADD CONSTRAINT pattern_lexicon_pattern_set_id_fkey FOREIGN KEY (pattern_set_id) REFERENCES reference.detection_pattern_set(id);
ALTER TABLE registry.court_case ADD CONSTRAINT court_case_matter_fkey FOREIGN KEY (matter_id) REFERENCES registry.matter(id) ON DELETE RESTRICT;
ALTER TABLE registry.device ADD CONSTRAINT device_id_fkey FOREIGN KEY (id) REFERENCES registry.entity(id) ON DELETE CASCADE;
ALTER TABLE registry.device ADD CONSTRAINT device_owner_entity_id_fkey FOREIGN KEY (owner_entity_id) REFERENCES registry.entity(id);
ALTER TABLE registry.entity ADD CONSTRAINT entity_merged_into_id_fkey FOREIGN KEY (merged_into_id) REFERENCES registry.entity(id);
ALTER TABLE registry.entity_alias ADD CONSTRAINT entity_alias_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES registry.entity(id) ON DELETE CASCADE;
ALTER TABLE registry.id_xref ADD CONSTRAINT id_xref_canonical_entity_id_fkey FOREIGN KEY (canonical_entity_id) REFERENCES registry.entity(id);
ALTER TABLE registry.location ADD CONSTRAINT location_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE registry.person ADD CONSTRAINT person_id_fkey FOREIGN KEY (id) REFERENCES registry.entity(id) ON DELETE CASCADE;
ALTER TABLE timeline.event_candidate_relative_time_anchor ADD CONSTRAINT event_candidate_relative_time_anchor_anchor_id_fkey FOREIGN KEY (anchor_id) REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT;
ALTER TABLE timeline.event_candidate_relative_time_anchor ADD CONSTRAINT event_candidate_relative_time_anchor_event_candidate_id_fkey FOREIGN KEY (event_candidate_id) REFERENCES timeline.event_candidate(id) ON DELETE RESTRICT;
ALTER TABLE timeline.event_candidate_source_range ADD CONSTRAINT event_candidate_source_range_event_candidate_id_fkey FOREIGN KEY (event_candidate_id) REFERENCES timeline.event_candidate(id) ON DELETE RESTRICT;
ALTER TABLE timeline.event_candidate_source_range ADD CONSTRAINT event_candidate_source_range_extraction_activity_receipt_i_fkey FOREIGN KEY (extraction_activity_receipt_id) REFERENCES context.activity_receipt(id) ON DELETE RESTRICT;
ALTER TABLE timeline.event_candidate_source_range ADD CONSTRAINT event_candidate_source_range_source_range_locator_id_sourc_fkey FOREIGN KEY (source_range_locator_id, source_version_id) REFERENCES context.source_range_locator(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE timeline.timeline_member ADD CONSTRAINT timeline_member_candidate_id_fkey FOREIGN KEY (candidate_id) REFERENCES timeline.event_candidate(id);
ALTER TABLE timeline.timeline_member ADD CONSTRAINT timeline_member_collection_id_fkey FOREIGN KEY (collection_id) REFERENCES timeline.timeline_collection(id);
ALTER TABLE timeline.timeline_projection_activation ADD CONSTRAINT timeline_projection_activation_generation_id_fkey FOREIGN KEY (generation_id) REFERENCES timeline.timeline_projection_generation(id);
ALTER TABLE timeline.timeline_projection_generation ADD CONSTRAINT timeline_projection_generation_collection_id_fkey FOREIGN KEY (collection_id) REFERENCES timeline.timeline_collection(id);
ALTER TABLE timeline.timeline_projection_generation ADD CONSTRAINT timeline_projection_generation_since_generation_id_fkey FOREIGN KEY (since_generation_id) REFERENCES timeline.timeline_projection_generation(id);
ALTER TABLE timeline.timeline_projection_generation ADD CONSTRAINT timeline_projection_generation_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES timeline.timeline_projection_generation(id);
ALTER TABLE timeline.timeline_projection_member ADD CONSTRAINT timeline_projection_member_generation_id_fkey FOREIGN KEY (generation_id) REFERENCES timeline.timeline_projection_generation(id);
ALTER TABLE timeline.timeline_projection_member ADD CONSTRAINT timeline_projection_member_source_member_id_fkey FOREIGN KEY (source_member_id) REFERENCES timeline.timeline_member(id);
ALTER TABLE timeline.timeline_projection_receipt ADD CONSTRAINT timeline_projection_receipt_generation_id_fkey FOREIGN KEY (generation_id) REFERENCES timeline.timeline_projection_generation(id);
ALTER TABLE timeline.timeline_projection_receipt ADD CONSTRAINT timeline_projection_receipt_member_id_fkey FOREIGN KEY (member_id) REFERENCES timeline.timeline_projection_member(id);
ALTER TABLE timeline.timeline_projection_receipt ADD CONSTRAINT timeline_projection_receipt_previous_receipt_id_fkey FOREIGN KEY (previous_receipt_id) REFERENCES timeline.timeline_projection_receipt(id);
ALTER TABLE working.account ADD CONSTRAINT account_id_fkey FOREIGN KEY (id) REFERENCES registry.entity(id) ON DELETE CASCADE;
ALTER TABLE working.account ADD CONSTRAINT account_owner_entity_id_fkey FOREIGN KEY (owner_entity_id) REFERENCES registry.entity(id);
ALTER TABLE working.artifact_registry ADD CONSTRAINT artifact_registry_parent_artifact_id_fkey FOREIGN KEY (parent_artifact_id) REFERENCES working.artifact_registry(artifact_id);
ALTER TABLE working.artifact_registry ADD CONSTRAINT artifact_registry_producing_run_fkey FOREIGN KEY (producing_run) REFERENCES ops.processing_run(run_id);
ALTER TABLE working.artifact_registry ADD CONSTRAINT artifact_registry_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES working.artifact_registry(artifact_id);
ALTER TABLE working.attachment ADD CONSTRAINT attachment_message_id_fkey FOREIGN KEY (message_id) REFERENCES working.message(id) ON DELETE CASCADE;
ALTER TABLE working.attachment ADD CONSTRAINT attachment_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE working.attachment ADD CONSTRAINT attachment_source_artifact_id_fkey FOREIGN KEY (source_artifact_id) REFERENCES evidence.evidence_hash(id);
ALTER TABLE working.call_log ADD CONSTRAINT call_log_id_fkey FOREIGN KEY (id) REFERENCES working.normalized_record(id) ON DELETE CASCADE;
ALTER TABLE working.call_log ADD CONSTRAINT call_log_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE working.call_log ADD CONSTRAINT call_log_source_artifact_id_fkey FOREIGN KEY (source_artifact_id) REFERENCES evidence.evidence_hash(id);
ALTER TABLE working.candidate_entity ADD CONSTRAINT candidate_entity_extraction_run_id_fkey FOREIGN KEY (extraction_run_id) REFERENCES working.extraction_run(id) ON DELETE CASCADE;
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_extraction_run_id_fkey FOREIGN KEY (extraction_run_id) REFERENCES working.extraction_run(id) ON DELETE CASCADE;
ALTER TABLE working.candidate_event ADD CONSTRAINT candidate_event_primary_entity_id_fkey FOREIGN KEY (primary_entity_id) REFERENCES working.candidate_entity(id) ON DELETE SET NULL;
ALTER TABLE working.candidate_fact ADD CONSTRAINT candidate_fact_extraction_run_id_fkey FOREIGN KEY (extraction_run_id) REFERENCES working.extraction_run(id) ON DELETE CASCADE;
ALTER TABLE working.candidate_fact ADD CONSTRAINT candidate_fact_object_entity_id_fkey FOREIGN KEY (object_entity_id) REFERENCES working.candidate_entity(id) ON DELETE SET NULL;
ALTER TABLE working.candidate_fact ADD CONSTRAINT candidate_fact_subject_entity_id_fkey FOREIGN KEY (subject_entity_id) REFERENCES working.candidate_entity(id) ON DELETE SET NULL;
ALTER TABLE working.chat_message ADD CONSTRAINT chat_message_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES working.chat_conversation(id) ON DELETE CASCADE;
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_chat_conversation_id_fkey FOREIGN KEY (chat_conversation_id) REFERENCES working.chat_conversation(id) ON DELETE RESTRICT;
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_chat_message_id_fkey FOREIGN KEY (chat_message_id) REFERENCES working.chat_message(id) ON DELETE RESTRICT;
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_claim_type_slug_fkey FOREIGN KEY (claim_type_slug) REFERENCES reference.claim_type(slug) ON DELETE RESTRICT;
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_extraction_run_id_fkey FOREIGN KEY (extraction_run_id) REFERENCES working.extraction_run(id) ON DELETE CASCADE;
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_relative_time_anchor_id_fkey FOREIGN KEY (relative_time_anchor_id) REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT;
ALTER TABLE working.claim_candidate ADD CONSTRAINT claim_candidate_window_id_fkey FOREIGN KEY (window_id) REFERENCES working.extraction_window(id) ON DELETE CASCADE;
ALTER TABLE working.claim_temporal_edge ADD CONSTRAINT claim_temporal_edge_extraction_run_id_fkey FOREIGN KEY (extraction_run_id) REFERENCES working.extraction_run(id) ON DELETE CASCADE;
ALTER TABLE working.claim_temporal_edge ADD CONSTRAINT claim_temporal_edge_from_claim_id_fkey FOREIGN KEY (from_claim_id) REFERENCES working.claim_candidate(id) ON DELETE RESTRICT;
ALTER TABLE working.claim_temporal_edge ADD CONSTRAINT claim_temporal_edge_resolved_claim_id_fkey FOREIGN KEY (resolved_claim_id) REFERENCES working.claim_candidate(id) ON DELETE RESTRICT;
ALTER TABLE working.claim_temporal_edge ADD CONSTRAINT claim_temporal_edge_to_claim_id_fkey FOREIGN KEY (to_claim_id) REFERENCES working.claim_candidate(id) ON DELETE RESTRICT;
ALTER TABLE working.content_chunk ADD CONSTRAINT content_chunk_generation_id_source_version_id_fkey FOREIGN KEY (generation_id, source_version_id) REFERENCES working.content_chunk_generation(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_activity_execution_id_source_vers_fkey FOREIGN KEY (activity_execution_id, source_version_id) REFERENCES context.activity_execution(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_activity_receipt_id_fkey FOREIGN KEY (activity_receipt_id) REFERENCES context.activity_receipt(id) ON DELETE RESTRICT;
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_normalized_generation_id_source_v_fkey FOREIGN KEY (normalized_generation_id, source_version_id) REFERENCES context.normalized_generation(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE working.content_chunk_generation ADD CONSTRAINT content_chunk_generation_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE working.content_chunk_projection ADD CONSTRAINT content_chunk_projection_chunk_id_fkey FOREIGN KEY (chunk_id) REFERENCES working.content_chunk(id) ON DELETE CASCADE;
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_rece_generation_id_source_version_fkey FOREIGN KEY (generation_id, source_version_id) REFERENCES working.content_chunk_generation(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE working.content_chunk_reassembly_receipt ADD CONSTRAINT content_chunk_reassembly_receipt_activity_receipt_id_fkey FOREIGN KEY (activity_receipt_id) REFERENCES context.activity_receipt(id) ON DELETE RESTRICT;
ALTER TABLE working.content_chunk_source_span ADD CONSTRAINT content_chunk_source_span_chunk_id_generation_id_source_ve_fkey FOREIGN KEY (chunk_id, generation_id, source_version_id) REFERENCES working.content_chunk(id, generation_id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE working.content_chunk_source_span ADD CONSTRAINT content_chunk_source_span_source_range_locator_id_source_v_fkey FOREIGN KEY (source_range_locator_id, source_version_id) REFERENCES context.source_range_locator(id, source_version_id) ON DELETE RESTRICT;
ALTER TABLE working.context_asset ADD CONSTRAINT context_asset_archive_id_fkey FOREIGN KEY (archive_id) REFERENCES working.context_archive(id);
ALTER TABLE working.context_asset_derivation ADD CONSTRAINT context_asset_derivation_child_asset_id_fkey FOREIGN KEY (child_asset_id) REFERENCES working.context_asset(id) ON DELETE CASCADE;
ALTER TABLE working.context_asset_derivation ADD CONSTRAINT context_asset_derivation_parent_asset_id_fkey FOREIGN KEY (parent_asset_id) REFERENCES working.context_asset(id) ON DELETE CASCADE;
ALTER TABLE working.context_asset_message ADD CONSTRAINT context_asset_message_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES working.context_asset(id) ON DELETE CASCADE;
ALTER TABLE working.context_asset_message ADD CONSTRAINT context_asset_message_message_id_fkey FOREIGN KEY (message_id) REFERENCES working.chat_message(id) ON DELETE CASCADE;
ALTER TABLE working.email ADD CONSTRAINT email_id_fkey FOREIGN KEY (id) REFERENCES registry.entity(id) ON DELETE CASCADE;
ALTER TABLE working.email ADD CONSTRAINT email_owner_entity_id_fkey FOREIGN KEY (owner_entity_id) REFERENCES registry.entity(id);
ALTER TABLE working.entity_resolution ADD CONSTRAINT entity_resolution_canonical_entity_id_fkey FOREIGN KEY (canonical_entity_id) REFERENCES registry.entity(id);
ALTER TABLE working.entity_resolution ADD CONSTRAINT entity_resolution_mention_id_fkey FOREIGN KEY (mention_id) REFERENCES working.entity_mention(id);
ALTER TABLE working.event_source_record ADD CONSTRAINT event_source_record_event_id_fkey FOREIGN KEY (event_id) REFERENCES analysis.timeline_event(event_id) ON DELETE CASCADE;
ALTER TABLE working.event_source_record ADD CONSTRAINT event_source_record_record_id_fkey FOREIGN KEY (record_id) REFERENCES working.normalized_record(id);
ALTER TABLE working.event_source_record ADD CONSTRAINT event_source_record_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);
ALTER TABLE working.extraction_window ADD CONSTRAINT extraction_window_chat_conversation_id_fkey FOREIGN KEY (chat_conversation_id) REFERENCES working.chat_conversation(id) ON DELETE RESTRICT;
ALTER TABLE working.extraction_window ADD CONSTRAINT extraction_window_extraction_run_id_fkey FOREIGN KEY (extraction_run_id) REFERENCES working.extraction_run(id) ON DELETE CASCADE;
ALTER TABLE working.first_party_context_thread ADD CONSTRAINT first_party_context_thread_court_case_id_matter_id_fkey FOREIGN KEY (court_case_id, matter_id) REFERENCES registry.court_case(id, matter_id) ON DELETE RESTRICT;
ALTER TABLE working.first_party_context_thread ADD CONSTRAINT first_party_context_thread_owner_person_id_fkey FOREIGN KEY (owner_person_id) REFERENCES registry.person(id) ON DELETE RESTRICT;
ALTER TABLE working.first_party_context_thread_message ADD CONSTRAINT first_party_context_thread_me_thread_version_id_context_th_fkey FOREIGN KEY (thread_version_id, context_thread_id) REFERENCES working.first_party_context_thread_version(id, context_thread_id) ON DELETE RESTRICT;
ALTER TABLE working.first_party_context_thread_message ADD CONSTRAINT first_party_context_thread_message_message_id_fkey FOREIGN KEY (message_id) REFERENCES working.message(id) ON DELETE RESTRICT;
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_so_thread_version_id_context_th_fkey FOREIGN KEY (thread_version_id, context_thread_id) REFERENCES working.first_party_context_thread_version(id, context_thread_id) ON DELETE RESTRICT;
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_originating_device_id_fkey FOREIGN KEY (originating_device_id) REFERENCES registry.device(id) ON DELETE RESTRICT;
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_perspective_person_id_fkey FOREIGN KEY (perspective_person_id) REFERENCES registry.person(id) ON DELETE RESTRICT;
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE working.first_party_context_thread_source ADD CONSTRAINT first_party_context_thread_source_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES working.first_party_context_thread_source(id) ON DELETE RESTRICT;
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_version_context_thread_id_fkey FOREIGN KEY (context_thread_id) REFERENCES working.first_party_context_thread(context_thread_id) ON DELETE RESTRICT;
ALTER TABLE working.first_party_context_thread_version ADD CONSTRAINT first_party_context_thread_version_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES working.first_party_context_thread_version(id) ON DELETE RESTRICT;
ALTER TABLE working.handle ADD CONSTRAINT handle_id_fkey FOREIGN KEY (id) REFERENCES registry.entity(id) ON DELETE CASCADE;
ALTER TABLE working.handle ADD CONSTRAINT handle_owner_entity_id_fkey FOREIGN KEY (owner_entity_id) REFERENCES registry.entity(id);
ALTER TABLE working.message ADD CONSTRAINT fk_msg_screenshot FOREIGN KEY (screenshot_attachment_id) REFERENCES working.attachment(id);
ALTER TABLE working.message ADD CONSTRAINT message_derived_from_record_id_fkey FOREIGN KEY (derived_from_record_id) REFERENCES working.normalized_record(id);
ALTER TABLE working.message ADD CONSTRAINT message_id_fkey FOREIGN KEY (id) REFERENCES working.normalized_record(id) ON DELETE CASCADE;
ALTER TABLE working.message ADD CONSTRAINT message_next_message_id_fkey FOREIGN KEY (next_message_id) REFERENCES working.message(id);
ALTER TABLE working.message ADD CONSTRAINT message_prev_message_id_fkey FOREIGN KEY (prev_message_id) REFERENCES working.message(id);
ALTER TABLE working.message ADD CONSTRAINT message_route_fk FOREIGN KEY (derived_from_record_id, projection_kind) REFERENCES working.message_projection_route(normalized_record_id, projection_kind) DEFERRABLE INITIALLY DEFERRED NOT VALID;
ALTER TABLE working.message_participant ADD CONSTRAINT message_participant_message_id_fkey FOREIGN KEY (message_id) REFERENCES working.message(id) ON DELETE CASCADE;
ALTER TABLE working.message_projection_route ADD CONSTRAINT message_projection_route_normalized_record_id_fkey FOREIGN KEY (normalized_record_id) REFERENCES working.normalized_record(id) ON DELETE CASCADE;
ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);
ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_artifact_id_fkey FOREIGN KEY (artifact_id) REFERENCES evidence.evidence_hash(id);
ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_device_id_fkey FOREIGN KEY (device_id) REFERENCES registry.device(id);
ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);
ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_sender_entity_id_fkey FOREIGN KEY (sender_entity_id) REFERENCES registry.entity(id);
ALTER TABLE working.organization ADD CONSTRAINT organization_id_fkey FOREIGN KEY (id) REFERENCES registry.entity(id) ON DELETE CASCADE;
ALTER TABLE working.phone ADD CONSTRAINT phone_id_fkey FOREIGN KEY (id) REFERENCES registry.entity(id) ON DELETE CASCADE;
ALTER TABLE working.phone ADD CONSTRAINT phone_owner_entity_id_fkey FOREIGN KEY (owner_entity_id) REFERENCES registry.entity(id);
ALTER TABLE working.realization_event ADD CONSTRAINT realization_event_trigger_record_id_fkey FOREIGN KEY (trigger_record_id) REFERENCES working.normalized_record(id) ON DELETE RESTRICT;
ALTER TABLE working.realization_event_record ADD CONSTRAINT realization_event_record_normalized_record_id_fkey FOREIGN KEY (normalized_record_id) REFERENCES working.normalized_record(id) ON DELETE RESTRICT;
ALTER TABLE working.realization_event_record ADD CONSTRAINT realization_event_record_realization_event_id_fkey FOREIGN KEY (realization_event_id) REFERENCES working.realization_event(id) ON DELETE CASCADE;
ALTER TABLE working.record_visible_from ADD CONSTRAINT record_visible_from_record_id_fkey FOREIGN KEY (record_id) REFERENCES working.normalized_record(id) ON DELETE CASCADE;
ALTER TABLE working.temporal_anchor ADD CONSTRAINT temporal_anchor_event_id_fkey FOREIGN KEY (event_id) REFERENCES analysis.timeline_event(event_id);
ALTER TABLE working.third_party_context_thread ADD CONSTRAINT third_party_context_thread_court_case_id_matter_id_fkey FOREIGN KEY (court_case_id, matter_id) REFERENCES registry.court_case(id, matter_id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_context_thread_message ADD CONSTRAINT third_party_context_thread_me_thread_version_id_context_th_fkey FOREIGN KEY (thread_version_id, context_thread_id) REFERENCES working.third_party_context_thread_version(id, context_thread_id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_context_thread_message ADD CONSTRAINT third_party_context_thread_mes_conversation_acquisition_id_fkey FOREIGN KEY (conversation_acquisition_id) REFERENCES working.third_party_conversation_acquisition(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_context_thread_message ADD CONSTRAINT third_party_context_thread_message_message_id_fkey FOREIGN KEY (message_id) REFERENCES working.third_party_message(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_so_acquisition_activity_receipt_fkey FOREIGN KEY (acquisition_activity_receipt_id) REFERENCES context.activity_receipt(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_so_thread_version_id_context_th_fkey FOREIGN KEY (thread_version_id, context_thread_id) REFERENCES working.third_party_context_thread_version(id, context_thread_id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_sou_conversation_acquisition_id_fkey FOREIGN KEY (conversation_acquisition_id) REFERENCES working.third_party_conversation_acquisition(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_sou_represented_conversation_id_fkey FOREIGN KEY (represented_conversation_id) REFERENCES working.third_party_conversation(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_originating_device_id_fkey FOREIGN KEY (originating_device_id) REFERENCES registry.device(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_perspective_entity_id_fkey FOREIGN KEY (perspective_entity_id) REFERENCES registry.entity(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_source_version_id_fkey FOREIGN KEY (source_version_id) REFERENCES context.source_version(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_context_thread_source ADD CONSTRAINT third_party_context_thread_source_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES working.third_party_context_thread_source(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_version_context_thread_id_fkey FOREIGN KEY (context_thread_id) REFERENCES working.third_party_context_thread(context_thread_id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_context_thread_version ADD CONSTRAINT third_party_context_thread_version_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES working.third_party_context_thread_version(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_conversation ADD CONSTRAINT third_party_conversation_source_artifact_id_fkey FOREIGN KEY (source_artifact_id) REFERENCES evidence.evidence_hash(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_conversation_acquisition ADD CONSTRAINT third_party_conversation_acquisition_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_conversation_acquisition ADD CONSTRAINT third_party_conversation_acquisition_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES working.third_party_conversation(id) ON DELETE CASCADE;
ALTER TABLE working.third_party_conversation_acquisition ADD CONSTRAINT third_party_conversation_acquisition_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES working.third_party_conversation_acquisition(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_message ADD CONSTRAINT third_party_message_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES working.third_party_conversation(id) ON DELETE CASCADE;
ALTER TABLE working.third_party_message ADD CONSTRAINT third_party_message_normalized_record_id_fkey FOREIGN KEY (normalized_record_id) REFERENCES working.normalized_record(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_message ADD CONSTRAINT third_party_message_route_fk FOREIGN KEY (normalized_record_id, projection_kind) REFERENCES working.message_projection_route(normalized_record_id, projection_kind) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE working.third_party_message ADD CONSTRAINT third_party_message_sender_entity_id_fkey FOREIGN KEY (sender_entity_id) REFERENCES registry.entity(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_message_participant ADD CONSTRAINT third_party_message_participant_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES registry.entity(id) ON DELETE RESTRICT;
ALTER TABLE working.third_party_message_participant ADD CONSTRAINT third_party_message_participant_message_id_fkey FOREIGN KEY (message_id) REFERENCES working.third_party_message(id) ON DELETE CASCADE;
ALTER TABLE working.walk_checkpoint ADD CONSTRAINT walk_checkpoint_walk_run_id_fkey FOREIGN KEY (walk_run_id) REFERENCES working.walk_run(id) ON DELETE CASCADE;
ALTER TABLE working.walk_run ADD CONSTRAINT walk_run_resume_checkpoint_fk FOREIGN KEY (resume_from_checkpoint_id, id) REFERENCES working.walk_checkpoint(id, walk_run_id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE working.walk_run ADD CONSTRAINT walk_run_rewalk_of_id_fkey FOREIGN KEY (rewalk_of_id) REFERENCES working.walk_run(id) ON DELETE RESTRICT;
ALTER TABLE working.walk_step ADD CONSTRAINT walk_step_record_id_fkey FOREIGN KEY (record_id) REFERENCES working.normalized_record(id) ON DELETE RESTRICT;
ALTER TABLE working.walk_step ADD CONSTRAINT walk_step_walk_run_id_fkey FOREIGN KEY (walk_run_id) REFERENCES working.walk_run(id) ON DELETE CASCADE;
ALTER TABLE working.walk_step_realization_retrieval ADD CONSTRAINT walk_step_realization_retrieval_realization_event_id_fkey FOREIGN KEY (realization_event_id) REFERENCES working.realization_event(id) ON DELETE RESTRICT;
ALTER TABLE working.walk_step_realization_retrieval ADD CONSTRAINT walk_step_realization_retrieval_walk_step_id_fkey FOREIGN KEY (walk_step_id) REFERENCES working.walk_step(id) ON DELETE CASCADE;
ALTER TABLE working.walk_step_retrieval ADD CONSTRAINT walk_step_retrieval_record_id_fkey FOREIGN KEY (record_id) REFERENCES working.normalized_record(id) ON DELETE RESTRICT;
ALTER TABLE working.walk_step_retrieval ADD CONSTRAINT walk_step_retrieval_walk_step_id_fkey FOREIGN KEY (walk_step_id) REFERENCES working.walk_step(id) ON DELETE CASCADE;

-- ============ indexes ============
CREATE INDEX IF NOT EXISTS candidate_entity_attrs_gin ON working.candidate_entity USING gin (attrs);
CREATE INDEX IF NOT EXISTS candidate_entity_domain_idx ON working.candidate_entity USING btree (case_id, domain);
CREATE INDEX IF NOT EXISTS candidate_entity_graph_lane_idx ON working.candidate_entity USING btree (graph_lane);
CREATE INDEX IF NOT EXISTS candidate_entity_horizon_idx ON working.candidate_entity USING btree (case_id, knowledge_time);
CREATE INDEX IF NOT EXISTS candidate_entity_normalized_idx ON working.candidate_entity USING btree (normalized_name);
CREATE INDEX IF NOT EXISTS candidate_entity_pending_idx ON working.candidate_entity USING btree (created_at) WHERE (review_state = 'pending'::text);
CREATE INDEX IF NOT EXISTS candidate_entity_run_idx ON working.candidate_entity USING btree (extraction_run_id);
CREATE INDEX IF NOT EXISTS candidate_entity_source_idx ON working.candidate_entity USING btree (source_raw_table, source_raw_id);
CREATE INDEX IF NOT EXISTS candidate_entity_topics_gin ON working.candidate_entity USING gin (topic_tags);
CREATE INDEX IF NOT EXISTS candidate_event_attrs_gin ON working.candidate_event USING gin (attrs);
CREATE INDEX IF NOT EXISTS candidate_event_domain_idx ON working.candidate_event USING btree (case_id, domain);
CREATE INDEX IF NOT EXISTS candidate_event_entity_idx ON working.candidate_event USING btree (primary_entity_id);
CREATE INDEX IF NOT EXISTS candidate_event_graph_lane_idx ON working.candidate_event USING btree (graph_lane);
CREATE INDEX IF NOT EXISTS candidate_event_horizon_idx ON working.candidate_event USING btree (case_id, knowledge_time);
CREATE INDEX IF NOT EXISTS candidate_event_occurred_idx ON working.candidate_event USING btree (occurred_at);
CREATE INDEX IF NOT EXISTS candidate_event_pending_idx ON working.candidate_event USING btree (created_at) WHERE (review_state = 'pending'::text);
CREATE INDEX IF NOT EXISTS candidate_event_run_idx ON working.candidate_event USING btree (extraction_run_id);
CREATE INDEX IF NOT EXISTS candidate_event_topics_gin ON working.candidate_event USING gin (topic_tags);
CREATE INDEX IF NOT EXISTS candidate_event_validity_gist ON working.candidate_event USING gist (validity);
CREATE INDEX IF NOT EXISTS candidate_fact_attrs_gin ON working.candidate_fact USING gin (attrs);
CREATE INDEX IF NOT EXISTS candidate_fact_domain_idx ON working.candidate_fact USING btree (case_id, domain);
CREATE INDEX IF NOT EXISTS candidate_fact_graph_lane_idx ON working.candidate_fact USING btree (graph_lane);
CREATE INDEX IF NOT EXISTS candidate_fact_horizon_idx ON working.candidate_fact USING btree (case_id, knowledge_time);
CREATE INDEX IF NOT EXISTS candidate_fact_object_idx ON working.candidate_fact USING btree (object_entity_id);
CREATE INDEX IF NOT EXISTS candidate_fact_pending_idx ON working.candidate_fact USING btree (created_at) WHERE (review_state = 'pending'::text);
CREATE INDEX IF NOT EXISTS candidate_fact_run_idx ON working.candidate_fact USING btree (extraction_run_id);
CREATE INDEX IF NOT EXISTS candidate_fact_subject_idx ON working.candidate_fact USING btree (subject_entity_id);
CREATE INDEX IF NOT EXISTS candidate_fact_topics_gin ON working.candidate_fact USING gin (topic_tags);
CREATE INDEX IF NOT EXISTS change_decision_proposal_idx ON canon.change_decision USING btree (proposal_id);
CREATE INDEX IF NOT EXISTS change_proposal_open_idx ON canon.change_proposal USING btree (status, tier) WHERE (status = 'proposed'::text);
CREATE INDEX IF NOT EXISTS change_proposal_table_idx ON canon.change_proposal USING btree (canonical_table_id, created_at);
CREATE INDEX IF NOT EXISTS chat_message_conversation_idx ON working.chat_message USING btree (conversation_id, message_index);
CREATE INDEX IF NOT EXISTS chat_message_sent_at_idx ON working.chat_message USING btree (sent_at);
CREATE INDEX IF NOT EXISTS claim_assertion_disposition_idx ON analysis.claim_assertion USING btree (owner_disposition);
CREATE INDEX IF NOT EXISTS claim_assertion_generation_idx ON analysis.claim_assertion USING btree (assertion_generation);
CREATE INDEX IF NOT EXISTS claim_assertion_targets_idx ON analysis.claim_assertion USING gin (argument_targets);
CREATE INDEX IF NOT EXISTS claim_candidate_class_idx ON working.claim_candidate USING btree (claim_class);
CREATE INDEX IF NOT EXISTS claim_candidate_conversation_idx ON working.claim_candidate USING btree (chat_conversation_id, message_ordinal);
CREATE INDEX IF NOT EXISTS claim_candidate_fingerprint_idx ON working.claim_candidate USING btree (fingerprint);
CREATE INDEX IF NOT EXISTS claim_candidate_type_idx ON working.claim_candidate USING btree (claim_type_slug);
CREATE INDEX IF NOT EXISTS claim_temporal_edge_from_idx ON working.claim_temporal_edge USING btree (from_claim_id);
CREATE INDEX IF NOT EXISTS claim_temporal_edge_to_idx ON working.claim_temporal_edge USING btree (to_claim_id) WHERE (to_claim_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS claim_temporal_edge_unresolved_idx ON working.claim_temporal_edge USING btree (created_at) WHERE ((target_kind = 'unresolved_phrase'::text) AND (resolved_claim_id IS NULL));
CREATE INDEX IF NOT EXISTS content_chunk_classification_review_idx ON analysis.content_chunk_classification_decision USING btree (review_state, lane, created_at);
CREATE INDEX IF NOT EXISTS content_chunk_generation_idx ON working.content_chunk USING btree (generation_id, chunk_index);
CREATE INDEX IF NOT EXISTS content_chunk_generation_normalized_idx ON working.content_chunk_generation USING btree (normalized_generation_id) WHERE (normalized_generation_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS content_chunk_generation_source_idx ON working.content_chunk_generation USING btree (source_version_id, generation_ordinal DESC);
CREATE INDEX IF NOT EXISTS content_chunk_hash_lookup_idx ON working.content_chunk USING btree (content_sha256);
CREATE INDEX IF NOT EXISTS content_chunk_projection_pending_idx ON working.content_chunk_projection USING btree (sink, created_at) WHERE (status = 'pending'::text);
CREATE INDEX IF NOT EXISTS content_chunk_source_span_generation_idx ON working.content_chunk_source_span USING btree (generation_id, member_ordinal);
CREATE INDEX IF NOT EXISTS content_chunk_source_span_subject_idx ON working.content_chunk_source_span USING btree (source_version_id, member_ordinal);
CREATE INDEX IF NOT EXISTS court_case_matter_status_idx ON registry.court_case USING btree (matter_id, status);
CREATE INDEX IF NOT EXISTS event_candidate_source_range_source_idx ON timeline.event_candidate_source_range USING btree (source_version_id, event_candidate_id);
CREATE INDEX IF NOT EXISTS evidence_item_matter_case_review_idx ON evidence.evidence_item USING btree (matter_id, court_case_id, review_status) WHERE (matter_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS evidence_vector_projection_job_drain_idx ON working.evidence_vector_projection_job USING btree (status, next_attempt_at, created_at);
CREATE INDEX IF NOT EXISTS extraction_run_extractor_idx ON working.extraction_run USING btree (extractor, extractor_version);
CREATE INDEX IF NOT EXISTS extraction_run_graph_lane_idx ON working.extraction_run USING btree (graph_lane);
CREATE INDEX IF NOT EXISTS extraction_run_started_at_idx ON working.extraction_run USING btree (started_at DESC);
CREATE INDEX IF NOT EXISTS extraction_window_conversation_idx ON working.extraction_window USING btree (chat_conversation_id);
CREATE INDEX IF NOT EXISTS first_party_context_thread_source_lookup_idx ON working.first_party_context_thread_source USING btree (source_version_id, platform, platform_conversation_key);
CREATE INDEX IF NOT EXISTS first_party_context_thread_version_review_idx ON working.first_party_context_thread_version USING btree (review_state, knowledge_available_from);
CREATE INDEX IF NOT EXISTS graph_edge_projection_generation_idx ON analysis.graph_edge_projection USING btree (source_generation);
CREATE INDEX IF NOT EXISTS graph_edge_projection_source_version_idx ON analysis.graph_edge_projection USING btree (source_version_id);
CREATE INDEX IF NOT EXISTS graph_node_projection_chunk_idx ON analysis.graph_node_projection USING btree (content_chunk_id);
CREATE INDEX IF NOT EXISTS graph_node_projection_generation_idx ON analysis.graph_node_projection USING btree (source_generation);
CREATE INDEX IF NOT EXISTS graph_node_projection_source_version_idx ON analysis.graph_node_projection USING btree (source_version_id);
CREATE INDEX IF NOT EXISTS graphrag_manifest_member_normalized_record_idx ON analysis.graphrag_eligibility_manifest_member USING btree (normalized_record_id);
CREATE INDEX IF NOT EXISTS graphrag_manifest_member_source_version_idx ON analysis.graphrag_eligibility_manifest_member USING btree (source_version_id);
CREATE INDEX IF NOT EXISTS hash_receipt_normalized_generation_idx ON context.hash_receipt USING btree (normalized_generation_id) WHERE (hash_kind = 'normalized_generation_manifest_digest'::text);
CREATE INDEX IF NOT EXISTS idx_acquisition_acquired ON evidence.acquisition USING btree (acquired_at);
CREATE INDEX IF NOT EXISTS idx_acquisition_method ON evidence.acquisition USING btree (method);
CREATE INDEX IF NOT EXISTS idx_acquisition_supersedes ON evidence.acquisition USING btree (supersedes_id) WHERE (supersedes_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_agno_approvals_agent_id ON ai.agno_approvals USING btree (agent_id);
CREATE INDEX IF NOT EXISTS idx_agno_approvals_approval_type ON ai.agno_approvals USING btree (approval_type);
CREATE INDEX IF NOT EXISTS idx_agno_approvals_created_at ON ai.agno_approvals USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_agno_approvals_pause_type ON ai.agno_approvals USING btree (pause_type);
CREATE INDEX IF NOT EXISTS idx_agno_approvals_run_id ON ai.agno_approvals USING btree (run_id);
CREATE INDEX IF NOT EXISTS idx_agno_approvals_run_status ON ai.agno_approvals USING btree (run_status);
CREATE INDEX IF NOT EXISTS idx_agno_approvals_schedule_id ON ai.agno_approvals USING btree (schedule_id);
CREATE INDEX IF NOT EXISTS idx_agno_approvals_schedule_run_id ON ai.agno_approvals USING btree (schedule_run_id);
CREATE INDEX IF NOT EXISTS idx_agno_approvals_session_id ON ai.agno_approvals USING btree (session_id);
CREATE INDEX IF NOT EXISTS idx_agno_approvals_source_type ON ai.agno_approvals USING btree (source_type);
CREATE INDEX IF NOT EXISTS idx_agno_approvals_status ON ai.agno_approvals USING btree (status);
CREATE INDEX IF NOT EXISTS idx_agno_approvals_team_id ON ai.agno_approvals USING btree (team_id);
CREATE INDEX IF NOT EXISTS idx_agno_approvals_user_id ON ai.agno_approvals USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_agno_approvals_workflow_id ON ai.agno_approvals USING btree (workflow_id);
CREATE INDEX IF NOT EXISTS idx_agno_component_configs_created_at ON ai.agno_component_configs USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_agno_component_configs_stage ON ai.agno_component_configs USING btree (stage);
CREATE INDEX IF NOT EXISTS idx_agno_component_links_created_at ON ai.agno_component_links USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_agno_component_links_link_kind ON ai.agno_component_links USING btree (link_kind);
CREATE INDEX IF NOT EXISTS idx_agno_components_component_type ON ai.agno_components USING btree (component_type);
CREATE INDEX IF NOT EXISTS idx_agno_components_created_at ON ai.agno_components USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_agno_components_current_version ON ai.agno_components USING btree (current_version);
CREATE INDEX IF NOT EXISTS idx_agno_components_name ON ai.agno_components USING btree (name);
CREATE INDEX IF NOT EXISTS idx_agno_eval_runs_created_at ON ai.agno_eval_runs USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_agno_learnings_agent_id ON ai.agno_learnings USING btree (agent_id);
CREATE INDEX IF NOT EXISTS idx_agno_learnings_created_at ON ai.agno_learnings USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_agno_learnings_entity_id ON ai.agno_learnings USING btree (entity_id);
CREATE INDEX IF NOT EXISTS idx_agno_learnings_entity_type ON ai.agno_learnings USING btree (entity_type);
CREATE INDEX IF NOT EXISTS idx_agno_learnings_learning_type ON ai.agno_learnings USING btree (learning_type);
CREATE INDEX IF NOT EXISTS idx_agno_learnings_namespace ON ai.agno_learnings USING btree (namespace);
CREATE INDEX IF NOT EXISTS idx_agno_learnings_session_id ON ai.agno_learnings USING btree (session_id);
CREATE INDEX IF NOT EXISTS idx_agno_learnings_team_id ON ai.agno_learnings USING btree (team_id);
CREATE INDEX IF NOT EXISTS idx_agno_learnings_user_id ON ai.agno_learnings USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_agno_learnings_workflow_id ON ai.agno_learnings USING btree (workflow_id);
CREATE INDEX IF NOT EXISTS idx_agno_memories_created_at ON ai.agno_memories USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_agno_memories_updated_at ON ai.agno_memories USING btree (updated_at);
CREATE INDEX IF NOT EXISTS idx_agno_memories_user_id ON ai.agno_memories USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_agno_metrics_date ON ai.agno_metrics USING btree (date);
CREATE INDEX IF NOT EXISTS idx_agno_schedule_runs_created_at ON ai.agno_schedule_runs USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_agno_schedule_runs_schedule_id ON ai.agno_schedule_runs USING btree (schedule_id);
CREATE INDEX IF NOT EXISTS idx_agno_schedule_runs_status ON ai.agno_schedule_runs USING btree (status);
CREATE INDEX IF NOT EXISTS idx_agno_schedules_created_at ON ai.agno_schedules USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_agno_schedules_enabled_next_run_at ON ai.agno_schedules USING btree (enabled, next_run_at);
CREATE INDEX IF NOT EXISTS idx_agno_schedules_name ON ai.agno_schedules USING btree (name);
CREATE INDEX IF NOT EXISTS idx_agno_schedules_next_run_at ON ai.agno_schedules USING btree (next_run_at);
CREATE INDEX IF NOT EXISTS idx_agno_schema_versions_created_at ON ai.agno_schema_versions USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_agno_service_accounts_created_at ON ai.agno_service_accounts USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_agno_service_accounts_token_hash ON ai.agno_service_accounts USING btree (token_hash);
CREATE INDEX IF NOT EXISTS idx_agno_sessions_created_at ON ai.agno_sessions USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_agno_sessions_session_type ON ai.agno_sessions USING btree (session_type);
CREATE INDEX IF NOT EXISTS idx_agno_spans_created_at ON ai.agno_spans USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_agno_spans_parent_span_id ON ai.agno_spans USING btree (parent_span_id);
CREATE INDEX IF NOT EXISTS idx_agno_spans_start_time ON ai.agno_spans USING btree (start_time);
CREATE INDEX IF NOT EXISTS idx_agno_spans_trace_id ON ai.agno_spans USING btree (trace_id);
CREATE INDEX IF NOT EXISTS idx_agno_traces_agent_id ON ai.agno_traces USING btree (agent_id);
CREATE INDEX IF NOT EXISTS idx_agno_traces_created_at ON ai.agno_traces USING btree (created_at);
CREATE INDEX IF NOT EXISTS idx_agno_traces_run_id ON ai.agno_traces USING btree (run_id);
CREATE INDEX IF NOT EXISTS idx_agno_traces_session_id ON ai.agno_traces USING btree (session_id);
CREATE INDEX IF NOT EXISTS idx_agno_traces_start_time ON ai.agno_traces USING btree (start_time);
CREATE INDEX IF NOT EXISTS idx_agno_traces_status ON ai.agno_traces USING btree (status);
CREATE INDEX IF NOT EXISTS idx_agno_traces_team_id ON ai.agno_traces USING btree (team_id);
CREATE INDEX IF NOT EXISTS idx_agno_traces_user_id ON ai.agno_traces USING btree (user_id);
CREATE INDEX IF NOT EXISTS idx_agno_traces_workflow_id ON ai.agno_traces USING btree (workflow_id);
CREATE INDEX IF NOT EXISTS idx_alias_dmeta ON registry.entity_alias USING btree (alias_dmeta);
CREATE INDEX IF NOT EXISTS idx_alias_entity ON registry.entity_alias USING btree (entity_id);
CREATE INDEX IF NOT EXISTS idx_alias_trgm ON registry.entity_alias USING gin (((alias_text)::text) gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_anchor_range ON working.temporal_anchor USING gist (valid_range);
CREATE INDEX IF NOT EXISTS idx_art_evid_gin ON working.artifact_registry USING gin (related_source_evidence);
CREATE INDEX IF NOT EXISTS idx_art_kind_status ON working.artifact_registry USING btree (artifact_kind, status);
CREATE INDEX IF NOT EXISTS idx_artmeta_set ON evidence.artifact_metadata USING btree (export_set_id) WHERE (export_set_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_artmeta_source ON evidence.artifact_metadata USING btree (source_id);
CREATE INDEX IF NOT EXISTS idx_art_sha256 ON working.artifact_registry USING btree (sha256);
CREATE INDEX IF NOT EXISTS idx_att_exif ON working.attachment USING gin (exif);
CREATE INDEX IF NOT EXISTS idx_att_msg ON working.attachment USING btree (message_id);
CREATE INDEX IF NOT EXISTS idx_att_ocr_fts ON working.attachment USING gin (to_tsvector('english'::regconfig, ((COALESCE(ocr_text, ''::text) || ' '::text) || COALESCE(transcription, ''::text))));
CREATE INDEX IF NOT EXISTS idx_audit_ledger_action_ts ON ops.audit_ledger USING btree (action_type, ts);
CREATE INDEX IF NOT EXISTS idx_audit_ledger_actor_ts ON ops.audit_ledger USING btree (actor, ts);
CREATE INDEX IF NOT EXISTS idx_audit_ledger_ts ON ops.audit_ledger USING btree (ts);
CREATE INDEX IF NOT EXISTS idx_behavior_category_alias ON reference.behavior_category USING gin (aliases);
CREATE INDEX IF NOT EXISTS idx_behavior_category_mcl_factor ON reference.behavior_category_mcl USING btree (factor_code);
CREATE INDEX IF NOT EXISTS idx_behavior_category_mcl ON reference.behavior_category USING gin (mcl_factors);
CREATE INDEX IF NOT EXISTS idx_call_conv ON working.call_log USING btree (conversation_id);
CREATE INDEX IF NOT EXISTS idx_call_started ON working.call_log USING btree (started_at);
CREATE INDEX IF NOT EXISTS idx_chunkclass_conv ON analysis.chunk_classification USING btree (conversation_key, seq);
CREATE INDEX IF NOT EXISTS idx_chunkclass_runkey ON analysis.chunk_classification USING btree (run_key, batch_index);
CREATE INDEX IF NOT EXISTS idx_chunkclass_version ON analysis.chunk_classification USING btree (classifier_version);
CREATE INDEX IF NOT EXISTS idx_clog_record ON public.change_log USING btree (table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_clog_time ON public.change_log USING btree (change_timestamp);
CREATE INDEX IF NOT EXISTS idx_corroboration_flag_status ON analysis.corroboration_flag USING btree (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_corroboration_flag_target ON analysis.corroboration_flag USING btree (target_kind, target_id);
CREATE INDEX IF NOT EXISTS idx_ctxasset_archive ON working.context_asset USING btree (archive_id);
CREATE INDEX IF NOT EXISTS idx_ctxasset_category ON working.context_asset USING btree (asset_category);
CREATE INDEX IF NOT EXISTS idx_ctxasset_conv ON working.context_asset USING btree (conversation_id);
CREATE INDEX IF NOT EXISTS idx_ctxrec_conv ON working.context_record USING btree (source, conversation_id);
CREATE INDEX IF NOT EXISTS idx_ctxrec_graphiti_pending ON working.context_record USING btree (conversation_id) WHERE (graphiti_synced_at IS NULL);
CREATE INDEX IF NOT EXISTS idx_ctxrec_occurred ON working.context_record USING btree (occurred_at);
CREATE INDEX IF NOT EXISTS idx_ctxrec_weaviate_pending ON working.context_record USING btree (conversation_id) WHERE (weaviate_synced_at IS NULL);
CREATE INDEX IF NOT EXISTS idx_custody_source ON evidence.custody_event USING btree (source_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_custody_type ON evidence.custody_event USING btree (event_type, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_detection_pattern_cat ON reference.detection_pattern USING btree (category_id);
CREATE INDEX IF NOT EXISTS idx_detection_pattern_kw ON reference.detection_pattern USING gin (keywords);
CREATE INDEX IF NOT EXISTS idx_detection_pattern_trgm ON reference.detection_pattern USING gin (pattern gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_discreq_task ON analysis.discovery_request USING btree (task_id, status);
CREATE INDEX IF NOT EXISTS idx_email_owner ON working.email USING btree (owner_entity_id);
CREATE INDEX IF NOT EXISTS idx_entity_dispname_trgm ON registry.entity USING gin (((display_name)::text) gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_entity_live ON registry.entity USING btree (id) WHERE (merged_into_id IS NULL);
CREATE INDEX IF NOT EXISTS idx_entity_normname_trgm ON registry.entity USING gin (((normalized_name)::text) gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_entity_type ON registry.entity USING btree (entity_type);
CREATE INDEX IF NOT EXISTS idx_esr_attestation ON working.event_source_record USING btree (record_id) WHERE (event_id IS NULL);
CREATE INDEX IF NOT EXISTS idx_esr_disagree ON working.event_source_record USING btree (record_id) WHERE (agrees IS FALSE);
CREATE INDEX IF NOT EXISTS idx_esr_rawref ON working.event_source_record USING btree (raw_ref);
CREATE INDEX IF NOT EXISTS idx_esr_record ON working.event_source_record USING btree (record_id);
CREATE INDEX IF NOT EXISTS idx_esr_source ON working.event_source_record USING btree (source_id);
CREATE INDEX IF NOT EXISTS idx_event_geo ON analysis.timeline_event USING gist (primary_geo);
CREATE INDEX IF NOT EXISTS idx_event_mcl ON analysis.timeline_event USING gin (mcl_relevance);
CREATE INDEX IF NOT EXISTS idx_event_title_trgm ON analysis.timeline_event USING gin (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_event_type_point ON analysis.timeline_event USING btree (event_type, valid_point);
CREATE INDEX IF NOT EXISTS idx_event_validrange ON analysis.timeline_event USING gist (valid_range);
CREATE INDEX IF NOT EXISTS idx_evhash_filenode ON evidence.evidence_hash USING btree (file_node_id);
CREATE INDEX IF NOT EXISTS idx_evhash_level_source ON evidence.evidence_hash USING btree (level, source_id);
CREATE INDEX IF NOT EXISTS idx_evhash_meta ON evidence.evidence_hash USING gin (meta);
CREATE INDEX IF NOT EXISTS idx_evidence_hash_digest ON evidence.evidence_hash USING btree (digest);
CREATE INDEX IF NOT EXISTS idx_evitem_case ON evidence.evidence_item USING btree (case_id, review_status);
CREATE INDEX IF NOT EXISTS idx_evitem_export ON evidence.evidence_item USING btree (case_id) WHERE (safe_for_legal_use = true);
CREATE INDEX IF NOT EXISTS idx_evitem_title_trgm ON evidence.evidence_item USING gin (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_factcite_factor ON analysis.factor_citation USING btree (factor, supports_factor);
CREATE INDEX IF NOT EXISTS idx_factcite_item ON analysis.factor_citation USING btree (evidence_item_id);
CREATE INDEX IF NOT EXISTS idx_filenode_parent ON raw.file_node USING btree (parent_node_id);
CREATE INDEX IF NOT EXISTS idx_filenode_path ON raw.file_node USING gist (node_path);
CREATE INDEX IF NOT EXISTS idx_filenode_sha ON raw.file_node USING btree (sha256);
CREATE INDEX IF NOT EXISTS idx_filenode_source ON raw.file_node USING btree (source_id);
CREATE INDEX IF NOT EXISTS idx_finding_mcl ON analysis.finding USING gin (mcl_factors);
CREATE INDEX IF NOT EXISTS idx_finding_review ON analysis.finding USING btree (review_status);
CREATE INDEX IF NOT EXISTS idx_finding_type ON analysis.finding USING btree (finding_type);
CREATE INDEX IF NOT EXISTS idx_gps_point_devtime ON raw.gps_point USING btree (device_id, captured_at);
CREATE INDEX IF NOT EXISTS idx_gps_point_geog ON raw.gps_point USING gist (geog);
CREATE INDEX IF NOT EXISTS idx_gps_point_raw ON raw.gps_point USING gin (raw_data);
CREATE INDEX IF NOT EXISTS idx_gps_point_seq ON raw.gps_point USING btree (source_id, point_sequence);
CREATE INDEX IF NOT EXISTS idx_handle_owner ON working.handle USING btree (owner_entity_id);
CREATE INDEX IF NOT EXISTS idx_handle_trgm ON working.handle USING gin (((handle)::text) gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_ingest_run_open ON evidence.ingest_run USING btree (status) WHERE (status = ANY (ARRAY['running'::text, 'failed'::text, 'rolled_back'::text]));
CREATE INDEX IF NOT EXISTS idx_ingest_run_sha ON evidence.ingest_run USING btree (source_sha256);
CREATE INDEX IF NOT EXISTS idx_ingest_run_source ON evidence.ingest_run USING btree (source_id);
CREATE INDEX IF NOT EXISTS idx_ingest_run_started ON evidence.ingest_run USING btree (started_at DESC);
CREATE INDEX IF NOT EXISTS idx_legal_issue_case ON reference.legal_issue USING btree (case_id, issue_type);
CREATE INDEX IF NOT EXISTS idx_legaltl_case ON analysis.legal_timeline_event USING btree (case_id, event_date);
CREATE INDEX IF NOT EXISTS idx_legaltl_fact ON analysis.legal_timeline_event USING gin (mcl_factors);
CREATE INDEX IF NOT EXISTS idx_locassert_geog ON analysis.location_assertion USING gist (geog);
CREATE INDEX IF NOT EXISTS idx_locassert_subject ON analysis.location_assertion USING btree (subject_type, subject_id);
CREATE INDEX IF NOT EXISTS idx_location_geog ON registry.location USING gist (geog);
CREATE INDEX IF NOT EXISTS idx_location_name_trgm ON registry.location USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_mem_fts ON public.memory_items USING gin (fts);
CREATE INDEX IF NOT EXISTS idx_mem_title_trgm ON public.memory_items USING gin (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_mem_type_status ON public.memory_items USING btree (memory_type, status);
CREATE INDEX IF NOT EXISTS idx_mention_dmeta ON working.entity_mention USING btree (mention_dmeta);
CREATE INDEX IF NOT EXISTS idx_mention_subject ON working.entity_mention USING btree (subject_type, subject_id);
CREATE INDEX IF NOT EXISTS idx_mention_trgm ON working.entity_mention USING gin (((surface_text)::text) gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_message_derived ON working.message USING btree (derived_from_record_id);
CREATE INDEX IF NOT EXISTS idx_msg_attrs ON working.message USING gin (platform_attrs);
CREATE INDEX IF NOT EXISTS idx_msg_chash ON working.message USING btree (content_sha256);
CREATE INDEX IF NOT EXISTS idx_msg_conv_time ON working.message USING btree (conversation_id, ts_utc);
CREATE INDEX IF NOT EXISTS idx_msgpart_msg ON working.message_participant USING btree (message_id);
CREATE INDEX IF NOT EXISTS idx_msg_private ON working.message USING btree (id) WHERE is_private;
CREATE INDEX IF NOT EXISTS idx_msg_sender ON working.message USING btree (sender_e164);
CREATE INDEX IF NOT EXISTS idx_normrec_acq_fk ON working.normalized_record USING btree (acquisition_id);
CREATE INDEX IF NOT EXISTS idx_normrec_acquired ON working.normalized_record USING btree (acquired_at);
CREATE INDEX IF NOT EXISTS idx_normrec_artifact ON working.normalized_record USING btree (artifact_id);
CREATE INDEX IF NOT EXISTS idx_normrec_attrs ON working.normalized_record USING gin (attrs);
CREATE INDEX IF NOT EXISTS idx_normrec_conv ON working.normalized_record USING btree (source, conversation_id);
CREATE INDEX IF NOT EXISTS idx_normrec_convref_time ON working.normalized_record USING btree (conversation_ref, occurred_at);
CREATE INDEX IF NOT EXISTS idx_normrec_device ON working.normalized_record USING btree (device_id);
CREATE INDEX IF NOT EXISTS idx_normrec_fts ON working.normalized_record USING gin (to_tsvector('english'::regconfig, COALESCE(content, ''::text)));
CREATE INDEX IF NOT EXISTS idx_normrec_occurred ON working.normalized_record USING btree (occurred_at);
CREATE INDEX IF NOT EXISTS idx_normrec_rawid ON working.normalized_record USING btree (derived_from_raw_id);
CREATE INDEX IF NOT EXISTS idx_normrec_realized ON working.normalized_record USING btree (realized_at) WHERE (realized_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_normrec_sender ON working.normalized_record USING btree (sender_entity_id);
CREATE INDEX IF NOT EXISTS idx_normrec_trgm ON working.normalized_record USING gin (content gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_oq_blocks ON public.open_questions USING btree (blocks_export) WHERE blocks_export;
CREATE INDEX IF NOT EXISTS idx_pattern_finding_author ON analysis.pattern_finding USING btree (author_party);
CREATE INDEX IF NOT EXISTS idx_pattern_finding_category ON analysis.pattern_finding USING btree (category_id);
CREATE INDEX IF NOT EXISTS idx_pattern_finding_finding ON analysis.pattern_finding USING btree (finding_id);
CREATE INDEX IF NOT EXISTS idx_pattern_finding_matched_trgm ON analysis.pattern_finding USING gin (matched_text gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_pattern_finding_subject ON analysis.pattern_finding USING btree (subject_type, subject_id);
CREATE INDEX IF NOT EXISTS idx_pattern_finding_triage ON analysis.pattern_finding USING btree (severity DESC NULLS LAST, review_status);
CREATE INDEX IF NOT EXISTS idx_pattern_lexicon_type ON reference.pattern_lexicon USING btree (lexicon_type);
CREATE INDEX IF NOT EXISTS idx_pattern_lexicon_variants ON reference.pattern_lexicon USING gin (variants);
CREATE INDEX IF NOT EXISTS idx_pattern_set_active ON reference.detection_pattern_set USING btree (is_active) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_phone_e164 ON working.phone USING btree (((e164)::text));
CREATE INDEX IF NOT EXISTS idx_phone_owner ON working.phone USING btree (owner_entity_id);
CREATE INDEX IF NOT EXISTS idx_raw_activity_source ON raw.raw_activity USING btree (source_id);
CREATE INDEX IF NOT EXISTS idx_raw_activity_start ON raw.raw_activity USING gist (start_geog);
CREATE INDEX IF NOT EXISTS idx_raw_activity_utc ON raw.raw_activity USING btree (start_utc);
CREATE INDEX IF NOT EXISTS idx_raw_ai_chat_device ON raw.raw_ai_chat USING btree (device_id);
CREATE INDEX IF NOT EXISTS idx_raw_ai_chat_hash ON raw.raw_ai_chat USING btree (content_hash);
CREATE INDEX IF NOT EXISTS idx_raw_ai_chat_live ON raw.raw_ai_chat USING btree (source_id) WHERE (superseded_by IS NULL);
CREATE INDEX IF NOT EXISTS idx_raw_ai_chat_source ON raw.raw_ai_chat USING btree (source_id);
CREATE INDEX IF NOT EXISTS idx_raw_csv_device ON raw.raw_csv USING btree (device_id);
CREATE INDEX IF NOT EXISTS idx_raw_csv_hash ON raw.raw_csv USING btree (content_hash);
CREATE INDEX IF NOT EXISTS idx_raw_csv_live ON raw.raw_csv USING btree (source_id) WHERE (superseded_by IS NULL);
CREATE INDEX IF NOT EXISTS idx_raw_csv_source ON raw.raw_csv USING btree (source_id);
CREATE INDEX IF NOT EXISTS idx_raw_facebook_device ON raw.raw_facebook USING btree (device_id);
CREATE INDEX IF NOT EXISTS idx_raw_facebook_hash ON raw.raw_facebook USING btree (content_hash);
CREATE INDEX IF NOT EXISTS idx_raw_facebook_live ON raw.raw_facebook USING btree (source_id) WHERE (superseded_by IS NULL);
CREATE INDEX IF NOT EXISTS idx_raw_facebook_source ON raw.raw_facebook USING btree (source_id);
CREATE INDEX IF NOT EXISTS idx_raw_imessage_device ON raw.raw_imessage USING btree (device_id);
CREATE INDEX IF NOT EXISTS idx_raw_imessage_hash ON raw.raw_imessage USING btree (content_hash);
CREATE INDEX IF NOT EXISTS idx_raw_imessage_live ON raw.raw_imessage USING btree (source_id) WHERE (superseded_by IS NULL);
CREATE INDEX IF NOT EXISTS idx_raw_imessage_source ON raw.raw_imessage USING btree (source_id);
CREATE INDEX IF NOT EXISTS idx_raw_path_geog ON raw.raw_path USING gist (point_geog);
CREATE INDEX IF NOT EXISTS idx_raw_path_source ON raw.raw_path USING btree (source_id, path_serial, point_sequence);
CREATE INDEX IF NOT EXISTS idx_raw_phone_device ON raw.raw_phone USING btree (device_id);
CREATE INDEX IF NOT EXISTS idx_raw_phone_hash ON raw.raw_phone USING btree (content_hash);
CREATE INDEX IF NOT EXISTS idx_raw_phone_live ON raw.raw_phone USING btree (source_id) WHERE (superseded_by IS NULL);
CREATE INDEX IF NOT EXISTS idx_raw_phone_source ON raw.raw_phone USING btree (source_id);
CREATE INDEX IF NOT EXISTS idx_raw_rejected_gin ON raw.raw_rejected USING gin (raw);
CREATE INDEX IF NOT EXISTS idx_raw_rejected_reason ON raw.raw_rejected USING btree (reason);
CREATE INDEX IF NOT EXISTS idx_raw_rejected_run ON raw.raw_rejected USING btree (ingest_run_id);
CREATE INDEX IF NOT EXISTS idx_raw_rejected_sha ON raw.raw_rejected USING btree (source_sha256);
CREATE INDEX IF NOT EXISTS idx_raw_sms_device ON raw.raw_sms USING btree (device_id);
CREATE INDEX IF NOT EXISTS idx_raw_sms_hash ON raw.raw_sms USING btree (content_hash);
CREATE INDEX IF NOT EXISTS idx_raw_sms_live ON raw.raw_sms USING btree (source_id) WHERE (superseded_by IS NULL);
CREATE INDEX IF NOT EXISTS idx_raw_sms_source ON raw.raw_sms USING btree (source_id);
CREATE INDEX IF NOT EXISTS idx_raw_trip_source ON raw.raw_trip USING btree (source_id);
CREATE INDEX IF NOT EXISTS idx_raw_trip_utc ON raw.raw_trip USING btree (start_utc);
CREATE INDEX IF NOT EXISTS idx_raw_visit_geog ON raw.raw_visit USING gist (geog);
CREATE INDEX IF NOT EXISTS idx_raw_visit_source ON raw.raw_visit USING btree (source_id);
CREATE INDEX IF NOT EXISTS idx_raw_visit_utc ON raw.raw_visit USING btree (start_utc);
CREATE INDEX IF NOT EXISTS idx_rdec_target ON analysis.review_decision USING btree (target_kind, target_id);
CREATE INDEX IF NOT EXISTS idx_relcls_phase ON analysis.relational_classification USING btree (cycle_phase);
CREATE INDEX IF NOT EXISTS idx_relcls_review ON analysis.relational_classification USING btree (review_status) WHERE requires_human_review;
CREATE INDEX IF NOT EXISTS idx_relcls_subject ON analysis.relational_classification USING btree (subject_type, subject_id);
CREATE INDEX IF NOT EXISTS idx_res_canonical ON working.entity_resolution USING btree (canonical_entity_id);
CREATE INDEX IF NOT EXISTS idx_resev_res ON analysis.resolution_evidence USING btree (resolution_id, polarity);
CREATE INDEX IF NOT EXISTS idx_rtask_state ON analysis.review_task USING btree (state, trigger_code);
CREATE INDEX IF NOT EXISTS idx_run_inputs_gin ON ops.processing_run USING gin (input_evidence_ids);
CREATE INDEX IF NOT EXISTS idx_run_started ON ops.processing_run USING btree (started_at DESC);
CREATE INDEX IF NOT EXISTS idx_run_type_status ON ops.processing_run USING btree (run_type, status);
CREATE INDEX IF NOT EXISTS idx_score_current ON analysis.score USING btree (score_type) WHERE (valid_to IS NULL);
CREATE INDEX IF NOT EXISTS idx_score_target ON analysis.score USING btree (target_kind, target_id);
CREATE INDEX IF NOT EXISTS idx_sess_fts ON public.session_summaries USING gin (fts);
CREATE INDEX IF NOT EXISTS idx_source_acquisition ON evidence.source USING btree (acquisition_id);
CREATE INDEX IF NOT EXISTS idx_source_custody ON evidence.source USING btree (custody_status);
CREATE INDEX IF NOT EXISTS idx_source_filename_trgm ON evidence.source USING gin (original_filename gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_source_orig_meta ON evidence.source USING gin (original_metadata);
CREATE INDEX IF NOT EXISTS idx_source_platform ON evidence.source USING btree (source_platform, source_type);
CREATE INDEX IF NOT EXISTS idx_source_supersedes ON evidence.source USING btree (supersedes_source_id);
CREATE INDEX IF NOT EXISTS idx_ta_current ON analysis.time_assertion USING btree (event_id) WHERE upper_inf(sys_period);
CREATE INDEX IF NOT EXISTS idx_task_case_status ON analysis.evidence_task USING btree (case_id, status);
CREATE INDEX IF NOT EXISTS idx_taskevent_task ON analysis.task_event USING btree (task_id, ts DESC);
CREATE INDEX IF NOT EXISTS idx_task_priority ON analysis.evidence_task USING btree (priority, due_date);
CREATE INDEX IF NOT EXISTS idx_task_riskkind ON analysis.evidence_task USING gin (risk_kind);
CREATE INDEX IF NOT EXISTS idx_ta_validrange ON analysis.time_assertion USING gist (valid_range);
CREATE INDEX IF NOT EXISTS idx_tcl_run ON ops.tool_call_ledger USING btree (run_id);
CREATE INDEX IF NOT EXISTS idx_transcript_insight_type ON public.transcript_insight USING btree (insight_type, mined_at DESC);
CREATE INDEX IF NOT EXISTS idx_walk_run_base_version ON working.walk_run USING btree (base_version);
CREATE INDEX IF NOT EXISTS idx_walk_run_case_status ON working.walk_run USING btree (case_id, status);
CREATE INDEX IF NOT EXISTS idx_walk_step_record ON working.walk_step USING btree (record_id) WHERE (record_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_walk_step_retrieval_record ON working.walk_step_retrieval USING btree (record_id);
CREATE INDEX IF NOT EXISTS idx_walk_step_run_step ON working.walk_step USING btree (walk_run_id, step_no);
CREATE INDEX IF NOT EXISTS idx_workflow_run_gate_state ON analysis.workflow_run USING btree (gate_state) WHERE (gate_state IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_workflow_run_gate_state ON ops.workflow_run USING btree (gate_state) WHERE (gate_state IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_workflow_run_parent ON analysis.workflow_run USING btree (parent_run_id) WHERE (parent_run_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_workflow_run_parent ON ops.workflow_run USING btree (parent_run_id) WHERE (parent_run_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_workflow_run_review_action_run ON ops.workflow_run_review_action USING btree (run_id, created_at, action_id);
CREATE INDEX IF NOT EXISTS idx_workflow_run_stage_run ON analysis.workflow_run_stage USING btree (run_id);
CREATE INDEX IF NOT EXISTS idx_workflow_run_stage_run ON ops.workflow_run_stage USING btree (run_id);
CREATE INDEX IF NOT EXISTS idx_workflow_run_status ON analysis.workflow_run USING btree (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflow_run_status ON ops.workflow_run USING btree (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflow_run_trace_id ON ops.workflow_run USING btree (trace_id) WHERE (trace_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_xref_b ON registry.id_xref USING btree (system_b, native_id_b);
CREATE INDEX IF NOT EXISTS idx_xref_entity ON registry.id_xref USING btree (canonical_entity_id);
CREATE INDEX IF NOT EXISTS knowledge_evidence_promotion_case_time_idx ON analysis.knowledge_evidence_promotion USING btree (court_case_id, promoted_at DESC);
CREATE INDEX IF NOT EXISTS knowledge_evidence_promotion_matter_time_idx ON analysis.knowledge_evidence_promotion USING btree (matter_id, promoted_at DESC);
CREATE INDEX IF NOT EXISTS knowledge_evidence_promotion_record_idx ON analysis.knowledge_evidence_promotion USING btree (normalized_record_id);
CREATE INDEX IF NOT EXISTS matter_knowledge_partition_default_case_idx ON analysis.matter_knowledge_partition USING btree (default_court_case_id);
CREATE INDEX IF NOT EXISTS matter_knowledge_partition_matter_idx ON analysis.matter_knowledge_partition USING btree (matter_id);
CREATE INDEX IF NOT EXISTS message_projection_route_kind_idx ON working.message_projection_route USING btree (projection_kind, decision_state, normalized_record_id);
CREATE INDEX IF NOT EXISTS normalization_lineage_raw_record_idx ON context.normalization_lineage USING btree (raw_record_id, normalized_record_id);
CREATE INDEX IF NOT EXISTS normalized_record_domain_idx ON working.normalized_record USING btree (case_id, domain);
CREATE INDEX IF NOT EXISTS normalized_record_horizon_idx ON working.normalized_record USING btree (case_id, knowledge_time);
CREATE INDEX IF NOT EXISTS normalized_record_topics_gin ON working.normalized_record USING gin (topic_tags);
CREATE INDEX IF NOT EXISTS promotion_candidate_idx ON working.promotion USING btree (candidate_kind, candidate_id);
CREATE INDEX IF NOT EXISTS promotion_lane_idx ON working.promotion USING btree (lane, promoted_at DESC);
CREATE INDEX IF NOT EXISTS promotion_target_idx ON working.promotion USING btree (target_system, promoted_at DESC);
CREATE INDEX IF NOT EXISTS raw_record_identity_generation_idx ON context.raw_record_identity USING btree (raw_generation_id, record_ordinal);
CREATE INDEX IF NOT EXISTS raw_record_identity_source_version_idx ON context.raw_record_identity USING btree (source_version_id, id);
CREATE INDEX IF NOT EXISTS realization_event_case_state_time_idx ON working.realization_event USING btree (case_id, approval_state, realized_at);
CREATE INDEX IF NOT EXISTS realization_event_record_record_idx ON working.realization_event_record USING btree (normalized_record_id);
CREATE INDEX IF NOT EXISTS recompute_queue_pending_idx ON canon.recompute_queue USING btree (recompute_target, created_at) WHERE (status = 'pending'::text);
CREATE INDEX IF NOT EXISTS relative_time_anchor_bounds_idx ON context.relative_time_anchor USING btree (lower_bound_at, upper_bound_at);
CREATE INDEX IF NOT EXISTS source_provenance_occurred_idx ON working.source_provenance USING btree (occurred_at);
CREATE INDEX IF NOT EXISTS source_provenance_realized_idx ON working.source_provenance USING btree (realized_at);
CREATE INDEX IF NOT EXISTS source_provenance_source_idx ON working.source_provenance USING btree (source_raw_table, source_raw_id);
CREATE INDEX IF NOT EXISTS source_range_locator_subject_idx ON context.source_range_locator USING btree (source_version_id, coordinate_system, range_start, range_end);
CREATE INDEX IF NOT EXISTS source_version_source_context_idx ON context.source_version USING btree (source_context_ref) WHERE (source_context_ref IS NOT NULL);
CREATE INDEX IF NOT EXISTS third_party_context_thread_source_lookup_idx ON working.third_party_context_thread_source USING btree (source_version_id, platform, platform_conversation_key);
CREATE INDEX IF NOT EXISTS third_party_context_thread_version_review_idx ON working.third_party_context_thread_version USING btree (review_state, knowledge_available_from);
CREATE INDEX IF NOT EXISTS third_party_conv_acq_acquisition_idx ON working.third_party_conversation_acquisition USING btree (acquisition_id);
CREATE INDEX IF NOT EXISTS third_party_conv_acq_current_idx ON working.third_party_conversation_acquisition USING btree (conversation_id, approval_state, acquisition_id);
CREATE INDEX IF NOT EXISTS third_party_conversation_case_time_idx ON working.third_party_conversation USING btree (case_id, started_at);
CREATE INDEX IF NOT EXISTS third_party_message_conv_time_idx ON working.third_party_message USING btree (conversation_id, occurred_at, id);
CREATE INDEX IF NOT EXISTS third_party_message_participant_entity_idx ON working.third_party_message_participant USING btree (entity_id, message_id);
CREATE INDEX IF NOT EXISTS third_party_message_sender_idx ON working.third_party_message USING btree (sender_entity_id, occurred_at);
CREATE INDEX IF NOT EXISTS timeline_member_collection_idx ON timeline.timeline_member USING btree (collection_id, included);
CREATE INDEX IF NOT EXISTS timeline_projection_member_generation_idx ON timeline.timeline_projection_member USING btree (generation_id);
CREATE INDEX IF NOT EXISTS timeline_projection_member_opensearch_doc_idx ON timeline.timeline_projection_member USING btree (opensearch_doc_id);
CREATE INDEX IF NOT EXISTS timeline_projection_member_stable_idx ON timeline.timeline_projection_member USING btree (stable_member_id, generation_id);
CREATE INDEX IF NOT EXISTS timeline_projection_receipt_generation_idx ON timeline.timeline_projection_receipt USING btree (generation_id, status);
CREATE INDEX IF NOT EXISTS timeline_projection_receipt_member_idx ON timeline.timeline_projection_receipt USING btree (member_id, status);
CREATE INDEX IF NOT EXISTS uiw_preview_event_replay_idx ON context.uiw_preview_event USING btree (preview_handle, event_id);
CREATE INDEX IF NOT EXISTS uiw_preview_message_page_idx ON context.uiw_preview_message USING btree (preview_handle, snapshot_seq, ordinal, message_id);
CREATE INDEX IF NOT EXISTS walk_checkpoint_run_latest_idx ON working.walk_checkpoint USING btree (walk_run_id, checkpoint_no DESC);
CREATE INDEX IF NOT EXISTS walk_step_realization_retrieval_event_idx ON working.walk_step_realization_retrieval USING btree (realization_event_id);
CREATE UNIQUE INDEX IF NOT EXISTS agno_service_accounts_uq_active_name ON ai.agno_service_accounts USING btree (name) WHERE (revoked_at IS NULL);
CREATE UNIQUE INDEX IF NOT EXISTS candidate_entity_dedup_idx ON working.candidate_entity USING btree (source_raw_table, source_raw_id, content_sha256);
CREATE UNIQUE INDEX IF NOT EXISTS candidate_event_dedup_idx ON working.candidate_event USING btree (source_raw_table, source_raw_id, content_sha256);
CREATE UNIQUE INDEX IF NOT EXISTS candidate_fact_dedup_idx ON working.candidate_fact USING btree (source_raw_table, source_raw_id, content_sha256);
CREATE UNIQUE INDEX IF NOT EXISTS claim_candidate_run_span_key ON working.claim_candidate USING btree (extraction_run_id, chat_message_id, content_sha256);
CREATE UNIQUE INDEX IF NOT EXISTS content_chunk_one_initial_context_uq ON analysis.content_chunk_classification_decision USING btree (chunk_id) WHERE (decision_kind = 'initial_context'::text);
CREATE UNIQUE INDEX IF NOT EXISTS court_case_docket_per_matter_idx ON registry.court_case USING btree (matter_id, lower(docket_number)) WHERE (docket_number IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS court_case_one_primary_per_matter_idx ON registry.court_case USING btree (matter_id) WHERE is_primary;
CREATE UNIQUE INDEX IF NOT EXISTS hash_manifest_member_normalized_record_uq ON context.hash_manifest_member USING btree (hash_manifest_id, normalized_record_id) WHERE (normalized_record_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS hash_manifest_member_raw_record_uq ON context.hash_manifest_member USING btree (hash_manifest_id, raw_record_id) WHERE (raw_record_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS hash_manifest_normalized_generation_kind_uq ON context.hash_manifest USING btree (normalized_generation_id, hash_kind) WHERE (normalized_generation_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS hash_manifest_raw_generation_kind_uq ON context.hash_manifest USING btree (raw_generation_id, hash_kind) WHERE (raw_generation_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS hash_receipt_context_raw_generation_fingerprint_uq ON context.hash_receipt USING btree (raw_generation_id) WHERE (hash_kind = 'context_raw_generation_fingerprint'::text);
CREATE UNIQUE INDEX IF NOT EXISTS hash_receipt_context_raw_record_fingerprint_uq ON context.hash_receipt USING btree (raw_record_id) WHERE (hash_kind = 'context_raw_record_fingerprint'::text);
CREATE UNIQUE INDEX IF NOT EXISTS hash_receipt_context_source_fingerprint_uq ON context.hash_receipt USING btree (source_version_id) WHERE (hash_kind = 'context_source_fingerprint'::text);
CREATE UNIQUE INDEX IF NOT EXISTS hash_receipt_normalized_generation_manifest_uq ON context.hash_receipt USING btree (normalized_generation_id) WHERE (hash_kind = 'normalized_generation_manifest_digest'::text);
CREATE UNIQUE INDEX IF NOT EXISTS hash_receipt_normalized_record_uq ON context.hash_receipt USING btree (normalized_record_id) WHERE (hash_kind = 'normalized_record_digest'::text);
CREATE UNIQUE INDEX IF NOT EXISTS message_one_per_spine_uq ON working.message USING btree (derived_from_record_id) WHERE (derived_from_record_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS normalized_record_source_key_uq ON working.normalized_record USING btree (artifact_id, source, source_record_key) WHERE (source_record_key IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS person_single_user_role_uq ON registry.person USING btree (role_in_case) WHERE (role_in_case = 'user'::text);
CREATE UNIQUE INDEX IF NOT EXISTS promotion_live_idx ON working.promotion USING btree (candidate_kind, candidate_id, lane, target_system) WHERE (revoked_at IS NULL);
CREATE UNIQUE INDEX IF NOT EXISTS source_provenance_revision_idx ON working.source_provenance USING btree (source_raw_table, source_raw_id, revision);
CREATE UNIQUE INDEX IF NOT EXISTS source_version_object_one_original_uq ON context.source_version_object USING btree (source_version_id) WHERE (object_role = 'original'::text);
CREATE UNIQUE INDEX IF NOT EXISTS third_party_message_external_uq ON working.third_party_message USING btree (conversation_id, external_id) WHERE (external_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS third_party_message_one_sender_uq ON working.third_party_message_participant USING btree (message_id) WHERE (role = 'from'::text);
CREATE UNIQUE INDEX IF NOT EXISTS timeline_member_candidate_uq ON timeline.timeline_member USING btree (collection_id, candidate_id) WHERE (candidate_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS timeline_member_governed_uq ON timeline.timeline_member USING btree (collection_id, governed_source_schema, governed_source_table, governed_source_pk) WHERE (governed_source_schema IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS uq_chunkclass_batch_item ON analysis.chunk_classification USING btree (run_key, batch_index, record_ref, classifier_version);
CREATE UNIQUE INDEX IF NOT EXISTS uq_chunkclass_decision_id ON analysis.chunk_classification USING btree (decision_id) WHERE (decision_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS uq_device_label ON registry.device USING btree (device_label) WHERE (device_label IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS uq_entity_norm ON registry.entity USING btree (entity_type, normalized_name) WHERE ((normalized_name IS NOT NULL) AND (merged_into_id IS NULL));
CREATE UNIQUE INDEX IF NOT EXISTS uq_esr_record ON working.event_source_record USING btree (event_id, record_id) WHERE (record_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS uq_location_dedup ON registry.location USING btree (geohash9, COALESCE(name, ''::text));
CREATE UNIQUE INDEX IF NOT EXISTS uq_raw_ai_chat_dedupe ON raw.raw_ai_chat USING btree (device_id, medium, content_hash) NULLS NOT DISTINCT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_raw_csv_dedupe ON raw.raw_csv USING btree (device_id, medium, content_hash) NULLS NOT DISTINCT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_raw_facebook_dedupe ON raw.raw_facebook USING btree (device_id, medium, content_hash) NULLS NOT DISTINCT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_raw_imessage_dedupe ON raw.raw_imessage USING btree (device_id, medium, content_hash) NULLS NOT DISTINCT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_raw_phone_dedupe ON raw.raw_phone USING btree (device_id, medium, content_hash) NULLS NOT DISTINCT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_raw_sms_dedupe ON raw.raw_sms USING btree (device_id, medium, content_hash) NULLS NOT DISTINCT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_res_current ON working.entity_resolution USING btree (mention_id) WHERE upper_inf(sys_period);

-- ============ functions (guards excluded by design) ============
CREATE OR REPLACE FUNCTION analysis.entity_candidate_no_mutate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.entity_text  IS DISTINCT FROM OLD.entity_text
     OR NEW.record_id IS DISTINCT FROM OLD.record_id
     OR NEW.extractor IS DISTINCT FROM OLD.extractor
     OR NEW.span_start IS DISTINCT FROM OLD.span_start
     OR NEW.span_end   IS DISTINCT FROM OLD.span_end THEN
    RAISE EXCEPTION
      'analysis.entity_candidate is append-only: insert a new row instead of editing the claim';
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION analysis.extraction_candidate_no_mutate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.entity_text  IS DISTINCT FROM OLD.entity_text
     OR NEW.record_id IS DISTINCT FROM OLD.record_id
     OR NEW.extractor IS DISTINCT FROM OLD.extractor
     OR NEW.candidate_kind IS DISTINCT FROM OLD.candidate_kind
     OR NEW.span_start IS DISTINCT FROM OLD.span_start
     OR NEW.span_end   IS DISTINCT FROM OLD.span_end THEN
    RAISE EXCEPTION USING MESSAGE =
      'analysis.extraction_candidate is append-only: insert a new row instead of '
      'editing the claim (review columns and consumed_by are the mutable surface)';
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION analysis.knowledge_evidence_pointer_hash(pointer jsonb)
 RETURNS bytea
 LANGUAGE sql
 IMMUTABLE STRICT
AS $function$
    SELECT public.digest(
        convert_to(
            jsonb_build_object(
                'matter_id', pointer -> 'matter_id',
                'court_case_id', pointer -> 'court_case_id',
                'partition_key', pointer -> 'partition_key',
                'lane', pointer -> 'lane',
                'normalized_record_id', pointer -> 'normalized_record_id',
                'evidence_hash_id', pointer -> 'evidence_hash_id',
                'source_id', pointer -> 'source_id',
                'sha256', pointer -> 'sha256',
                'conversation_id', pointer -> 'conversation_id',
                'quote', pointer -> 'quote'
            )::text,
            'UTF8'
        ),
        'sha256'
    )
$function$
;
CREATE OR REPLACE FUNCTION analysis.log_task_status()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      IF NEW.status = 'archived' AND COALESCE(NEW.archive_reason,'') = '' THEN
        RAISE EXCEPTION 'archived status requires archive_reason (no silent discard)';
      END IF;
      INSERT INTO analysis.task_event(task_id, from_status, to_status, actor, actor_kind, reason, ts)
      VALUES (NEW.id, OLD.status, NEW.status, COALESCE(current_setting('app.actor', true),'system'),
              COALESCE(current_setting('app.actor_kind', true),'system'), NEW.archive_reason, now());
    END IF; RETURN NEW; END $function$
;
CREATE OR REPLACE FUNCTION analysis.record_graphrag_comparison_join(p_run_id uuid, p_stage_id text, p_stage_version text, p_manifest_id uuid, p_manifest_digest bytea, p_semantica_receipt_id uuid, p_sat_temporal_receipt_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id UUID;
BEGIN
  INSERT INTO analysis.graphrag_comparison_join (
    run_id, stage_id, stage_version, manifest_id, manifest_digest,
    semantica_receipt_id, sat_temporal_receipt_id)
  VALUES (p_run_id, p_stage_id, p_stage_version, p_manifest_id, p_manifest_digest,
          p_semantica_receipt_id, p_sat_temporal_receipt_id)
  ON CONFLICT (run_id, stage_id, stage_version, manifest_id, manifest_digest) DO UPDATE
    SET semantica_receipt_id    = COALESCE(EXCLUDED.semantica_receipt_id,    analysis.graphrag_comparison_join.semantica_receipt_id),
        sat_temporal_receipt_id = COALESCE(EXCLUDED.sat_temporal_receipt_id, analysis.graphrag_comparison_join.sat_temporal_receipt_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$
;
CREATE OR REPLACE FUNCTION analysis.seal_graphrag_manifest(p_manifest_id uuid)
 RETURNS TABLE(manifest_id uuid, membership_digest bytea, member_count integer, sealed_at timestamp with time zone)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_digest BYTEA;
  v_count  INTEGER;
  v_now    TIMESTAMPTZ := now();
BEGIN
  SELECT count(*)::INTEGER,
         digest(coalesce(string_agg(
           m.ordinal::TEXT || ':' || m.source_version_id::TEXT || ':' ||
           m.normalized_record_id::TEXT || ':' || coalesce(m.text_unit_id::TEXT,''),
           '|' ORDER BY m.ordinal), ''), 'sha256')
    INTO v_count, v_digest
    FROM analysis.graphrag_eligibility_manifest_member m
   WHERE m.manifest_id = p_manifest_id;

  UPDATE analysis.graphrag_eligibility_manifest
     SET status = 'sealed', membership_digest = v_digest,
         member_count = v_count, sealed_at = v_now
   WHERE id = p_manifest_id;

  RETURN QUERY SELECT p_manifest_id, v_digest, v_count, v_now;
END $function$
;
CREATE OR REPLACE FUNCTION analysis.set_case_management_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION analysis.snapshot_task()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ BEGIN
    INSERT INTO analysis.task_revision(task_id, snapshot, changed_by, change_note, ts)
    VALUES (OLD.id, to_jsonb(OLD), COALESCE(current_setting('app.actor', true),'unknown'),
            'auto-snapshot before UPDATE', now());
    RETURN NEW; END $function$
;
CREATE OR REPLACE FUNCTION canon.apply_proposal(p_proposal_id uuid, p_decision_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_p        canon.change_proposal%ROWTYPE;
  v_ct       canon.canonical_table%ROWTYPE;
  v_prior    JSONB := '{}'::jsonb;
  v_app_id   UUID;
  v_col      TEXT;
  v_pk_col   TEXT;
  v_pk_val   TEXT;
  v_set_sql  TEXT := '';
  v_tgt      TEXT;
BEGIN
  SELECT * INTO v_p  FROM canon.change_proposal  WHERE id = p_proposal_id FOR UPDATE;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'proposal % not found', p_proposal_id; END IF;
  IF v_p.status NOT IN ('proposed','approved') THEN
    RAISE EXCEPTION 'proposal % is %, not applicable', p_proposal_id, v_p.status;
  END IF;
  SELECT * INTO v_ct FROM canon.canonical_table  WHERE id = v_p.canonical_table_id FOR UPDATE;

  -- STALENESS GUARD: reasoned against a superseded generation -> requeue, never apply
  IF v_p.source_generation <> v_ct.current_generation THEN
    UPDATE canon.change_proposal SET status = 'stale_requeued' WHERE id = p_proposal_id;
    RETURN NULL;
  END IF;

  -- Only 'correct' patches are applied generically here; other kinds record the
  -- ruling + receipt and are executed by their kind-specific worker off the queue.
  IF v_p.proposal_kind = 'correct' THEN
    SELECT key, value #>> '{}' INTO v_pk_col, v_pk_val
      FROM jsonb_each(v_p.target_pk) LIMIT 1;
    -- snapshot prior values of exactly the patched columns
    EXECUTE format('SELECT to_jsonb(t) FROM %I.%I t WHERE %I = $1::uuid',
                   v_ct.table_schema, v_ct.table_name, v_pk_col)
      INTO v_prior USING v_pk_val;
    IF v_prior IS NULL THEN RAISE EXCEPTION 'target row not found for proposal %', p_proposal_id; END IF;
    SELECT jsonb_object_agg(k, v_prior -> k) INTO v_prior
      FROM jsonb_object_keys(v_p.patch) k;
    -- build and run the update
    SELECT string_agg(format('%I = ($1::jsonb ->> %L)::%s', key,
             key,
             (SELECT format_type(a.atttypid, a.atttypmod)
                FROM pg_attribute a
               WHERE a.attrelid = format('%I.%I', v_ct.table_schema, v_ct.table_name)::regclass
                 AND a.attname = key AND a.attnum > 0)), ', ')
      INTO v_set_sql
      FROM jsonb_each(v_p.patch);
    EXECUTE format('UPDATE %I.%I SET %s WHERE %I = $2::uuid',
                   v_ct.table_schema, v_ct.table_name, v_set_sql, v_pk_col)
      USING v_p.patch, v_pk_val;
  END IF;

  UPDATE canon.canonical_table
     SET current_generation = current_generation + 1
   WHERE id = v_ct.id;

  INSERT INTO canon.change_application
      (proposal_id, decision_id, prior_values, applied_patch, generation_before, generation_after)
  VALUES (p_proposal_id, p_decision_id, coalesce(v_prior,'{}'::jsonb), v_p.patch,
          v_ct.current_generation, v_ct.current_generation + 1)
  RETURNING id INTO v_app_id;

  FOREACH v_tgt IN ARRAY v_ct.recompute_targets LOOP
    INSERT INTO canon.recompute_queue
        (application_id, canonical_table_id, target_pk, recompute_target)
    VALUES (v_app_id, v_ct.id, v_p.target_pk, v_tgt);
  END LOOP;

  UPDATE canon.change_proposal SET status = 'applied' WHERE id = p_proposal_id;
  RETURN v_app_id;
END $function$
;
CREATE OR REPLACE FUNCTION canon.route_tier(p_canonical_table_id uuid, p_confidence numeric)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN ct.auto_confirm_min_confidence IS NOT NULL
     AND p_confidence IS NOT NULL
     AND p_confidence >= ct.auto_confirm_min_confidence
    THEN 'auto_adopt'
    ELSE ct.default_tier
  END
  FROM canon.canonical_table ct WHERE ct.id = p_canonical_table_id
$function$
;
CREATE OR REPLACE FUNCTION context.register_raw_format_subtype(p_format_id text)
 RETURNS regclass
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'context'
AS $function$
DECLARE
    v_table_name TEXT;
    v_relation REGCLASS;
    v_relation_kind "char";
    v_raw_record_attnum SMALLINT;
    v_raw_identity_id_attnum SMALLINT;
    v_native_fields_attnum SMALLINT;
    v_native_metadata_attnum SMALLINT;
BEGIN
    IF p_format_id !~ '^[a-z][a-z0-9_]{0,58}$' THEN
        RAISE EXCEPTION 'invalid raw format id %', p_format_id;
    END IF;

    v_table_name := 'raw_' || p_format_id;
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS context.%I (
            raw_record_id UUID PRIMARY KEY
                REFERENCES context.raw_record_identity(id) ON DELETE RESTRICT,
            native_fields JSONB NOT NULL DEFAULT ''{}''::jsonb
                CHECK (jsonb_typeof(native_fields) = ''object''),
            native_metadata JSONB NOT NULL DEFAULT ''{}''::jsonb
                CHECK (jsonb_typeof(native_metadata) = ''object''),
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )',
        v_table_name
    );
    v_relation := to_regclass(format('context.%I', v_table_name));

    SELECT relkind INTO v_relation_kind
    FROM pg_class
    WHERE oid = v_relation;
    IF v_relation_kind IS DISTINCT FROM 'r'::"char" THEN
        RAISE EXCEPTION 'raw subtype % must be an ordinary table, found relation kind %',
            v_relation::TEXT, v_relation_kind;
    END IF;

    SELECT attnum INTO v_raw_identity_id_attnum
    FROM pg_attribute
    WHERE attrelid = 'context.raw_record_identity'::regclass
      AND attname = 'id'
      AND atttypid = 'uuid'::regtype
      AND attnotnull
      AND NOT attisdropped;

    SELECT attnum INTO v_raw_record_attnum
    FROM pg_attribute
    WHERE attrelid = v_relation
      AND attname = 'raw_record_id'
      AND atttypid = 'uuid'::regtype
      AND attnotnull
      AND NOT attisdropped;

    IF v_raw_record_attnum IS NULL OR v_raw_identity_id_attnum IS NULL THEN
        RAISE EXCEPTION 'raw subtype % must have a NOT NULL UUID raw_record_id key column',
            v_relation::TEXT;
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = v_relation
          AND contype = 'p'
          AND conkey = ARRAY[v_raw_record_attnum]::SMALLINT[]
    ) THEN
        RAISE EXCEPTION 'raw subtype % must have raw_record_id as its exact primary key',
            v_relation::TEXT;
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = v_relation
          AND contype = 'f'
          AND confrelid = 'context.raw_record_identity'::regclass
          AND conkey = ARRAY[v_raw_record_attnum]::SMALLINT[]
          AND confkey = ARRAY[v_raw_identity_id_attnum]::SMALLINT[]
          AND confdeltype = 'r'
    ) THEN
        RAISE EXCEPTION 'raw subtype % must have an exact raw_record_id FK to context.raw_record_identity(id) ON DELETE RESTRICT',
            v_relation::TEXT;
    END IF;

    SELECT attnum INTO v_native_fields_attnum
    FROM pg_attribute
    WHERE attrelid = v_relation
      AND attname = 'native_fields'
      AND atttypid = 'jsonb'::regtype
      AND attnotnull
      AND NOT attisdropped;
    SELECT attnum INTO v_native_metadata_attnum
    FROM pg_attribute
    WHERE attrelid = v_relation
      AND attname = 'native_metadata'
      AND atttypid = 'jsonb'::regtype
      AND attnotnull
      AND NOT attisdropped;
    IF v_native_fields_attnum IS NULL OR v_native_metadata_attnum IS NULL THEN
        RAISE EXCEPTION 'raw subtype % must have NOT NULL JSONB native_fields and native_metadata columns',
            v_relation::TEXT;
    END IF;

    INSERT INTO context.raw_format_registry (format_id, subtype_relation)
    VALUES (p_format_id, v_relation)
    ON CONFLICT (format_id) DO NOTHING;
    IF (SELECT subtype_relation FROM context.raw_format_registry WHERE format_id = p_format_id)
       IS DISTINCT FROM v_relation THEN
        RAISE EXCEPTION 'raw format % is already registered to a different subtype relation', p_format_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = v_relation
          AND tgname = 'raw_subtype_append_only'
          AND NOT tgisinternal
    ) THEN
        EXECUTE format(
            'CREATE TRIGGER raw_subtype_append_only
             BEFORE UPDATE OR DELETE ON context.%I
             FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation()',
            v_table_name
        );
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = v_relation
          AND tgname = 'raw_subtype_open_generation_gate'
          AND NOT tgisinternal
    ) THEN
        EXECUTE format(
            'CREATE TRIGGER raw_subtype_open_generation_gate
             BEFORE INSERT ON context.%I
             FOR EACH ROW EXECUTE FUNCTION context.guard_raw_subtype_insert()',
            v_table_name
        );
    END IF;
    RETURN v_relation;
END;
$function$
;
CREATE OR REPLACE FUNCTION context.seal_hash_manifest_from_receipt()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'context'
AS $function$
BEGIN
    IF NEW.hash_kind IN ('context_raw_generation_fingerprint', 'normalized_generation_manifest_digest') THEN
        UPDATE context.hash_manifest SET status = 'sealed',
            member_count = (SELECT count(*) FROM context.hash_manifest_member WHERE hash_manifest_id = NEW.hash_manifest_id),
            sealed_hash_receipt_id = NEW.id, sealed_at = NEW.computed_at
        WHERE id = NEW.hash_manifest_id;
    END IF;
    RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION evidence.chain_custody_event()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.source_id::text, 0));
    SELECT ce.event_digest INTO NEW.prev_event_digest
      FROM evidence.custody_event ce
     WHERE ce.source_id = NEW.source_id ORDER BY ce.seq DESC LIMIT 1;
    NEW.event_digest := digest(convert_to(
        coalesce(NEW.source_id::text,'') || '|' || coalesce(NEW.file_node_id::text,'') || '|' ||
        coalesce(NEW.evidence_hash_id::text,'') || '|' || NEW.event_type || '|' || NEW.actor || '|' ||
        to_char(NEW.occurred_at,'YYYY-MM-DD"T"HH24:MI:SS.US TZH:TZM') || '|' ||
        coalesce(NEW.detail::text,'{}') || '|' || coalesce(encode(NEW.prev_event_digest,'hex'),''),
      'UTF8'), 'sha256');
    RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION evidence.raw_no_mutate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- INERT UNTIL LIVE (owner, 2026-08-01: "append only only starts once we are
  -- actually live"). During build-out the schema and parsers churn, and a hard
  -- immutability rule would force a DB rebuild for every iteration. The trigger is
  -- installed now so going live is a one-line switch rather than a migration:
  --
  --   ALTER DATABASE <db> SET app.evidence_live = 'on';
  --
  -- Until then raw behaves like an ordinary table.
  IF current_setting('app.evidence_live', true) IS DISTINCT FROM 'on' THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  -- One exception: marking a row superseded. That is the ONLY legal mutation, and it
  -- adds a forward pointer rather than changing anything the row asserts. Everything
  -- the row claimed about the source stays exactly as written.
  IF TG_OP = 'UPDATE'
     AND OLD.superseded_by IS NULL
     AND NEW.superseded_by IS NOT NULL
     AND NEW.raw            IS NOT DISTINCT FROM OLD.raw
     AND NEW.raw_text       IS NOT DISTINCT FROM OLD.raw_text
     AND NEW.content_hash   IS NOT DISTINCT FROM OLD.content_hash
     AND NEW.source_id      IS NOT DISTINCT FROM OLD.source_id
     AND NEW.device_id      IS NOT DISTINCT FROM OLD.device_id
     AND NEW.medium         IS NOT DISTINCT FROM OLD.medium
     AND NEW.record_index   IS NOT DISTINCT FROM OLD.record_index
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION USING MESSAGE =
    'evidence.' || TG_TABLE_NAME ||
    ' is append-only: raw source records are never updated or deleted '
    '(the only permitted change is setting superseded_by on a live row)';
END;
$function$
;
CREATE OR REPLACE FUNCTION ops.reset_test_data(p_confirm text)
 RETURNS TABLE(truncated_schema text, tables_truncated integer)
 LANGUAGE plpgsql
AS $function$
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
END $function$
;
CREATE OR REPLACE FUNCTION public.change_log_chain()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE prev bytea;
BEGIN
  SELECT row_hash INTO prev FROM public.change_log ORDER BY seq DESC LIMIT 1;
  NEW.prev_change_hash := prev;
  NEW.row_hash := digest(
      coalesce(NEW.table_name,'') || '|' || coalesce(NEW.record_id::text,'') || '|' ||
      coalesce(NEW.field_name,'') || '|' || NEW.action || '|' ||
      coalesce(NEW.previous_value,'') || '|' || coalesce(NEW.new_value,'') || '|' ||
      NEW.actor || '|' || NEW.change_origin || '|' || coalesce(encode(prev,'hex'),''), 'sha256');
  RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION public.require_consolidation_verified_proof_v0049()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_proof_kind TEXT;
    v_result TEXT;
    v_details JSONB;
BEGIN
    IF NEW.checkpoint_status <> 'verified' THEN
        RETURN NEW;
    END IF;

    SELECT receipt.proof_kind, receipt.result, receipt.details
    INTO v_proof_kind, v_result, v_details
    FROM public.platform_consolidation_proof_receipt AS receipt
    WHERE receipt.id = NEW.verified_receipt_id
      AND receipt.checkpoint_id = NEW.id
      AND NOT EXISTS (
          SELECT 1
          FROM public.platform_consolidation_proof_receipt AS successor
          WHERE successor.supersedes_receipt_id = receipt.id
      );

    IF NOT FOUND OR v_result <> 'pass' OR v_proof_kind <> NEW.required_proof_kind THEN
        RAISE EXCEPTION
            'verified consolidation checkpoint % requires its exact unsuperseded passing % receipt',
            NEW.id, NEW.required_proof_kind;
    END IF;
    IF NOT (v_details ?& ARRAY[
        'phase_key', 'relation_key', 'proof_kind', 'source_snapshot_id',
        'target_snapshot_id', 'source_snapshot_sha256', 'target_snapshot_sha256',
        'manifest_sha256', 'repository_revision'
    ])
       OR v_details->>'phase_key' IS DISTINCT FROM NEW.phase_key
       OR v_details->>'relation_key' IS DISTINCT FROM NEW.relation_key
       OR v_details->>'proof_kind' IS DISTINCT FROM NEW.required_proof_kind
       OR v_details->>'source_snapshot_id' IS DISTINCT FROM NEW.source_snapshot_id
       OR v_details->>'target_snapshot_id' IS DISTINCT FROM NEW.target_snapshot_id
       OR lower(v_details->>'source_snapshot_sha256') IS DISTINCT FROM encode(NEW.source_snapshot_sha256, 'hex')
       OR lower(v_details->>'target_snapshot_sha256') IS DISTINCT FROM encode(NEW.target_snapshot_sha256, 'hex')
       OR lower(v_details->>'manifest_sha256') IS DISTINCT FROM encode(NEW.manifest_sha256, 'hex')
       OR v_details->>'repository_revision' IS DISTINCT FROM NEW.repository_revision THEN
        RAISE EXCEPTION 'verified consolidation checkpoint % has an unbound proof receipt', NEW.id;
    END IF;
    IF NEW.required_proof_kind IN ('caller_inventory', 'zero_active_sessions')
       AND (
           NOT (v_details ?& ARRAY[
               'fence_attestation_id', 'fence_attestation_sha256', 'fence_established_at',
               'fence_valid_until'
           ])
           OR v_details->>'fence_attestation_id' IS DISTINCT FROM NEW.fence_attestation_id
           OR lower(v_details->>'fence_attestation_sha256')
              IS DISTINCT FROM encode(NEW.fence_attestation_sha256, 'hex')
           OR (v_details->>'fence_established_at')::TIMESTAMPTZ
              IS DISTINCT FROM NEW.fence_established_at
           OR (v_details->>'fence_valid_until')::TIMESTAMPTZ IS DISTINCT FROM NEW.fence_valid_until
       ) THEN
        RAISE EXCEPTION 'verified caller checkpoint % requires its exact bound fence attestation', NEW.id;
    END IF;
    BEGIN
        INSERT INTO public.platform_consolidation_receipt_claim (
            receipt_id, claim_kind, checkpoint_id
        ) VALUES (NEW.verified_receipt_id, 'verified', NEW.id);
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION
                'receipt % already has an incompatible immutable claim', NEW.verified_receipt_id
                USING ERRCODE = '23514';
    END;
    RETURN NEW;
END
$function$
;
CREATE OR REPLACE FUNCTION timeline.generation_supersede_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.status <> 'sealed' THEN
        RAISE EXCEPTION 'timeline_projection_generation %: already %, no further UPDATE allowed', OLD.id, OLD.status;
    END IF;
    IF NEW.status NOT IN ('superseded', 'quarantined') THEN
        RAISE EXCEPTION 'timeline_projection_generation: UPDATE must set status to superseded or quarantined';
    END IF;
    IF to_jsonb(NEW) - 'status' - 'superseded_by' IS DISTINCT FROM to_jsonb(OLD) - 'status' - 'superseded_by' THEN
        RAISE EXCEPTION 'timeline_projection_generation: only status/superseded_by may change';
    END IF;
    RETURN NEW;
END
$function$
;
CREATE OR REPLACE FUNCTION working.check_context_thread_realization_deferred()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'working'
AS $function$
DECLARE
    v_assertion_id UUID;
    v_party TEXT;
BEGIN
    IF TG_TABLE_NAME LIKE '%_realization_assertion' THEN
        v_assertion_id := NEW.id;
    ELSE
        v_assertion_id := NEW.realization_assertion_id;
    END IF;
    IF TG_TABLE_NAME LIKE 'first_party_%' THEN
        v_party := 'first_party';
    ELSE
        v_party := 'third_party';
    END IF;
    PERFORM working.validate_context_thread_realization_sources(v_assertion_id, v_party);
    RETURN NULL;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.check_context_thread_version_deferred()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'working'
AS $function$
DECLARE
    v_version_id UUID;
BEGIN
    IF TG_TABLE_NAME LIKE '%_thread_version' THEN
        v_version_id := NEW.id;
    ELSE
        v_version_id := NEW.thread_version_id;
    END IF;
    IF TG_TABLE_NAME LIKE 'first_party_%' THEN
        PERFORM working.validate_first_party_context_thread_version(v_version_id);
    ELSE
        PERFORM working.validate_third_party_context_thread_version(v_version_id);
    END IF;
    RETURN NULL;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.check_source_range_locator_subject_deferred()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'working'
AS $function$
BEGIN
    PERFORM working.validate_source_range_locator_subject(
        CASE WHEN TG_TABLE_NAME = 'source_range_locator' THEN NEW.id
             ELSE NEW.source_range_locator_id END
    );
    RETURN NULL;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.emit_chat_row_event()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE target_table TEXT := TG_TABLE_NAME || '_event';
BEGIN
    EXECUTE format('INSERT INTO working.%I (operation, row_data) VALUES ($1, $2)', target_table)
        USING TG_OP, to_jsonb(NEW);
    PERFORM pg_notify('working_chat_changed', TG_TABLE_NAME);
    RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.enqueue_evidence_vector_projection(p_record_ids uuid[], p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE queued INTEGER;
BEGIN
  IF p_reason IS NULL OR length(trim(p_reason))=0 THEN
    RAISE EXCEPTION 'VECTOR_PROJECTION_REASON_REQUIRED';
  END IF;
  INSERT INTO working.evidence_vector_projection_job(chunk_id, reason)
  SELECT chunk.id, p_reason
    FROM working.normalized_record_chunk chunk
   WHERE chunk.normalized_record_id=ANY(p_record_ids)
  ON CONFLICT (chunk_id, projection_version) DO UPDATE
    SET reason=EXCLUDED.reason, status='pending', generation=working.evidence_vector_projection_job.generation+1,
        next_attempt_at=now(),
        locked_at=NULL, locked_by=NULL, completed_at=NULL, updated_at=now();
  GET DIAGNOSTICS queued = ROW_COUNT;
  RETURN queued;
END $function$
;
CREATE OR REPLACE FUNCTION working.entity_candidate_no_mutate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.entity_text  IS DISTINCT FROM OLD.entity_text
     OR NEW.record_id IS DISTINCT FROM OLD.record_id
     OR NEW.extractor IS DISTINCT FROM OLD.extractor
     OR NEW.span_start IS DISTINCT FROM OLD.span_start
     OR NEW.span_end   IS DISTINCT FROM OLD.span_end THEN
    RAISE EXCEPTION
      'analysis.entity_candidate is append-only: insert a new row instead of editing the claim';
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.extraction_candidate_no_mutate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.entity_text  IS DISTINCT FROM OLD.entity_text
     OR NEW.record_id IS DISTINCT FROM OLD.record_id
     OR NEW.extractor IS DISTINCT FROM OLD.extractor
     OR NEW.candidate_kind IS DISTINCT FROM OLD.candidate_kind
     OR NEW.span_start IS DISTINCT FROM OLD.span_start
     OR NEW.span_end   IS DISTINCT FROM OLD.span_end THEN
    RAISE EXCEPTION USING MESSAGE =
      'analysis.extraction_candidate is append-only: insert a new row instead of '
      'editing the claim (review columns and consumed_by are the mutable surface)';
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.horizon_record_visible(p_record_id uuid, p_horizon timestamp with time zone, p_base_version text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
  SELECT COALESCE((
    SELECT CASE
      WHEN source_time IS NULL THEN false
      WHEN p_horizon IS NULL THEN true
      ELSE source_time<=p_horizon
    END
    FROM (
      SELECT CASE
        WHEN p_base_version IS NOT NULL
             AND rvf.base_version=p_base_version
             AND rvf.base_version<>'__legacy_untrusted__'
          THEN rvf.visible_from
        ELSE working.source_available_from(nr.id)
      END AS source_time
      FROM working.normalized_record nr
      LEFT JOIN working.record_visible_from rvf ON rvf.record_id=nr.id
      WHERE nr.id=p_record_id
    ) q
  ), false);
$function$
;
CREATE OR REPLACE FUNCTION working.horizon_visible(row_case_id text, row_knowledge_time timestamp with time zone, row_disclosure text, row_actor text, p_case_id text, p_horizon timestamp with time zone, p_actor text DEFAULT 'owner'::text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT row_case_id = p_case_id
       AND (
            p_horizon IS NULL                       -- hindsight: no cutoff
            OR (row_knowledge_time IS NOT NULL
                AND row_knowledge_time <= p_horizon
                AND row_actor = p_actor
                AND row_disclosure <> 'hindsight')  -- never leaks backwards
       );
$function$
;
CREATE OR REPLACE FUNCTION working.insert_initial_content_chunk_context()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'working'
AS $function$
BEGIN
    INSERT INTO working.content_chunk_classification_decision (
        chunk_id, decision_version, lane, decision_kind, review_state,
        classifier_id, classifier_version, confidence, rationale
    ) VALUES (
        NEW.id, 1, 'context', 'initial_context', 'system_initial',
        'context-first-ingest-policy', '0047', 1.0,
        'All intake begins in context; legal/personal_history require reviewed classification.'
    );
    RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.promotion_revoke_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'working.promotion is append-only: DELETE blocked (revoke instead)';
    END IF;
    -- The ONLY legal update: first-time revocation. Everything else identical.
    IF OLD.revoked_at IS NOT NULL THEN
        RAISE EXCEPTION 'working.promotion: row already revoked; further updates blocked';
    END IF;
    IF NEW.revoked_at IS NULL THEN
        RAISE EXCEPTION 'working.promotion: UPDATE must set revoked_at (revocation is the only legal update)';
    END IF;
    IF to_jsonb(NEW) - 'revoked_at' - 'revoked_reason'
       IS DISTINCT FROM to_jsonb(OLD) - 'revoked_at' - 'revoked_reason' THEN
        RAISE EXCEPTION 'working.promotion: only revoked_at/revoked_reason may change on revocation';
    END IF;
    RETURN NEW;
END
$function$
;
CREATE OR REPLACE FUNCTION working.queue_vector_chunk_on_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM working.enqueue_evidence_vector_projection(
    ARRAY[NEW.normalized_record_id], 'normalized_record_chunk_insert');
  RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION working.queue_vector_route_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM working.enqueue_evidence_vector_projection(
    ARRAY[COALESCE(NEW.normalized_record_id,OLD.normalized_record_id)],
    'message_projection_authority_change');
  RETURN COALESCE(NEW,OLD);
END $function$
;
CREATE OR REPLACE FUNCTION working.queue_vector_third_party_authority_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE conversation UUID;
BEGIN
  conversation := COALESCE(NEW.conversation_id,OLD.conversation_id);
  PERFORM working.enqueue_evidence_vector_projection(
    ARRAY(SELECT message.normalized_record_id
            FROM working.third_party_message message
           WHERE message.conversation_id=conversation),
    'third_party_authority_change');
  RETURN COALESCE(NEW,OLD);
END $function$
;
CREATE OR REPLACE FUNCTION working.reject_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ BEGIN
    RAISE EXCEPTION 'append-only table %.% — % not allowed', TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP; END $function$
;
CREATE OR REPLACE FUNCTION working.source_available_from(p_record_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
SELECT CASE
  WHEN nr.record_type <> 'message' THEN nr.occurred_at
  WHEN r.decision_state <> 'approved' OR r.normalized_record_id IS NULL THEN NULL
  WHEN r.projection_kind='first_party' THEN nr.occurred_at
  WHEN r.projection_kind='acquired_third_party' THEN (
    SELECT MIN(a.acquired_at)
      FROM working.third_party_message tm
      JOIN working.third_party_conversation_acquisition ca ON ca.conversation_id=tm.conversation_id
      JOIN evidence.acquisition a ON a.id=ca.acquisition_id
     WHERE tm.normalized_record_id=nr.id
       AND ca.approval_state='approved'
       AND a.acquired_at IS NOT NULL)
END
FROM working.normalized_record nr
LEFT JOIN working.message_projection_route r ON r.normalized_record_id=nr.id
WHERE nr.id=p_record_id;
$function$
;
CREATE OR REPLACE FUNCTION working.validate_context_thread_realization_sources(p_assertion_id uuid, p_party text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'working'
AS $function$
DECLARE
    v_required_count BIGINT;
    v_missing_exact_count BIGINT;
    v_missing_anchor_count BIGINT;
    v_available TIMESTAMPTZ;
    v_recorded TIMESTAMPTZ;
BEGIN
    IF p_party = 'first_party' THEN
        WITH required_member AS (
            SELECT 'message'::TEXT AS member_kind, message.message_id AS member_id,
                   message.source_available_from
            FROM working.first_party_context_thread_realization_message link
            JOIN working.first_party_context_thread_message message
              ON message.thread_version_id = link.thread_version_id
             AND message.message_id = link.message_id
            WHERE link.realization_assertion_id = p_assertion_id AND link.required_for_realization
            UNION ALL
            SELECT 'source', source.id, source.source_available_from
            FROM working.first_party_context_thread_realization_source link
            JOIN working.first_party_context_thread_source source
              ON source.id = link.thread_source_id
            WHERE link.realization_assertion_id = p_assertion_id AND link.required_for_realization
        )
        SELECT count(*), count(*) FILTER (WHERE source_available_from IS NULL),
               CASE WHEN bool_or(source_available_from IS NULL) THEN NULL
                    ELSE max(source_available_from) END
          INTO v_required_count, v_missing_exact_count, v_available
        FROM required_member;
        SELECT count(*) INTO v_missing_anchor_count
        FROM (
            SELECT message.message_id
            FROM working.first_party_context_thread_realization_message link
            JOIN working.first_party_context_thread_message message
              ON message.thread_version_id = link.thread_version_id
             AND message.message_id = link.message_id
            WHERE link.realization_assertion_id = p_assertion_id
              AND link.required_for_realization AND message.source_available_from IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM context.first_party_thread_message_relative_time_anchor anchor_link
                  JOIN context.relative_time_anchor anchor ON anchor.id = anchor_link.anchor_id
                  WHERE anchor_link.thread_version_id = message.thread_version_id
                    AND anchor_link.message_id = message.message_id
                    AND anchor_link.link_role = 'primary_fallback'
                    AND anchor.review_state IN ('proposed', 'approved')
              )
            UNION ALL
            SELECT source.id
            FROM working.first_party_context_thread_realization_source link
            JOIN working.first_party_context_thread_source source ON source.id = link.thread_source_id
            WHERE link.realization_assertion_id = p_assertion_id
              AND link.required_for_realization AND source.source_available_from IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM context.first_party_thread_source_relative_time_anchor anchor_link
                  JOIN context.relative_time_anchor anchor ON anchor.id = anchor_link.anchor_id
                  WHERE anchor_link.thread_source_id = source.id
                    AND anchor_link.link_role = 'primary_fallback'
                    AND anchor.review_state IN ('proposed', 'approved')
              )
        ) missing_anchor;
        SELECT required_source_available_from INTO v_recorded
        FROM working.first_party_context_thread_realization_assertion WHERE id = p_assertion_id;
    ELSIF p_party = 'third_party' THEN
        WITH required_member AS (
            SELECT 'message'::TEXT AS member_kind, message.message_id AS member_id,
                   message.source_available_from
            FROM working.third_party_context_thread_realization_message link
            JOIN working.third_party_context_thread_message message
              ON message.thread_version_id = link.thread_version_id
             AND message.message_id = link.message_id
            WHERE link.realization_assertion_id = p_assertion_id AND link.required_for_realization
            UNION ALL
            SELECT 'source', source.id, source.source_available_from
            FROM working.third_party_context_thread_realization_source link
            JOIN working.third_party_context_thread_source source ON source.id = link.thread_source_id
            WHERE link.realization_assertion_id = p_assertion_id AND link.required_for_realization
        )
        SELECT count(*), count(*) FILTER (WHERE source_available_from IS NULL),
               CASE WHEN bool_or(source_available_from IS NULL) THEN NULL
                    ELSE max(source_available_from) END
          INTO v_required_count, v_missing_exact_count, v_available
        FROM required_member;
        SELECT count(*) INTO v_missing_anchor_count
        FROM (
            SELECT message.message_id
            FROM working.third_party_context_thread_realization_message link
            JOIN working.third_party_context_thread_message message
              ON message.thread_version_id = link.thread_version_id
             AND message.message_id = link.message_id
            WHERE link.realization_assertion_id = p_assertion_id
              AND link.required_for_realization AND message.source_available_from IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM context.third_party_thread_message_relative_time_anchor anchor_link
                  JOIN context.relative_time_anchor anchor ON anchor.id = anchor_link.anchor_id
                  WHERE anchor_link.thread_version_id = message.thread_version_id
                    AND anchor_link.message_id = message.message_id
                    AND anchor_link.link_role = 'primary_fallback'
                    AND anchor.review_state IN ('proposed', 'approved')
              )
            UNION ALL
            SELECT source.id
            FROM working.third_party_context_thread_realization_source link
            JOIN working.third_party_context_thread_source source ON source.id = link.thread_source_id
            WHERE link.realization_assertion_id = p_assertion_id
              AND link.required_for_realization AND source.source_available_from IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM context.third_party_thread_source_relative_time_anchor anchor_link
                  JOIN context.relative_time_anchor anchor ON anchor.id = anchor_link.anchor_id
                  WHERE anchor_link.thread_source_id = source.id
                    AND anchor_link.link_role = 'primary_fallback'
                    AND anchor.review_state IN ('proposed', 'approved')
              )
        ) missing_anchor;
        SELECT required_source_available_from INTO v_recorded
        FROM working.third_party_context_thread_realization_assertion WHERE id = p_assertion_id;
    ELSE
        RAISE EXCEPTION 'unknown context-thread party %', p_party;
    END IF;
    IF v_required_count = 0 OR v_missing_anchor_count <> 0
       OR v_recorded IS DISTINCT FROM v_available
       OR (v_missing_exact_count > 0 AND v_recorded IS NOT NULL) THEN
        RAISE EXCEPTION 'realization assertion availability must equal the greatest required source availability';
    END IF;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.validate_first_party_context_thread_version(p_version_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'working', 'context'
AS $function$
DECLARE
    v_version working.first_party_context_thread_version%ROWTYPE;
    v_message_count BIGINT;
    v_first TIMESTAMPTZ;
    v_last TIMESTAMPTZ;
    v_required_source_count BIGINT;
    v_missing_exact_count BIGINT;
    v_missing_anchor_count BIGINT;
    v_available TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_version FROM working.first_party_context_thread_version WHERE id = p_version_id;
    SELECT count(*), min(occurred_at), max(occurred_at)
      INTO v_message_count, v_first, v_last
    FROM working.first_party_context_thread_message WHERE thread_version_id = p_version_id;
    IF v_message_count = 0 OR (v_version.first_occurred_at, v_version.last_occurred_at)
       IS DISTINCT FROM (v_first, v_last) THEN
        RAISE EXCEPTION 'first-party thread bounds must equal its message occurred_at bounds';
    END IF;
    WITH required_member AS (
        SELECT 'message'::TEXT AS member_kind, message_id AS member_id, source_available_from
        FROM working.first_party_context_thread_message
        WHERE thread_version_id = p_version_id AND required_for_horizon
        UNION ALL
        SELECT 'source', id, source_available_from
        FROM working.first_party_context_thread_source
        WHERE thread_version_id = p_version_id AND required_for_horizon
    )
    SELECT count(*), count(*) FILTER (WHERE source_available_from IS NULL),
           CASE WHEN bool_or(source_available_from IS NULL) THEN NULL
                ELSE max(source_available_from) END
      INTO v_required_source_count, v_missing_exact_count, v_available
    FROM required_member;
    SELECT count(*) INTO v_missing_anchor_count
    FROM (
        SELECT membership.message_id
        FROM working.first_party_context_thread_message membership
        WHERE membership.thread_version_id = p_version_id
          AND membership.required_for_horizon
          AND membership.source_available_from IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM context.first_party_thread_message_relative_time_anchor link
              JOIN context.relative_time_anchor anchor ON anchor.id = link.anchor_id
              WHERE link.thread_version_id = membership.thread_version_id
                AND link.message_id = membership.message_id
                AND link.link_role = 'primary_fallback'
                AND anchor.review_state IN ('proposed', 'approved')
          )
        UNION ALL
        SELECT source.id
        FROM working.first_party_context_thread_source source
        WHERE source.thread_version_id = p_version_id
          AND source.required_for_horizon
          AND source.source_available_from IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM context.first_party_thread_source_relative_time_anchor link
              JOIN context.relative_time_anchor anchor ON anchor.id = link.anchor_id
              WHERE link.thread_source_id = source.id
                AND link.link_role = 'primary_fallback'
                AND anchor.review_state IN ('proposed', 'approved')
          )
    ) missing_anchor;
    IF v_required_source_count = 0 OR v_missing_anchor_count <> 0
       OR v_version.knowledge_available_from IS DISTINCT FROM v_available THEN
        RAISE EXCEPTION 'first-party knowledge availability must be the greatest required occurred_at availability';
    END IF;
    IF v_missing_exact_count > 0 AND v_version.knowledge_available_from IS NOT NULL THEN
        RAISE EXCEPTION 'first-party required NULL clocks prohibit an exact thread horizon';
    END IF;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.validate_message_projection()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE owner_count INTEGER;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('working.message_projection'));
  IF EXISTS (SELECT 1 FROM working.message_projection_route r
             JOIN working.normalized_record nr ON nr.id=r.normalized_record_id
             WHERE r.decision_state='approved' AND nr.record_type<>'message') THEN
    RAISE EXCEPTION 'MESSAGE_ROUTE_REQUIRES_MESSAGE_RECORD';
  END IF;
  IF EXISTS (
    SELECT 1 FROM working.message_projection_route r
    WHERE r.decision_state='approved' AND r.projection_kind='first_party'
      AND ((SELECT count(*) FROM working.message m WHERE m.derived_from_record_id=r.normalized_record_id)<>1
        OR EXISTS (SELECT 1 FROM working.third_party_message tm WHERE tm.normalized_record_id=r.normalized_record_id))) THEN
    RAISE EXCEPTION 'FIRST_PARTY_PROJECTION_CARDINALITY';
  END IF;
  IF EXISTS (SELECT 1 FROM working.message_projection_route
             WHERE decision_state='approved' AND projection_kind='acquired_third_party') THEN
    SELECT count(*) INTO owner_count FROM registry.person WHERE role_in_case='user';
    IF owner_count<>1 THEN RAISE EXCEPTION 'OWNER_IDENTITY_NOT_CONFIGURED'; END IF;
  END IF;
  IF EXISTS (
    SELECT 1 FROM working.message_projection_route r
    JOIN working.normalized_record nr ON nr.id=r.normalized_record_id
    LEFT JOIN working.third_party_message tm ON tm.normalized_record_id=r.normalized_record_id
    LEFT JOIN working.third_party_conversation tc ON tc.id=tm.conversation_id
    WHERE r.decision_state='approved' AND r.projection_kind='acquired_third_party'
      AND (tm.id IS NULL OR tc.review_status<>'approved' OR tc.case_id<>nr.case_id
        OR tc.source_artifact_id<>nr.artifact_id
        OR tm.occurred_at IS DISTINCT FROM nr.occurred_at
        OR tm.sender_raw IS NULL OR length(trim(tm.sender_raw))=0
        OR tm.sender_entity_id IS NULL
        OR (nr.attrs ? 'source_party_review_required'
            AND r.basis->>'source_party_review_resolved' IS DISTINCT FROM 'true')
        OR EXISTS (SELECT 1 FROM working.message m WHERE m.derived_from_record_id=r.normalized_record_id)
        OR (SELECT count(*) FROM working.third_party_message_participant p
            WHERE p.message_id=tm.id AND p.role='from')<>1
        OR NOT EXISTS (SELECT 1 FROM working.third_party_message_participant p
                       WHERE p.message_id=tm.id AND p.role IN ('to','cc','bcc','group'))
        OR EXISTS (SELECT 1 FROM working.third_party_message_participant p
                   WHERE p.message_id=tm.id AND p.entity_id IS NULL)
        OR NOT EXISTS (SELECT 1 FROM working.third_party_message_participant p
                       WHERE p.message_id=tm.id AND p.role='from' AND p.entity_id=tm.sender_entity_id)
        OR EXISTS (SELECT 1 FROM working.third_party_message_participant p
                   JOIN registry.person wp ON wp.id=p.entity_id
                   WHERE p.message_id=tm.id AND wp.role_in_case='user')
        OR NOT EXISTS (SELECT 1 FROM working.third_party_conversation_acquisition ca
                       JOIN evidence.acquisition a ON a.id=ca.acquisition_id
                       WHERE ca.conversation_id=tm.conversation_id
                         AND ca.approval_state='approved' AND a.acquired_at IS NOT NULL
                         AND a.asserted_by='human'))) THEN
    RAISE EXCEPTION 'ACQUIRED_THIRD_PARTY_PROJECTION_INVALID';
  END IF;
  RETURN NULL;
END $function$
;
CREATE OR REPLACE FUNCTION working.validate_realization_links()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1 FROM working.realization_event_record rer
    JOIN working.realization_event re ON re.id=rer.realization_event_id
    JOIN working.normalized_record nr ON nr.id=rer.normalized_record_id
    WHERE rer.case_id<>re.case_id OR rer.case_id<>nr.case_id) THEN
    RAISE EXCEPTION 'REALIZATION_LINK_CASE_MISMATCH';
  END IF;
  IF EXISTS (
    SELECT 1 FROM working.realization_event re
    WHERE re.approval_state='approved' AND re.trigger_record_id IS NULL
      AND NOT EXISTS (SELECT 1 FROM working.realization_event_record rer
                      WHERE rer.realization_event_id=re.id)) THEN
    RAISE EXCEPTION 'APPROVED_REALIZATION_REQUIRES_EVIDENCE_LINK';
  END IF;
  RETURN NULL;
END $function$
;
CREATE OR REPLACE FUNCTION working.validate_source_range_locator_subject(p_locator_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'context'
AS $function$
DECLARE
    v_subject_count BIGINT;
BEGIN
    SELECT (SELECT count(*) FROM context.source_object_range_locator WHERE source_range_locator_id = p_locator_id)
         + (SELECT count(*) FROM context.raw_record_range_locator WHERE source_range_locator_id = p_locator_id)
         + (SELECT count(*) FROM context.normalized_record_range_locator WHERE source_range_locator_id = p_locator_id)
      INTO v_subject_count;
    IF v_subject_count <> 1 THEN
        RAISE EXCEPTION 'source range locator requires exactly one typed subject link';
    END IF;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.validate_third_party_context_thread_version(p_version_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'working', 'context'
AS $function$
DECLARE
    v_version working.third_party_context_thread_version%ROWTYPE;
    v_message_count BIGINT;
    v_first TIMESTAMPTZ;
    v_last TIMESTAMPTZ;
    v_required_source_count BIGINT;
    v_missing_exact_count BIGINT;
    v_missing_anchor_count BIGINT;
    v_available TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_version FROM working.third_party_context_thread_version WHERE id = p_version_id;
    SELECT count(*), min(occurred_at), max(occurred_at)
      INTO v_message_count, v_first, v_last
    FROM working.third_party_context_thread_message WHERE thread_version_id = p_version_id;
    IF v_message_count = 0 OR (v_version.first_occurred_at, v_version.last_occurred_at)
       IS DISTINCT FROM (v_first, v_last) THEN
        RAISE EXCEPTION 'third-party thread bounds must equal its message occurred_at bounds';
    END IF;
    WITH required_member AS (
        SELECT 'message'::TEXT AS member_kind, message_id AS member_id, source_available_from
        FROM working.third_party_context_thread_message
        WHERE thread_version_id = p_version_id AND required_for_horizon
        UNION ALL
        SELECT 'source', id, source_available_from
        FROM working.third_party_context_thread_source
        WHERE thread_version_id = p_version_id AND required_for_horizon
    )
    SELECT count(*), count(*) FILTER (WHERE source_available_from IS NULL),
           CASE WHEN bool_or(source_available_from IS NULL) THEN NULL
                ELSE max(source_available_from) END
      INTO v_required_source_count, v_missing_exact_count, v_available
    FROM required_member;
    SELECT count(*) INTO v_missing_anchor_count
    FROM (
        SELECT membership.message_id
        FROM working.third_party_context_thread_message membership
        WHERE membership.thread_version_id = p_version_id
          AND membership.required_for_horizon
          AND membership.source_available_from IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM context.third_party_thread_message_relative_time_anchor link
              JOIN context.relative_time_anchor anchor ON anchor.id = link.anchor_id
              WHERE link.thread_version_id = membership.thread_version_id
                AND link.message_id = membership.message_id
                AND link.link_role = 'primary_fallback'
                AND anchor.review_state IN ('proposed', 'approved')
          )
        UNION ALL
        SELECT source.id
        FROM working.third_party_context_thread_source source
        WHERE source.thread_version_id = p_version_id
          AND source.required_for_horizon
          AND source.source_available_from IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM context.third_party_thread_source_relative_time_anchor link
              JOIN context.relative_time_anchor anchor ON anchor.id = link.anchor_id
              WHERE link.thread_source_id = source.id
                AND link.link_role = 'primary_fallback'
                AND anchor.review_state IN ('proposed', 'approved')
          )
    ) missing_anchor;
    IF v_required_source_count = 0 OR v_missing_anchor_count <> 0
       OR v_version.knowledge_available_from IS DISTINCT FROM v_available THEN
        RAISE EXCEPTION 'third-party knowledge availability must be the greatest required custody-backed availability';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM working.third_party_context_thread_source source
        WHERE source.thread_version_id = p_version_id
          AND NOT EXISTS (
              SELECT 1
              FROM working.third_party_context_thread_message membership
              JOIN working.third_party_message message ON message.id = membership.message_id
              WHERE membership.thread_version_id = p_version_id
                AND message.conversation_id = source.represented_conversation_id
          )
    ) THEN
        RAISE EXCEPTION 'third-party source represented conversation must belong to the same thread version';
    END IF;
    IF v_missing_exact_count > 0 AND v_version.knowledge_available_from IS NOT NULL THEN
        RAISE EXCEPTION 'third-party required NULL clocks prohibit an exact thread horizon';
    END IF;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.visible_from(p_record_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
  SELECT working.source_available_from(p_record_id);
$function$
;

-- ============ views ============
CREATE OR REPLACE VIEW analysis.vw_court_export AS
 SELECT id,
    case_id,
    exhibit_number,
    title,
    description,
    quote,
    context,
    evidence_type,
    evidence_date,
    date_precision,
    assertion_type,
    confidence,
    confidence_tier,
    is_authenticated,
    authentication_method,
    chain_of_custody,
    sensitivity_tier,
    redaction_status,
    source_id,
    file_node_id,
    evidence_hash_id,
    reviewed_by,
    reviewed_at
   FROM evidence.evidence_item ei
  WHERE safe_for_legal_use = true AND review_status = 'approved'::review_state AND (confidence_tier = ANY (ARRAY['high'::text, 'medium'::text])) AND is_hypothesis = false AND is_authenticated = true AND redaction_status <> 'required'::text AND sensitivity_tier <> 'sealed'::sensitivity_tier;
CREATE OR REPLACE VIEW analysis.vw_human_label_long AS
 SELECT conversation_key,
    seq,
    occurred_at,
    who,
    message_text,
    unnest(labels) AS label,
    is_clean,
    severity,
    notes
   FROM analysis.human_label
  WHERE cardinality(labels) > 0;
CREATE OR REPLACE VIEW analysis.vw_labeling_progress AS
 SELECT count(*) AS total_messages,
    count(*) FILTER (WHERE cardinality(labels) > 0 OR is_clean) AS labeled,
    count(*) FILTER (WHERE cardinality(labels) > 0) AS labeled_with_behavior,
    count(*) FILTER (WHERE is_clean) AS marked_clean,
    count(*) FILTER (WHERE cardinality(labels) = 0 AND is_clean IS NOT TRUE) AS remaining,
    round(100.0 * count(*) FILTER (WHERE cardinality(labels) > 0 OR is_clean)::numeric / NULLIF(count(*), 0)::numeric, 1) AS pct_done
   FROM analysis.human_label;
CREATE OR REPLACE VIEW analysis.vw_message_behavior AS
 SELECT m.id AS message_id,
    m.conversation_id,
    m.ts_utc,
    m.direction,
    m.has_behaviors,
    m.behavior_count,
    m.max_behavior_severity,
    count(pf.*) AS finding_count,
    count(pf.*) FILTER (WHERE pf.review_status = 'approved'::review_state) AS confirmed_count,
    bool_or(pf.category_id = 'threats'::citext) AS flag_threat_hypothesis,
    bool_or(pf.category_id = 'threats'::citext AND pf.review_status = 'approved'::review_state) AS flag_threat_confirmed,
    bool_or(pf.category_id = 'gaslighting'::citext) AS flag_gaslighting_hypothesis,
    bool_or(pf.category_id = 'minimizing'::citext) AS flag_minimizing_hypothesis,
    bool_or(pf.category_id = 'blame_shifting'::citext) AS flag_blame_hypothesis,
    array_agg(DISTINCT pf.category_id) FILTER (WHERE pf.category_id IS NOT NULL) AS categories
   FROM working.message m
     LEFT JOIN analysis.pattern_finding pf ON pf.subject_id = m.id AND pf.subject_type = 'message'::text
  GROUP BY m.id, m.conversation_id, m.ts_utc, m.direction, m.has_behaviors, m.behavior_count, m.max_behavior_severity;
CREATE OR REPLACE VIEW analysis.vw_open_tasks AS
 SELECT id,
    task_key,
    case_id,
    status,
    priority,
    priority_score,
    due_date,
    due_basis,
    human_action,
    human_action_kind,
    label_sensitivity,
    hitl_required,
    hitl_status,
    confidence_tier,
    is_hypothesis,
    ( SELECT count(*) AS count
           FROM analysis.task_dependency d
          WHERE d.depends_on = t.id AND (d.dep_kind = ANY (ARRAY['blocks'::text, 'prereq_of'::text]))) AS blocks_n,
    ( SELECT e.to_status
           FROM analysis.task_event e
          WHERE e.task_id = t.id
          ORDER BY e.ts DESC
         LIMIT 1) AS last_event
   FROM analysis.evidence_task t
  WHERE status <> ALL (ARRAY['closed_satisfied'::text, 'closed_unmet'::text, 'closed_overcome'::text, 'superseded'::text, 'archived'::text])
  ORDER BY priority, priority_score DESC NULLS LAST, due_date;
CREATE OR REPLACE VIEW evidence.vw_artifacts_without_claim AS
 SELECT s.id AS source_id,
    s.original_filename,
    s.source_type,
    s.byte_size,
    s.ingested_at,
    am.source_id IS NOT NULL AS has_metadata_row,
    ( SELECT count(*) AS count
           FROM evidence.vw_raw_all r
          WHERE r.source_id = s.id) AS raw_rows
   FROM evidence.source s
     LEFT JOIN evidence.artifact_metadata am ON am.source_id = s.id
  WHERE am.source_id IS NULL OR am.record_count_claimed IS NULL;
CREATE OR REPLACE VIEW evidence.vw_dropped_records AS
 SELECT j.id AS rejected_id,
    encode(j.source_sha256, 'hex'::text) AS h1,
    s.original_filename,
    ir.parser,
    ir.parser_version,
    ir.status AS run_status,
    j.record_index,
    j.element_tag,
    j.reason,
    j.reason_detail,
    j.content_hash,
    j.raw,
    j.created_at
   FROM raw.raw_rejected j
     JOIN evidence.ingest_run ir ON ir.id = j.ingest_run_id
     LEFT JOIN evidence.source s ON s.sha256 = j.source_sha256;
CREATE OR REPLACE VIEW evidence.vw_ingest_history AS
 SELECT id AS run_id,
    source_filename,
    status,
    parser,
    parser_version,
    runner,
    started_at,
    finished_at,
    EXTRACT(epoch FROM finished_at - started_at)::bigint AS duration_s,
    count_claimed,
    count_parsed,
    count_rejected,
    count_deduped,
    count_raw,
    count_spine,
    count_attestations,
    COALESCE(count_claimed, 0::bigint) - COALESCE(count_parsed, 0::bigint) AS claimed_minus_parsed,
    outcome_detail,
    notes
   FROM evidence.ingest_run ir
  ORDER BY started_at DESC;
CREATE OR REPLACE VIEW evidence.vw_raw_all AS
 SELECT 'evidence.raw_sms'::text AS raw_table,
    raw_sms.id,
    raw_sms.source_id,
    raw_sms.device_id,
    raw_sms.acquisition_id,
    raw_sms.medium,
    raw_sms.record_index,
    raw_sms.content_hash,
    raw_sms.parser_version,
    raw_sms.superseded_by,
    raw_sms.ingested_at
   FROM raw.raw_sms
UNION ALL
 SELECT 'evidence.raw_imessage'::text AS raw_table,
    raw_imessage.id,
    raw_imessage.source_id,
    raw_imessage.device_id,
    raw_imessage.acquisition_id,
    raw_imessage.medium,
    raw_imessage.record_index,
    raw_imessage.content_hash,
    raw_imessage.parser_version,
    raw_imessage.superseded_by,
    raw_imessage.ingested_at
   FROM raw.raw_imessage
UNION ALL
 SELECT 'evidence.raw_facebook'::text AS raw_table,
    raw_facebook.id,
    raw_facebook.source_id,
    raw_facebook.device_id,
    raw_facebook.acquisition_id,
    raw_facebook.medium,
    raw_facebook.record_index,
    raw_facebook.content_hash,
    raw_facebook.parser_version,
    raw_facebook.superseded_by,
    raw_facebook.ingested_at
   FROM raw.raw_facebook
UNION ALL
 SELECT 'evidence.raw_ai_chat'::text AS raw_table,
    raw_ai_chat.id,
    raw_ai_chat.source_id,
    raw_ai_chat.device_id,
    raw_ai_chat.acquisition_id,
    raw_ai_chat.medium,
    raw_ai_chat.record_index,
    raw_ai_chat.content_hash,
    raw_ai_chat.parser_version,
    raw_ai_chat.superseded_by,
    raw_ai_chat.ingested_at
   FROM raw.raw_ai_chat
UNION ALL
 SELECT 'evidence.raw_csv'::text AS raw_table,
    raw_csv.id,
    raw_csv.source_id,
    raw_csv.device_id,
    raw_csv.acquisition_id,
    raw_csv.medium,
    raw_csv.record_index,
    raw_csv.content_hash,
    raw_csv.parser_version,
    raw_csv.superseded_by,
    raw_csv.ingested_at
   FROM raw.raw_csv
UNION ALL
 SELECT 'evidence.raw_phone'::text AS raw_table,
    raw_phone.id,
    raw_phone.source_id,
    raw_phone.device_id,
    raw_phone.acquisition_id,
    raw_phone.medium,
    raw_phone.record_index,
    raw_phone.content_hash,
    raw_phone.parser_version,
    raw_phone.superseded_by,
    raw_phone.ingested_at
   FROM raw.raw_phone;
CREATE OR REPLACE VIEW evidence.vw_source_acquisition AS
 SELECT s.id AS source_id,
    s.original_filename,
    s.sha256,
    s.acquisition_source AS file_acquisition_source,
    s.acquisition_method AS file_acquisition_method,
    s.custodian AS file_custodian,
    s.acquired_at_utc AS file_acquired_at,
    s.provenance_tier,
    a.id AS acquisition_id,
    a.method AS event_method,
    a.authority AS event_authority,
    a.device_custodian AS event_custodian,
    a.acquired_at AS event_acquired_at,
    a.export_created_at,
    a.producible,
        CASE
            WHEN a.id IS NULL THEN 'no_acquisition_event'::text
            WHEN s.acquisition_method IS DISTINCT FROM a.method::text THEN 'METHOD_DIVERGES'::text
            WHEN s.acquired_at_utc IS NOT NULL AND a.acquired_at IS NOT NULL AND abs(EXTRACT(epoch FROM s.acquired_at_utc - a.acquired_at)) > 86400::numeric THEN 'ACQUIRED_AT_DIVERGES'::text
            ELSE 'consistent'::text
        END AS reconciliation_status
   FROM evidence.source s
     LEFT JOIN evidence.acquisition a ON a.id = s.acquisition_id;
CREATE OR REPLACE VIEW public.geography_columns AS
 SELECT current_database() AS f_table_catalog,
    n.nspname AS f_table_schema,
    c.relname AS f_table_name,
    a.attname AS f_geography_column,
    postgis_typmod_dims(a.atttypmod) AS coord_dimension,
    postgis_typmod_srid(a.atttypmod) AS srid,
    postgis_typmod_type(a.atttypmod) AS type
   FROM pg_class c,
    pg_attribute a,
    pg_type t,
    pg_namespace n
  WHERE t.typname = 'geography'::name AND a.attisdropped = false AND a.atttypid = t.oid AND a.attrelid = c.oid AND c.relnamespace = n.oid AND (c.relkind = ANY (ARRAY['r'::"char", 'v'::"char", 'm'::"char", 'f'::"char", 'p'::"char"])) AND NOT pg_is_other_temp_schema(c.relnamespace) AND has_table_privilege(c.oid, 'SELECT'::text);
CREATE OR REPLACE VIEW public.geometry_columns AS
 SELECT current_database()::character varying(256) AS f_table_catalog,
    n.nspname AS f_table_schema,
    c.relname AS f_table_name,
    a.attname AS f_geometry_column,
    COALESCE(postgis_typmod_dims(a.atttypmod), sn.ndims, 2) AS coord_dimension,
    COALESCE(NULLIF(postgis_typmod_srid(a.atttypmod), 0), sr.srid, 0) AS srid,
    replace(replace(COALESCE(NULLIF(upper(postgis_typmod_type(a.atttypmod)), 'GEOMETRY'::text), st.type, 'GEOMETRY'::text), 'ZM'::text, ''::text), 'Z'::text, ''::text)::character varying(30) AS type
   FROM pg_class c
     JOIN pg_attribute a ON a.attrelid = c.oid AND NOT a.attisdropped
     JOIN pg_namespace n ON c.relnamespace = n.oid
     JOIN pg_type t ON a.atttypid = t.oid
     LEFT JOIN ( SELECT s.connamespace,
            s.conrelid,
            s.conkey,
            (regexp_match(s.consrc, 'geometrytype\(\w+\)\s*=\s*''(\w+)'''::text, 'i'::text))[1] AS type
           FROM ( SELECT pg_constraint.connamespace,
                    pg_constraint.conrelid,
                    pg_constraint.conkey,
                    pg_get_constraintdef(pg_constraint.oid) AS consrc
                   FROM pg_constraint) s
          WHERE s.consrc ~* 'geometrytype\(\w+\)\s*=\s*''\w+'''::text) st ON st.connamespace = n.oid AND st.conrelid = c.oid AND (a.attnum = ANY (st.conkey))
     LEFT JOIN ( SELECT s.connamespace,
            s.conrelid,
            s.conkey,
            (regexp_match(s.consrc, 'ndims\(\w+\)\s*=\s*(\d+)'::text, 'i'::text))[1]::integer AS ndims
           FROM ( SELECT pg_constraint.connamespace,
                    pg_constraint.conrelid,
                    pg_constraint.conkey,
                    pg_get_constraintdef(pg_constraint.oid) AS consrc
                   FROM pg_constraint) s
          WHERE s.consrc ~* 'ndims\(\w+\)\s*=\s*\d+'::text) sn ON sn.connamespace = n.oid AND sn.conrelid = c.oid AND (a.attnum = ANY (sn.conkey))
     LEFT JOIN ( SELECT s.connamespace,
            s.conrelid,
            s.conkey,
            (regexp_match(s.consrc, 'srid\(\w+\)\s*=\s*(\d+)'::text, 'i'::text))[1]::integer AS srid
           FROM ( SELECT pg_constraint.connamespace,
                    pg_constraint.conrelid,
                    pg_constraint.conkey,
                    pg_get_constraintdef(pg_constraint.oid) AS consrc
                   FROM pg_constraint) s
          WHERE s.consrc ~* 'srid\(\w+\)\s*=\s*\d+'::text) sr ON sr.connamespace = n.oid AND sr.conrelid = c.oid AND (a.attnum = ANY (sr.conkey))
  WHERE (c.relkind = ANY (ARRAY['r'::"char", 'v'::"char", 'm'::"char", 'f'::"char", 'p'::"char"])) AND NOT c.relname = 'raster_columns'::name AND t.typname = 'geometry'::name AND NOT pg_is_other_temp_schema(c.relnamespace) AND has_table_privilege(c.oid, 'SELECT'::text);
CREATE OR REPLACE VIEW public.pg_stat_statements AS
 SELECT userid,
    dbid,
    toplevel,
    queryid,
    query,
    plans,
    total_plan_time,
    min_plan_time,
    max_plan_time,
    mean_plan_time,
    stddev_plan_time,
    calls,
    total_exec_time,
    min_exec_time,
    max_exec_time,
    mean_exec_time,
    stddev_exec_time,
    rows,
    shared_blks_hit,
    shared_blks_read,
    shared_blks_dirtied,
    shared_blks_written,
    local_blks_hit,
    local_blks_read,
    local_blks_dirtied,
    local_blks_written,
    temp_blks_read,
    temp_blks_written,
    shared_blk_read_time,
    shared_blk_write_time,
    local_blk_read_time,
    local_blk_write_time,
    temp_blk_read_time,
    temp_blk_write_time,
    wal_records,
    wal_fpi,
    wal_bytes,
    wal_buffers_full,
    jit_functions,
    jit_generation_time,
    jit_inlining_count,
    jit_inlining_time,
    jit_optimization_count,
    jit_optimization_time,
    jit_emission_count,
    jit_emission_time,
    jit_deform_count,
    jit_deform_time,
    parallel_workers_to_launch,
    parallel_workers_launched,
    stats_since,
    minmax_stats_since
   FROM pg_stat_statements(true) pg_stat_statements(userid, dbid, toplevel, queryid, query, plans, total_plan_time, min_plan_time, max_plan_time, mean_plan_time, stddev_plan_time, calls, total_exec_time, min_exec_time, max_exec_time, mean_exec_time, stddev_exec_time, rows, shared_blks_hit, shared_blks_read, shared_blks_dirtied, shared_blks_written, local_blks_hit, local_blks_read, local_blks_dirtied, local_blks_written, temp_blks_read, temp_blks_written, shared_blk_read_time, shared_blk_write_time, local_blk_read_time, local_blk_write_time, temp_blk_read_time, temp_blk_write_time, wal_records, wal_fpi, wal_bytes, wal_buffers_full, jit_functions, jit_generation_time, jit_inlining_count, jit_inlining_time, jit_optimization_count, jit_optimization_time, jit_emission_count, jit_emission_time, jit_deform_count, jit_deform_time, parallel_workers_to_launch, parallel_workers_launched, stats_since, minmax_stats_since);
CREATE OR REPLACE VIEW public.pg_stat_statements_info AS
 SELECT dealloc,
    stats_reset
   FROM pg_stat_statements_info() pg_stat_statements_info(dealloc, stats_reset);
CREATE OR REPLACE VIEW public.vw_event_evidence_package AS
 SELECT e.event_id,
    e.serial_id,
    e.title,
    e.event_type,
    ta.valid_earliest,
    ta.valid_latest,
    ta.valid_point,
    ta.ts_utc,
    ta.certainty,
    ta.assertion_type,
    ta.confidence,
    ta.disclosure_horizon,
        CASE
            WHEN ta.certainty = 'exact'::precision_class AND ta.confidence::numeric >= 0.80 THEN 'HIGH'::text
            WHEN ta.certainty = 'approximate'::precision_class AND ta.confidence::numeric >= 0.60 THEN 'MEDIUM'::text
            ELSE 'LOW'::text
        END AS temporal_confidence_tier,
    e.mcl_relevance,
    e.source_artifact_id,
    ta.reasoning
   FROM analysis.timeline_event e
     JOIN analysis.time_assertion ta ON ta.event_id = e.event_id AND upper_inf(ta.sys_period)
  WHERE e.safe_for_legal_use AND NOT e.requires_human_review AND NOT ta.requires_human_review;
CREATE OR REPLACE VIEW public.vw_llm_cost_rollup AS
 SELECT date_trunc('day'::text, created_at) AS day,
    tool_name,
    tool_category,
    count(*) AS calls,
    sum(cost_estimate) AS total_cost,
    sum(runtime_ms) AS total_ms
   FROM ops.tool_call_ledger
  GROUP BY (date_trunc('day'::text, created_at)), tool_name, tool_category
  ORDER BY (date_trunc('day'::text, created_at)) DESC, (sum(cost_estimate)) DESC NULLS LAST;
CREATE OR REPLACE VIEW public.vw_prompt_performance AS
 SELECT pr.prompt_name,
    pr.prompt_version,
    count(l.*) AS uses,
    avg(l.runtime_ms)::numeric(10,1) AS avg_runtime_ms,
    sum(l.cost_estimate) AS total_cost,
    count(*) FILTER (WHERE l.errors IS NOT NULL) AS error_count
   FROM prompt_registry pr
     LEFT JOIN ops.tool_call_ledger l ON l.prompt_version = pr.prompt_version
  GROUP BY pr.prompt_name, pr.prompt_version;
CREATE OR REPLACE VIEW timeline.vw_projection_expected_manifest AS
 SELECT g.id AS generation_id,
    g.sequence,
    g.status,
    g.membership_hash,
    g.content_hash,
    m.stable_member_id,
    m.opensearch_doc_id,
    m.member_content_hash,
    m.authority_state,
    m.change_class
   FROM timeline.timeline_projection_generation g
     JOIN timeline.timeline_projection_member m ON m.generation_id = g.id
  ORDER BY g.sequence, m.stable_member_id;
CREATE OR REPLACE VIEW timeline.vw_projection_receipt_current AS
 SELECT DISTINCT ON (generation_id, member_id, sink) generation_id,
    member_id,
    sink,
    status,
    attempt,
    expected_content_hash,
    observed_content_hash,
    opensearch_doc_id,
    opensearch_index,
    error_code,
    error_digest,
    started_at,
    finished_at,
    observed_at,
    id AS receipt_id,
    created_at
   FROM timeline.timeline_projection_receipt
  ORDER BY generation_id, member_id, sink, created_at DESC, id DESC;
CREATE OR REPLACE VIEW working.content_chunk_current_classification AS
 SELECT DISTINCT ON (chunk_id) chunk_id,
    id AS decision_id,
    decision_version,
    lane,
    review_state,
    classifier_id,
    classifier_version,
    confidence,
    reviewed_by,
    reviewed_at
   FROM analysis.content_chunk_classification_decision
  WHERE review_state = ANY (ARRAY['system_initial'::text, 'human_approved'::text])
  ORDER BY chunk_id, decision_version DESC, created_at DESC, id DESC;
CREATE OR REPLACE VIEW working.current_provenance AS
 SELECT DISTINCT ON (source_raw_table, source_raw_id) id,
    source_raw_table,
    source_raw_id,
    revision,
    occurred_at,
    export_created_at,
    acquired_at,
    ingested_at,
    realized_at,
    realized_at_source,
    realized_at_state,
    acquisition_method,
    acquisition_authority,
    source_device,
    device_custodian,
    custody_transferred_at,
    acquisition_notes,
    asserted_by,
    asserted_by_kind,
    producible,
    created_at
   FROM working.source_provenance
  ORDER BY source_raw_table, source_raw_id, revision DESC;
CREATE OR REPLACE VIEW working.knowledge_gap AS
 SELECT source_raw_table,
    source_raw_id,
    occurred_at,
    realized_at,
    realized_at - occurred_at AS gap,
    acquisition_method,
    acquisition_authority,
    producible
   FROM working.current_provenance
  WHERE occurred_at IS NOT NULL AND realized_at IS NOT NULL;
CREATE OR REPLACE VIEW working.review_queue AS
 SELECT 'entity'::text AS kind,
    e.id,
    e.created_at,
    e.confidence,
    e.source_raw_table,
    e.source_raw_id,
    e.name AS label,
    e.review_state
   FROM working.candidate_entity e
  WHERE e.review_state = 'pending'::text
UNION ALL
 SELECT 'fact'::text AS kind,
    f.id,
    f.created_at,
    f.confidence,
    f.source_raw_table,
    f.source_raw_id,
    f.statement AS label,
    f.review_state
   FROM working.candidate_fact f
  WHERE f.review_state = 'pending'::text
UNION ALL
 SELECT 'event'::text AS kind,
    v.id,
    v.created_at,
    v.confidence,
    v.source_raw_table,
    v.source_raw_id,
    v.summary AS label,
    v.review_state
   FROM working.candidate_event v
  WHERE v.review_state = 'pending'::text;
CREATE OR REPLACE VIEW working.vw_derivation_lineage AS
 SELECT nr.id AS record_id,
    nr.record_type,
    nr.occurred_at,
    "left"(nr.content, 120) AS content_preview,
    nr.derived_from_raw_table AS raw_table,
    nr.derived_from_raw_id AS raw_id,
    nr.deriver_version,
    nr.derived_at,
    r.parser_version,
    r.record_index,
    r.content_hash,
    r.superseded_by AS raw_superseded_by,
    s.id AS source_id,
    s.original_filename,
    encode(s.sha256, 'hex'::text) AS h1,
    a.id AS acquisition_id,
    a.method AS acquisition_method,
    a.authority AS acquisition_authority,
    nr.acquired_at,
    nr.export_created_at,
    nr.ingested_at
   FROM working.normalized_record nr
     LEFT JOIN evidence.vw_raw_all r ON r.id = nr.derived_from_raw_id
     LEFT JOIN evidence.source s ON s.id = r.source_id
     LEFT JOIN evidence.acquisition a ON a.id = nr.acquisition_id;
CREATE OR REPLACE VIEW working.vw_horizon_atom AS
 SELECT nr.case_id,
    'normalized_record'::text AS atom_kind,
    nr.id AS atom_id,
    nr.id AS normalized_record_id,
    NULL::uuid AS realization_event_id,
    nr.occurred_at,
    working.source_available_from(nr.id) AS visible_from,
    nr.disclosure_tier,
    nr.content,
    nr.attrs
   FROM working.normalized_record nr
UNION ALL
 SELECT re.case_id,
    'realization_event'::text AS atom_kind,
    re.id AS atom_id,
    NULL::uuid AS normalized_record_id,
    re.id AS realization_event_id,
    re.realized_at AS occurred_at,
    re.realized_at AS visible_from,
    'discovered'::text AS disclosure_tier,
    COALESCE(re.notes, ''::text) AS content,
    jsonb_build_object('kind', re.kind, 'evidence_pointer', re.evidence_pointer) AS attrs
   FROM working.realization_event re
  WHERE re.approval_state = 'approved'::text;
CREATE OR REPLACE VIEW working.vw_message_imessage AS
 SELECT m.id AS message_id,
    m.conversation_id,
    m.ts_utc,
    m.direction,
    m.is_read,
    m.external_id AS apple_guid,
    m.platform_attrs ->> 'service'::text AS service,
    m.platform_attrs ->> 'date_read'::text AS date_read,
    m.platform_attrs ->> 'date_edited'::text AS date_edited,
    m.platform_attrs ->> 'thread_originator_guid'::text AS reply_to_guid,
    m.raw_ts,
    nr.content
   FROM working.message m
     LEFT JOIN working.normalized_record nr ON nr.id = m.id
  WHERE m.platform = 'imessage'::text;
CREATE OR REPLACE VIEW working.vw_message_sms AS
 SELECT m.id AS message_id,
    m.conversation_id,
    m.ts_utc,
    m.direction,
    m.is_read,
    m.sender_e164,
    m.recipient_e164,
    m.delivery_status,
    m.status_code,
    m.is_blocked,
    m.platform_attrs ->> 'service_center'::text AS service_center,
    m.platform_attrs ->> 'sub_id'::text AS sub_id,
    m.platform_attrs ->> 'contact_name'::text AS contact_name,
    m.raw_ts,
    nr.content
   FROM working.message m
     LEFT JOIN working.normalized_record nr ON nr.id = m.id
  WHERE m.platform = 'sms'::text;
CREATE OR REPLACE VIEW working.vw_record_attestations AS
 SELECT r.id AS record_id,
    r.occurred_at,
    count(esr.link_id) AS attestation_count,
    count(*) FILTER (WHERE esr.agrees IS FALSE) AS disagreeing_count,
    array_agg(DISTINCT esr.medium) FILTER (WHERE esr.medium IS NOT NULL) AS mediums,
    array_agg(DISTINCT esr.raw_table) FILTER (WHERE esr.raw_table IS NOT NULL) AS raw_tables,
    array_agg(DISTINCT esr.source_id) FILTER (WHERE esr.source_id IS NOT NULL) AS source_ids,
        CASE
            WHEN count(*) FILTER (WHERE esr.agrees IS FALSE) > 0 THEN 'CONFLICTED'::text
            WHEN count(esr.link_id) > 1 THEN 'corroborated'::text
            WHEN count(esr.link_id) = 1 THEN 'single_source'::text
            ELSE 'unlinked'::text
        END AS attestation_status
   FROM working.normalized_record r
     LEFT JOIN working.event_source_record esr ON esr.record_id = r.id
  GROUP BY r.id, r.occurred_at;
CREATE OR REPLACE VIEW working.vw_record_disclosure AS
 SELECT id,
    occurred_at,
    acquired_at,
    realized_at,
    disclosure_tier AS disclosure_tier_asserted,
        CASE
            WHEN realized_at IS NULL AND acquired_at IS NULL THEN NULL::text
            WHEN realized_at IS NOT NULL AND occurred_at IS NOT NULL AND realized_at > (occurred_at + '30 days'::interval) THEN 'hindsight'::text
            WHEN acquired_at IS NOT NULL AND occurred_at IS NOT NULL AND acquired_at > (occurred_at + '30 days'::interval) THEN 'discovered'::text
            ELSE 'contemporaneous'::text
        END AS disclosure_tier_derived,
        CASE
            WHEN realized_at IS NOT NULL AND occurred_at IS NOT NULL THEN realized_at - occurred_at
            ELSE NULL::interval
        END AS realization_lag
   FROM working.normalized_record r;
CREATE OR REPLACE VIEW working.vw_spine_horizon AS
 SELECT id,
    artifact_id,
    record_type,
    source,
    conversation_id,
    role,
    participants,
    content,
    occurred_at,
    knowledge_time,
    disclosure_tier,
    attrs,
    created_at,
    conversation_ref,
    ts_precision,
    sensitivity_tier,
    data_tier,
    review_status,
    safe_for_legal_use,
    provenance_id,
    export_created_at,
    acquired_at,
    ingested_at,
    realized_at,
    realized_evidence,
    acquisition_id,
    device_id,
    sender_entity_id,
    derived_from_raw_table,
    derived_from_raw_id,
    deriver_version,
    derived_at,
    attestation_count,
    case_id,
    domain,
    topic_tags,
    knowledge_actor,
    ontology_version,
    source_record_key,
    source_content_sha256,
    sender,
    recipients,
    message_corpus
   FROM working.normalized_record r
  WHERE case_id = COALESCE(NULLIF(current_setting('app.case_id'::text, true), ''::text), 'primary'::text) AND working.horizon_record_visible(id, NULLIF(current_setting('app.horizon'::text, true), ''::text)::timestamp with time zone, NULLIF(current_setting('app.base_version'::text, true), ''::text)) AND (NULLIF(current_setting('app.horizon'::text, true), ''::text) IS NULL OR disclosure_tier <> 'hindsight'::text);
CREATE OR REPLACE VIEW working.vw_walk_base_version_input AS
 SELECT nr.case_id,
    'normalized_record'::text AS input_kind,
    nr.id::text AS input_key,
    jsonb_build_object('content_sha256', encode(COALESCE(nr.source_content_sha256, digest(convert_to(nr.content, 'UTF8'::name), 'sha256'::text)), 'hex'::text), 'occurred_at', nr.occurred_at, 'disclosure_tier', nr.disclosure_tier) AS input_payload
   FROM working.normalized_record nr
UNION ALL
 SELECT nr.case_id,
    'message_projection_route'::text AS input_kind,
    r.normalized_record_id::text AS input_key,
    jsonb_build_object('projection_kind', r.projection_kind, 'decision_state', r.decision_state, 'approved_at', r.approved_at, 'deriver_version', r.deriver_version) AS input_payload
   FROM working.message_projection_route r
     JOIN working.normalized_record nr ON nr.id = r.normalized_record_id
UNION ALL
 SELECT tc.case_id,
    'third_party_acquisition'::text AS input_kind,
    ca.id::text AS input_key,
    jsonb_build_object('conversation_id', ca.conversation_id, 'acquisition_id', ca.acquisition_id, 'approval_state', ca.approval_state, 'acquired_at', a.acquired_at) AS input_payload
   FROM working.third_party_conversation_acquisition ca
     JOIN working.third_party_conversation tc ON tc.id = ca.conversation_id
     JOIN evidence.acquisition a ON a.id = ca.acquisition_id
UNION ALL
 SELECT re.case_id,
    'realization_event'::text AS input_kind,
    re.id::text AS input_key,
    jsonb_build_object('kind', re.kind, 'realized_at', re.realized_at, 'approval_state', re.approval_state, 'trigger_record_id', re.trigger_record_id) AS input_payload
   FROM working.realization_event re
UNION ALL
 SELECT rer.case_id,
    'realization_event_record'::text AS input_kind,
    (rer.realization_event_id::text || ':'::text) || rer.normalized_record_id::text AS input_key,
    jsonb_build_object('realization_event_id', rer.realization_event_id, 'normalized_record_id', rer.normalized_record_id) AS input_payload
   FROM working.realization_event_record rer;
CREATE OR REPLACE VIEW working.vw_walk_contamination AS
 SELECT s.walk_run_id,
    s.step_no,
    s.horizon_at,
    ret.record_id,
    ret.store,
    ret.was_used,
    working.source_available_from(ret.record_id) AS visible_from
   FROM working.walk_step s
     JOIN working.walk_step_retrieval ret ON ret.walk_step_id = s.id
  WHERE working.source_available_from(ret.record_id) IS NULL OR s.horizon_at IS NOT NULL AND working.source_available_from(ret.record_id) > s.horizon_at
UNION ALL
 SELECT s.walk_run_id,
    s.step_no,
    s.horizon_at,
    NULL::uuid AS record_id,
    ret.store,
    ret.was_used,
    re.realized_at AS visible_from
   FROM working.walk_step s
     JOIN working.walk_step_realization_retrieval ret ON ret.walk_step_id = s.id
     JOIN working.realization_event re ON re.id = ret.realization_event_id
  WHERE re.approval_state <> 'approved'::text OR s.horizon_at IS NOT NULL AND re.realized_at > s.horizon_at;
CREATE OR REPLACE VIEW working.vw_walk_delta AS
 SELECT s.walk_run_id,
    s.step_no,
    s.horizon_at,
    s.record_id AS focal_record_id,
    s.conclusion AS believed_then,
    nr.content AS actual,
    nr.occurred_at,
    working.source_available_from(s.record_id) AS actual_known_from,
        CASE
            WHEN rz.first_realized_at IS NOT NULL AND nr.occurred_at IS NOT NULL THEN rz.first_realized_at - nr.occurred_at
            ELSE NULL::interval
        END AS realization_lag,
    rz.first_realized_at
   FROM working.walk_step s
     JOIN working.normalized_record nr ON nr.id = s.record_id
     LEFT JOIN LATERAL ( SELECT min(re.realized_at) AS first_realized_at
           FROM working.realization_event_record rer
             JOIN working.realization_event re ON re.id = rer.realization_event_id
          WHERE rer.normalized_record_id = s.record_id AND re.approval_state = 'approved'::text) rz ON true
  WHERE s.record_id IS NOT NULL;

-- ============ functions, pass 2 (resolves intra-section dependency order) ============
CREATE OR REPLACE FUNCTION analysis.entity_candidate_no_mutate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.entity_text  IS DISTINCT FROM OLD.entity_text
     OR NEW.record_id IS DISTINCT FROM OLD.record_id
     OR NEW.extractor IS DISTINCT FROM OLD.extractor
     OR NEW.span_start IS DISTINCT FROM OLD.span_start
     OR NEW.span_end   IS DISTINCT FROM OLD.span_end THEN
    RAISE EXCEPTION
      'analysis.entity_candidate is append-only: insert a new row instead of editing the claim';
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION analysis.extraction_candidate_no_mutate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.entity_text  IS DISTINCT FROM OLD.entity_text
     OR NEW.record_id IS DISTINCT FROM OLD.record_id
     OR NEW.extractor IS DISTINCT FROM OLD.extractor
     OR NEW.candidate_kind IS DISTINCT FROM OLD.candidate_kind
     OR NEW.span_start IS DISTINCT FROM OLD.span_start
     OR NEW.span_end   IS DISTINCT FROM OLD.span_end THEN
    RAISE EXCEPTION USING MESSAGE =
      'analysis.extraction_candidate is append-only: insert a new row instead of '
      'editing the claim (review columns and consumed_by are the mutable surface)';
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION analysis.knowledge_evidence_pointer_hash(pointer jsonb)
 RETURNS bytea
 LANGUAGE sql
 IMMUTABLE STRICT
AS $function$
    SELECT public.digest(
        convert_to(
            jsonb_build_object(
                'matter_id', pointer -> 'matter_id',
                'court_case_id', pointer -> 'court_case_id',
                'partition_key', pointer -> 'partition_key',
                'lane', pointer -> 'lane',
                'normalized_record_id', pointer -> 'normalized_record_id',
                'evidence_hash_id', pointer -> 'evidence_hash_id',
                'source_id', pointer -> 'source_id',
                'sha256', pointer -> 'sha256',
                'conversation_id', pointer -> 'conversation_id',
                'quote', pointer -> 'quote'
            )::text,
            'UTF8'
        ),
        'sha256'
    )
$function$
;
CREATE OR REPLACE FUNCTION analysis.log_task_status()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      IF NEW.status = 'archived' AND COALESCE(NEW.archive_reason,'') = '' THEN
        RAISE EXCEPTION 'archived status requires archive_reason (no silent discard)';
      END IF;
      INSERT INTO analysis.task_event(task_id, from_status, to_status, actor, actor_kind, reason, ts)
      VALUES (NEW.id, OLD.status, NEW.status, COALESCE(current_setting('app.actor', true),'system'),
              COALESCE(current_setting('app.actor_kind', true),'system'), NEW.archive_reason, now());
    END IF; RETURN NEW; END $function$
;
CREATE OR REPLACE FUNCTION analysis.record_graphrag_comparison_join(p_run_id uuid, p_stage_id text, p_stage_version text, p_manifest_id uuid, p_manifest_digest bytea, p_semantica_receipt_id uuid, p_sat_temporal_receipt_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id UUID;
BEGIN
  INSERT INTO analysis.graphrag_comparison_join (
    run_id, stage_id, stage_version, manifest_id, manifest_digest,
    semantica_receipt_id, sat_temporal_receipt_id)
  VALUES (p_run_id, p_stage_id, p_stage_version, p_manifest_id, p_manifest_digest,
          p_semantica_receipt_id, p_sat_temporal_receipt_id)
  ON CONFLICT (run_id, stage_id, stage_version, manifest_id, manifest_digest) DO UPDATE
    SET semantica_receipt_id    = COALESCE(EXCLUDED.semantica_receipt_id,    analysis.graphrag_comparison_join.semantica_receipt_id),
        sat_temporal_receipt_id = COALESCE(EXCLUDED.sat_temporal_receipt_id, analysis.graphrag_comparison_join.sat_temporal_receipt_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$
;
CREATE OR REPLACE FUNCTION analysis.seal_graphrag_manifest(p_manifest_id uuid)
 RETURNS TABLE(manifest_id uuid, membership_digest bytea, member_count integer, sealed_at timestamp with time zone)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_digest BYTEA;
  v_count  INTEGER;
  v_now    TIMESTAMPTZ := now();
BEGIN
  SELECT count(*)::INTEGER,
         digest(coalesce(string_agg(
           m.ordinal::TEXT || ':' || m.source_version_id::TEXT || ':' ||
           m.normalized_record_id::TEXT || ':' || coalesce(m.text_unit_id::TEXT,''),
           '|' ORDER BY m.ordinal), ''), 'sha256')
    INTO v_count, v_digest
    FROM analysis.graphrag_eligibility_manifest_member m
   WHERE m.manifest_id = p_manifest_id;

  UPDATE analysis.graphrag_eligibility_manifest
     SET status = 'sealed', membership_digest = v_digest,
         member_count = v_count, sealed_at = v_now
   WHERE id = p_manifest_id;

  RETURN QUERY SELECT p_manifest_id, v_digest, v_count, v_now;
END $function$
;
CREATE OR REPLACE FUNCTION analysis.set_case_management_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION analysis.snapshot_task()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ BEGIN
    INSERT INTO analysis.task_revision(task_id, snapshot, changed_by, change_note, ts)
    VALUES (OLD.id, to_jsonb(OLD), COALESCE(current_setting('app.actor', true),'unknown'),
            'auto-snapshot before UPDATE', now());
    RETURN NEW; END $function$
;
CREATE OR REPLACE FUNCTION canon.apply_proposal(p_proposal_id uuid, p_decision_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_p        canon.change_proposal%ROWTYPE;
  v_ct       canon.canonical_table%ROWTYPE;
  v_prior    JSONB := '{}'::jsonb;
  v_app_id   UUID;
  v_col      TEXT;
  v_pk_col   TEXT;
  v_pk_val   TEXT;
  v_set_sql  TEXT := '';
  v_tgt      TEXT;
BEGIN
  SELECT * INTO v_p  FROM canon.change_proposal  WHERE id = p_proposal_id FOR UPDATE;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'proposal % not found', p_proposal_id; END IF;
  IF v_p.status NOT IN ('proposed','approved') THEN
    RAISE EXCEPTION 'proposal % is %, not applicable', p_proposal_id, v_p.status;
  END IF;
  SELECT * INTO v_ct FROM canon.canonical_table  WHERE id = v_p.canonical_table_id FOR UPDATE;

  -- STALENESS GUARD: reasoned against a superseded generation -> requeue, never apply
  IF v_p.source_generation <> v_ct.current_generation THEN
    UPDATE canon.change_proposal SET status = 'stale_requeued' WHERE id = p_proposal_id;
    RETURN NULL;
  END IF;

  -- Only 'correct' patches are applied generically here; other kinds record the
  -- ruling + receipt and are executed by their kind-specific worker off the queue.
  IF v_p.proposal_kind = 'correct' THEN
    SELECT key, value #>> '{}' INTO v_pk_col, v_pk_val
      FROM jsonb_each(v_p.target_pk) LIMIT 1;
    -- snapshot prior values of exactly the patched columns
    EXECUTE format('SELECT to_jsonb(t) FROM %I.%I t WHERE %I = $1::uuid',
                   v_ct.table_schema, v_ct.table_name, v_pk_col)
      INTO v_prior USING v_pk_val;
    IF v_prior IS NULL THEN RAISE EXCEPTION 'target row not found for proposal %', p_proposal_id; END IF;
    SELECT jsonb_object_agg(k, v_prior -> k) INTO v_prior
      FROM jsonb_object_keys(v_p.patch) k;
    -- build and run the update
    SELECT string_agg(format('%I = ($1::jsonb ->> %L)::%s', key,
             key,
             (SELECT format_type(a.atttypid, a.atttypmod)
                FROM pg_attribute a
               WHERE a.attrelid = format('%I.%I', v_ct.table_schema, v_ct.table_name)::regclass
                 AND a.attname = key AND a.attnum > 0)), ', ')
      INTO v_set_sql
      FROM jsonb_each(v_p.patch);
    EXECUTE format('UPDATE %I.%I SET %s WHERE %I = $2::uuid',
                   v_ct.table_schema, v_ct.table_name, v_set_sql, v_pk_col)
      USING v_p.patch, v_pk_val;
  END IF;

  UPDATE canon.canonical_table
     SET current_generation = current_generation + 1
   WHERE id = v_ct.id;

  INSERT INTO canon.change_application
      (proposal_id, decision_id, prior_values, applied_patch, generation_before, generation_after)
  VALUES (p_proposal_id, p_decision_id, coalesce(v_prior,'{}'::jsonb), v_p.patch,
          v_ct.current_generation, v_ct.current_generation + 1)
  RETURNING id INTO v_app_id;

  FOREACH v_tgt IN ARRAY v_ct.recompute_targets LOOP
    INSERT INTO canon.recompute_queue
        (application_id, canonical_table_id, target_pk, recompute_target)
    VALUES (v_app_id, v_ct.id, v_p.target_pk, v_tgt);
  END LOOP;

  UPDATE canon.change_proposal SET status = 'applied' WHERE id = p_proposal_id;
  RETURN v_app_id;
END $function$
;
CREATE OR REPLACE FUNCTION canon.route_tier(p_canonical_table_id uuid, p_confidence numeric)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN ct.auto_confirm_min_confidence IS NOT NULL
     AND p_confidence IS NOT NULL
     AND p_confidence >= ct.auto_confirm_min_confidence
    THEN 'auto_adopt'
    ELSE ct.default_tier
  END
  FROM canon.canonical_table ct WHERE ct.id = p_canonical_table_id
$function$
;
CREATE OR REPLACE FUNCTION context.register_raw_format_subtype(p_format_id text)
 RETURNS regclass
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'context'
AS $function$
DECLARE
    v_table_name TEXT;
    v_relation REGCLASS;
    v_relation_kind "char";
    v_raw_record_attnum SMALLINT;
    v_raw_identity_id_attnum SMALLINT;
    v_native_fields_attnum SMALLINT;
    v_native_metadata_attnum SMALLINT;
BEGIN
    IF p_format_id !~ '^[a-z][a-z0-9_]{0,58}$' THEN
        RAISE EXCEPTION 'invalid raw format id %', p_format_id;
    END IF;

    v_table_name := 'raw_' || p_format_id;
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS context.%I (
            raw_record_id UUID PRIMARY KEY
                REFERENCES context.raw_record_identity(id) ON DELETE RESTRICT,
            native_fields JSONB NOT NULL DEFAULT ''{}''::jsonb
                CHECK (jsonb_typeof(native_fields) = ''object''),
            native_metadata JSONB NOT NULL DEFAULT ''{}''::jsonb
                CHECK (jsonb_typeof(native_metadata) = ''object''),
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )',
        v_table_name
    );
    v_relation := to_regclass(format('context.%I', v_table_name));

    SELECT relkind INTO v_relation_kind
    FROM pg_class
    WHERE oid = v_relation;
    IF v_relation_kind IS DISTINCT FROM 'r'::"char" THEN
        RAISE EXCEPTION 'raw subtype % must be an ordinary table, found relation kind %',
            v_relation::TEXT, v_relation_kind;
    END IF;

    SELECT attnum INTO v_raw_identity_id_attnum
    FROM pg_attribute
    WHERE attrelid = 'context.raw_record_identity'::regclass
      AND attname = 'id'
      AND atttypid = 'uuid'::regtype
      AND attnotnull
      AND NOT attisdropped;

    SELECT attnum INTO v_raw_record_attnum
    FROM pg_attribute
    WHERE attrelid = v_relation
      AND attname = 'raw_record_id'
      AND atttypid = 'uuid'::regtype
      AND attnotnull
      AND NOT attisdropped;

    IF v_raw_record_attnum IS NULL OR v_raw_identity_id_attnum IS NULL THEN
        RAISE EXCEPTION 'raw subtype % must have a NOT NULL UUID raw_record_id key column',
            v_relation::TEXT;
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = v_relation
          AND contype = 'p'
          AND conkey = ARRAY[v_raw_record_attnum]::SMALLINT[]
    ) THEN
        RAISE EXCEPTION 'raw subtype % must have raw_record_id as its exact primary key',
            v_relation::TEXT;
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = v_relation
          AND contype = 'f'
          AND confrelid = 'context.raw_record_identity'::regclass
          AND conkey = ARRAY[v_raw_record_attnum]::SMALLINT[]
          AND confkey = ARRAY[v_raw_identity_id_attnum]::SMALLINT[]
          AND confdeltype = 'r'
    ) THEN
        RAISE EXCEPTION 'raw subtype % must have an exact raw_record_id FK to context.raw_record_identity(id) ON DELETE RESTRICT',
            v_relation::TEXT;
    END IF;

    SELECT attnum INTO v_native_fields_attnum
    FROM pg_attribute
    WHERE attrelid = v_relation
      AND attname = 'native_fields'
      AND atttypid = 'jsonb'::regtype
      AND attnotnull
      AND NOT attisdropped;
    SELECT attnum INTO v_native_metadata_attnum
    FROM pg_attribute
    WHERE attrelid = v_relation
      AND attname = 'native_metadata'
      AND atttypid = 'jsonb'::regtype
      AND attnotnull
      AND NOT attisdropped;
    IF v_native_fields_attnum IS NULL OR v_native_metadata_attnum IS NULL THEN
        RAISE EXCEPTION 'raw subtype % must have NOT NULL JSONB native_fields and native_metadata columns',
            v_relation::TEXT;
    END IF;

    INSERT INTO context.raw_format_registry (format_id, subtype_relation)
    VALUES (p_format_id, v_relation)
    ON CONFLICT (format_id) DO NOTHING;
    IF (SELECT subtype_relation FROM context.raw_format_registry WHERE format_id = p_format_id)
       IS DISTINCT FROM v_relation THEN
        RAISE EXCEPTION 'raw format % is already registered to a different subtype relation', p_format_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = v_relation
          AND tgname = 'raw_subtype_append_only'
          AND NOT tgisinternal
    ) THEN
        EXECUTE format(
            'CREATE TRIGGER raw_subtype_append_only
             BEFORE UPDATE OR DELETE ON context.%I
             FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation()',
            v_table_name
        );
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = v_relation
          AND tgname = 'raw_subtype_open_generation_gate'
          AND NOT tgisinternal
    ) THEN
        EXECUTE format(
            'CREATE TRIGGER raw_subtype_open_generation_gate
             BEFORE INSERT ON context.%I
             FOR EACH ROW EXECUTE FUNCTION context.guard_raw_subtype_insert()',
            v_table_name
        );
    END IF;
    RETURN v_relation;
END;
$function$
;
CREATE OR REPLACE FUNCTION context.seal_hash_manifest_from_receipt()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'context'
AS $function$
BEGIN
    IF NEW.hash_kind IN ('context_raw_generation_fingerprint', 'normalized_generation_manifest_digest') THEN
        UPDATE context.hash_manifest SET status = 'sealed',
            member_count = (SELECT count(*) FROM context.hash_manifest_member WHERE hash_manifest_id = NEW.hash_manifest_id),
            sealed_hash_receipt_id = NEW.id, sealed_at = NEW.computed_at
        WHERE id = NEW.hash_manifest_id;
    END IF;
    RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION evidence.chain_custody_event()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.source_id::text, 0));
    SELECT ce.event_digest INTO NEW.prev_event_digest
      FROM evidence.custody_event ce
     WHERE ce.source_id = NEW.source_id ORDER BY ce.seq DESC LIMIT 1;
    NEW.event_digest := digest(convert_to(
        coalesce(NEW.source_id::text,'') || '|' || coalesce(NEW.file_node_id::text,'') || '|' ||
        coalesce(NEW.evidence_hash_id::text,'') || '|' || NEW.event_type || '|' || NEW.actor || '|' ||
        to_char(NEW.occurred_at,'YYYY-MM-DD"T"HH24:MI:SS.US TZH:TZM') || '|' ||
        coalesce(NEW.detail::text,'{}') || '|' || coalesce(encode(NEW.prev_event_digest,'hex'),''),
      'UTF8'), 'sha256');
    RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION evidence.raw_no_mutate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- INERT UNTIL LIVE (owner, 2026-08-01: "append only only starts once we are
  -- actually live"). During build-out the schema and parsers churn, and a hard
  -- immutability rule would force a DB rebuild for every iteration. The trigger is
  -- installed now so going live is a one-line switch rather than a migration:
  --
  --   ALTER DATABASE <db> SET app.evidence_live = 'on';
  --
  -- Until then raw behaves like an ordinary table.
  IF current_setting('app.evidence_live', true) IS DISTINCT FROM 'on' THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  -- One exception: marking a row superseded. That is the ONLY legal mutation, and it
  -- adds a forward pointer rather than changing anything the row asserts. Everything
  -- the row claimed about the source stays exactly as written.
  IF TG_OP = 'UPDATE'
     AND OLD.superseded_by IS NULL
     AND NEW.superseded_by IS NOT NULL
     AND NEW.raw            IS NOT DISTINCT FROM OLD.raw
     AND NEW.raw_text       IS NOT DISTINCT FROM OLD.raw_text
     AND NEW.content_hash   IS NOT DISTINCT FROM OLD.content_hash
     AND NEW.source_id      IS NOT DISTINCT FROM OLD.source_id
     AND NEW.device_id      IS NOT DISTINCT FROM OLD.device_id
     AND NEW.medium         IS NOT DISTINCT FROM OLD.medium
     AND NEW.record_index   IS NOT DISTINCT FROM OLD.record_index
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION USING MESSAGE =
    'evidence.' || TG_TABLE_NAME ||
    ' is append-only: raw source records are never updated or deleted '
    '(the only permitted change is setting superseded_by on a live row)';
END;
$function$
;
CREATE OR REPLACE FUNCTION ops.reset_test_data(p_confirm text)
 RETURNS TABLE(truncated_schema text, tables_truncated integer)
 LANGUAGE plpgsql
AS $function$
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
END $function$
;
CREATE OR REPLACE FUNCTION public.change_log_chain()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE prev bytea;
BEGIN
  SELECT row_hash INTO prev FROM public.change_log ORDER BY seq DESC LIMIT 1;
  NEW.prev_change_hash := prev;
  NEW.row_hash := digest(
      coalesce(NEW.table_name,'') || '|' || coalesce(NEW.record_id::text,'') || '|' ||
      coalesce(NEW.field_name,'') || '|' || NEW.action || '|' ||
      coalesce(NEW.previous_value,'') || '|' || coalesce(NEW.new_value,'') || '|' ||
      NEW.actor || '|' || NEW.change_origin || '|' || coalesce(encode(prev,'hex'),''), 'sha256');
  RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION public.require_consolidation_verified_proof_v0049()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_proof_kind TEXT;
    v_result TEXT;
    v_details JSONB;
BEGIN
    IF NEW.checkpoint_status <> 'verified' THEN
        RETURN NEW;
    END IF;

    SELECT receipt.proof_kind, receipt.result, receipt.details
    INTO v_proof_kind, v_result, v_details
    FROM public.platform_consolidation_proof_receipt AS receipt
    WHERE receipt.id = NEW.verified_receipt_id
      AND receipt.checkpoint_id = NEW.id
      AND NOT EXISTS (
          SELECT 1
          FROM public.platform_consolidation_proof_receipt AS successor
          WHERE successor.supersedes_receipt_id = receipt.id
      );

    IF NOT FOUND OR v_result <> 'pass' OR v_proof_kind <> NEW.required_proof_kind THEN
        RAISE EXCEPTION
            'verified consolidation checkpoint % requires its exact unsuperseded passing % receipt',
            NEW.id, NEW.required_proof_kind;
    END IF;
    IF NOT (v_details ?& ARRAY[
        'phase_key', 'relation_key', 'proof_kind', 'source_snapshot_id',
        'target_snapshot_id', 'source_snapshot_sha256', 'target_snapshot_sha256',
        'manifest_sha256', 'repository_revision'
    ])
       OR v_details->>'phase_key' IS DISTINCT FROM NEW.phase_key
       OR v_details->>'relation_key' IS DISTINCT FROM NEW.relation_key
       OR v_details->>'proof_kind' IS DISTINCT FROM NEW.required_proof_kind
       OR v_details->>'source_snapshot_id' IS DISTINCT FROM NEW.source_snapshot_id
       OR v_details->>'target_snapshot_id' IS DISTINCT FROM NEW.target_snapshot_id
       OR lower(v_details->>'source_snapshot_sha256') IS DISTINCT FROM encode(NEW.source_snapshot_sha256, 'hex')
       OR lower(v_details->>'target_snapshot_sha256') IS DISTINCT FROM encode(NEW.target_snapshot_sha256, 'hex')
       OR lower(v_details->>'manifest_sha256') IS DISTINCT FROM encode(NEW.manifest_sha256, 'hex')
       OR v_details->>'repository_revision' IS DISTINCT FROM NEW.repository_revision THEN
        RAISE EXCEPTION 'verified consolidation checkpoint % has an unbound proof receipt', NEW.id;
    END IF;
    IF NEW.required_proof_kind IN ('caller_inventory', 'zero_active_sessions')
       AND (
           NOT (v_details ?& ARRAY[
               'fence_attestation_id', 'fence_attestation_sha256', 'fence_established_at',
               'fence_valid_until'
           ])
           OR v_details->>'fence_attestation_id' IS DISTINCT FROM NEW.fence_attestation_id
           OR lower(v_details->>'fence_attestation_sha256')
              IS DISTINCT FROM encode(NEW.fence_attestation_sha256, 'hex')
           OR (v_details->>'fence_established_at')::TIMESTAMPTZ
              IS DISTINCT FROM NEW.fence_established_at
           OR (v_details->>'fence_valid_until')::TIMESTAMPTZ IS DISTINCT FROM NEW.fence_valid_until
       ) THEN
        RAISE EXCEPTION 'verified caller checkpoint % requires its exact bound fence attestation', NEW.id;
    END IF;
    BEGIN
        INSERT INTO public.platform_consolidation_receipt_claim (
            receipt_id, claim_kind, checkpoint_id
        ) VALUES (NEW.verified_receipt_id, 'verified', NEW.id);
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION
                'receipt % already has an incompatible immutable claim', NEW.verified_receipt_id
                USING ERRCODE = '23514';
    END;
    RETURN NEW;
END
$function$
;
CREATE OR REPLACE FUNCTION timeline.generation_supersede_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.status <> 'sealed' THEN
        RAISE EXCEPTION 'timeline_projection_generation %: already %, no further UPDATE allowed', OLD.id, OLD.status;
    END IF;
    IF NEW.status NOT IN ('superseded', 'quarantined') THEN
        RAISE EXCEPTION 'timeline_projection_generation: UPDATE must set status to superseded or quarantined';
    END IF;
    IF to_jsonb(NEW) - 'status' - 'superseded_by' IS DISTINCT FROM to_jsonb(OLD) - 'status' - 'superseded_by' THEN
        RAISE EXCEPTION 'timeline_projection_generation: only status/superseded_by may change';
    END IF;
    RETURN NEW;
END
$function$
;
CREATE OR REPLACE FUNCTION working.check_context_thread_realization_deferred()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'working'
AS $function$
DECLARE
    v_assertion_id UUID;
    v_party TEXT;
BEGIN
    IF TG_TABLE_NAME LIKE '%_realization_assertion' THEN
        v_assertion_id := NEW.id;
    ELSE
        v_assertion_id := NEW.realization_assertion_id;
    END IF;
    IF TG_TABLE_NAME LIKE 'first_party_%' THEN
        v_party := 'first_party';
    ELSE
        v_party := 'third_party';
    END IF;
    PERFORM working.validate_context_thread_realization_sources(v_assertion_id, v_party);
    RETURN NULL;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.check_context_thread_version_deferred()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'working'
AS $function$
DECLARE
    v_version_id UUID;
BEGIN
    IF TG_TABLE_NAME LIKE '%_thread_version' THEN
        v_version_id := NEW.id;
    ELSE
        v_version_id := NEW.thread_version_id;
    END IF;
    IF TG_TABLE_NAME LIKE 'first_party_%' THEN
        PERFORM working.validate_first_party_context_thread_version(v_version_id);
    ELSE
        PERFORM working.validate_third_party_context_thread_version(v_version_id);
    END IF;
    RETURN NULL;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.check_source_range_locator_subject_deferred()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'working'
AS $function$
BEGIN
    PERFORM working.validate_source_range_locator_subject(
        CASE WHEN TG_TABLE_NAME = 'source_range_locator' THEN NEW.id
             ELSE NEW.source_range_locator_id END
    );
    RETURN NULL;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.emit_chat_row_event()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE target_table TEXT := TG_TABLE_NAME || '_event';
BEGIN
    EXECUTE format('INSERT INTO working.%I (operation, row_data) VALUES ($1, $2)', target_table)
        USING TG_OP, to_jsonb(NEW);
    PERFORM pg_notify('working_chat_changed', TG_TABLE_NAME);
    RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.enqueue_evidence_vector_projection(p_record_ids uuid[], p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE queued INTEGER;
BEGIN
  IF p_reason IS NULL OR length(trim(p_reason))=0 THEN
    RAISE EXCEPTION 'VECTOR_PROJECTION_REASON_REQUIRED';
  END IF;
  INSERT INTO working.evidence_vector_projection_job(chunk_id, reason)
  SELECT chunk.id, p_reason
    FROM working.normalized_record_chunk chunk
   WHERE chunk.normalized_record_id=ANY(p_record_ids)
  ON CONFLICT (chunk_id, projection_version) DO UPDATE
    SET reason=EXCLUDED.reason, status='pending', generation=working.evidence_vector_projection_job.generation+1,
        next_attempt_at=now(),
        locked_at=NULL, locked_by=NULL, completed_at=NULL, updated_at=now();
  GET DIAGNOSTICS queued = ROW_COUNT;
  RETURN queued;
END $function$
;
CREATE OR REPLACE FUNCTION working.entity_candidate_no_mutate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.entity_text  IS DISTINCT FROM OLD.entity_text
     OR NEW.record_id IS DISTINCT FROM OLD.record_id
     OR NEW.extractor IS DISTINCT FROM OLD.extractor
     OR NEW.span_start IS DISTINCT FROM OLD.span_start
     OR NEW.span_end   IS DISTINCT FROM OLD.span_end THEN
    RAISE EXCEPTION
      'analysis.entity_candidate is append-only: insert a new row instead of editing the claim';
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.extraction_candidate_no_mutate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.entity_text  IS DISTINCT FROM OLD.entity_text
     OR NEW.record_id IS DISTINCT FROM OLD.record_id
     OR NEW.extractor IS DISTINCT FROM OLD.extractor
     OR NEW.candidate_kind IS DISTINCT FROM OLD.candidate_kind
     OR NEW.span_start IS DISTINCT FROM OLD.span_start
     OR NEW.span_end   IS DISTINCT FROM OLD.span_end THEN
    RAISE EXCEPTION USING MESSAGE =
      'analysis.extraction_candidate is append-only: insert a new row instead of '
      'editing the claim (review columns and consumed_by are the mutable surface)';
  END IF;
  RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.horizon_record_visible(p_record_id uuid, p_horizon timestamp with time zone, p_base_version text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
  SELECT COALESCE((
    SELECT CASE
      WHEN source_time IS NULL THEN false
      WHEN p_horizon IS NULL THEN true
      ELSE source_time<=p_horizon
    END
    FROM (
      SELECT CASE
        WHEN p_base_version IS NOT NULL
             AND rvf.base_version=p_base_version
             AND rvf.base_version<>'__legacy_untrusted__'
          THEN rvf.visible_from
        ELSE working.source_available_from(nr.id)
      END AS source_time
      FROM working.normalized_record nr
      LEFT JOIN working.record_visible_from rvf ON rvf.record_id=nr.id
      WHERE nr.id=p_record_id
    ) q
  ), false);
$function$
;
CREATE OR REPLACE FUNCTION working.horizon_visible(row_case_id text, row_knowledge_time timestamp with time zone, row_disclosure text, row_actor text, p_case_id text, p_horizon timestamp with time zone, p_actor text DEFAULT 'owner'::text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT row_case_id = p_case_id
       AND (
            p_horizon IS NULL                       -- hindsight: no cutoff
            OR (row_knowledge_time IS NOT NULL
                AND row_knowledge_time <= p_horizon
                AND row_actor = p_actor
                AND row_disclosure <> 'hindsight')  -- never leaks backwards
       );
$function$
;
CREATE OR REPLACE FUNCTION working.insert_initial_content_chunk_context()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'working'
AS $function$
BEGIN
    INSERT INTO working.content_chunk_classification_decision (
        chunk_id, decision_version, lane, decision_kind, review_state,
        classifier_id, classifier_version, confidence, rationale
    ) VALUES (
        NEW.id, 1, 'context', 'initial_context', 'system_initial',
        'context-first-ingest-policy', '0047', 1.0,
        'All intake begins in context; legal/personal_history require reviewed classification.'
    );
    RETURN NEW;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.promotion_revoke_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'working.promotion is append-only: DELETE blocked (revoke instead)';
    END IF;
    -- The ONLY legal update: first-time revocation. Everything else identical.
    IF OLD.revoked_at IS NOT NULL THEN
        RAISE EXCEPTION 'working.promotion: row already revoked; further updates blocked';
    END IF;
    IF NEW.revoked_at IS NULL THEN
        RAISE EXCEPTION 'working.promotion: UPDATE must set revoked_at (revocation is the only legal update)';
    END IF;
    IF to_jsonb(NEW) - 'revoked_at' - 'revoked_reason'
       IS DISTINCT FROM to_jsonb(OLD) - 'revoked_at' - 'revoked_reason' THEN
        RAISE EXCEPTION 'working.promotion: only revoked_at/revoked_reason may change on revocation';
    END IF;
    RETURN NEW;
END
$function$
;
CREATE OR REPLACE FUNCTION working.queue_vector_chunk_on_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM working.enqueue_evidence_vector_projection(
    ARRAY[NEW.normalized_record_id], 'normalized_record_chunk_insert');
  RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION working.queue_vector_route_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM working.enqueue_evidence_vector_projection(
    ARRAY[COALESCE(NEW.normalized_record_id,OLD.normalized_record_id)],
    'message_projection_authority_change');
  RETURN COALESCE(NEW,OLD);
END $function$
;
CREATE OR REPLACE FUNCTION working.queue_vector_third_party_authority_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE conversation UUID;
BEGIN
  conversation := COALESCE(NEW.conversation_id,OLD.conversation_id);
  PERFORM working.enqueue_evidence_vector_projection(
    ARRAY(SELECT message.normalized_record_id
            FROM working.third_party_message message
           WHERE message.conversation_id=conversation),
    'third_party_authority_change');
  RETURN COALESCE(NEW,OLD);
END $function$
;
CREATE OR REPLACE FUNCTION working.reject_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ BEGIN
    RAISE EXCEPTION 'append-only table %.% — % not allowed', TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP; END $function$
;
CREATE OR REPLACE FUNCTION working.source_available_from(p_record_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
SELECT CASE
  WHEN nr.record_type <> 'message' THEN nr.occurred_at
  WHEN r.decision_state <> 'approved' OR r.normalized_record_id IS NULL THEN NULL
  WHEN r.projection_kind='first_party' THEN nr.occurred_at
  WHEN r.projection_kind='acquired_third_party' THEN (
    SELECT MIN(a.acquired_at)
      FROM working.third_party_message tm
      JOIN working.third_party_conversation_acquisition ca ON ca.conversation_id=tm.conversation_id
      JOIN evidence.acquisition a ON a.id=ca.acquisition_id
     WHERE tm.normalized_record_id=nr.id
       AND ca.approval_state='approved'
       AND a.acquired_at IS NOT NULL)
END
FROM working.normalized_record nr
LEFT JOIN working.message_projection_route r ON r.normalized_record_id=nr.id
WHERE nr.id=p_record_id;
$function$
;
CREATE OR REPLACE FUNCTION working.validate_context_thread_realization_sources(p_assertion_id uuid, p_party text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'working'
AS $function$
DECLARE
    v_required_count BIGINT;
    v_missing_exact_count BIGINT;
    v_missing_anchor_count BIGINT;
    v_available TIMESTAMPTZ;
    v_recorded TIMESTAMPTZ;
BEGIN
    IF p_party = 'first_party' THEN
        WITH required_member AS (
            SELECT 'message'::TEXT AS member_kind, message.message_id AS member_id,
                   message.source_available_from
            FROM working.first_party_context_thread_realization_message link
            JOIN working.first_party_context_thread_message message
              ON message.thread_version_id = link.thread_version_id
             AND message.message_id = link.message_id
            WHERE link.realization_assertion_id = p_assertion_id AND link.required_for_realization
            UNION ALL
            SELECT 'source', source.id, source.source_available_from
            FROM working.first_party_context_thread_realization_source link
            JOIN working.first_party_context_thread_source source
              ON source.id = link.thread_source_id
            WHERE link.realization_assertion_id = p_assertion_id AND link.required_for_realization
        )
        SELECT count(*), count(*) FILTER (WHERE source_available_from IS NULL),
               CASE WHEN bool_or(source_available_from IS NULL) THEN NULL
                    ELSE max(source_available_from) END
          INTO v_required_count, v_missing_exact_count, v_available
        FROM required_member;
        SELECT count(*) INTO v_missing_anchor_count
        FROM (
            SELECT message.message_id
            FROM working.first_party_context_thread_realization_message link
            JOIN working.first_party_context_thread_message message
              ON message.thread_version_id = link.thread_version_id
             AND message.message_id = link.message_id
            WHERE link.realization_assertion_id = p_assertion_id
              AND link.required_for_realization AND message.source_available_from IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM context.first_party_thread_message_relative_time_anchor anchor_link
                  JOIN context.relative_time_anchor anchor ON anchor.id = anchor_link.anchor_id
                  WHERE anchor_link.thread_version_id = message.thread_version_id
                    AND anchor_link.message_id = message.message_id
                    AND anchor_link.link_role = 'primary_fallback'
                    AND anchor.review_state IN ('proposed', 'approved')
              )
            UNION ALL
            SELECT source.id
            FROM working.first_party_context_thread_realization_source link
            JOIN working.first_party_context_thread_source source ON source.id = link.thread_source_id
            WHERE link.realization_assertion_id = p_assertion_id
              AND link.required_for_realization AND source.source_available_from IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM context.first_party_thread_source_relative_time_anchor anchor_link
                  JOIN context.relative_time_anchor anchor ON anchor.id = anchor_link.anchor_id
                  WHERE anchor_link.thread_source_id = source.id
                    AND anchor_link.link_role = 'primary_fallback'
                    AND anchor.review_state IN ('proposed', 'approved')
              )
        ) missing_anchor;
        SELECT required_source_available_from INTO v_recorded
        FROM working.first_party_context_thread_realization_assertion WHERE id = p_assertion_id;
    ELSIF p_party = 'third_party' THEN
        WITH required_member AS (
            SELECT 'message'::TEXT AS member_kind, message.message_id AS member_id,
                   message.source_available_from
            FROM working.third_party_context_thread_realization_message link
            JOIN working.third_party_context_thread_message message
              ON message.thread_version_id = link.thread_version_id
             AND message.message_id = link.message_id
            WHERE link.realization_assertion_id = p_assertion_id AND link.required_for_realization
            UNION ALL
            SELECT 'source', source.id, source.source_available_from
            FROM working.third_party_context_thread_realization_source link
            JOIN working.third_party_context_thread_source source ON source.id = link.thread_source_id
            WHERE link.realization_assertion_id = p_assertion_id AND link.required_for_realization
        )
        SELECT count(*), count(*) FILTER (WHERE source_available_from IS NULL),
               CASE WHEN bool_or(source_available_from IS NULL) THEN NULL
                    ELSE max(source_available_from) END
          INTO v_required_count, v_missing_exact_count, v_available
        FROM required_member;
        SELECT count(*) INTO v_missing_anchor_count
        FROM (
            SELECT message.message_id
            FROM working.third_party_context_thread_realization_message link
            JOIN working.third_party_context_thread_message message
              ON message.thread_version_id = link.thread_version_id
             AND message.message_id = link.message_id
            WHERE link.realization_assertion_id = p_assertion_id
              AND link.required_for_realization AND message.source_available_from IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM context.third_party_thread_message_relative_time_anchor anchor_link
                  JOIN context.relative_time_anchor anchor ON anchor.id = anchor_link.anchor_id
                  WHERE anchor_link.thread_version_id = message.thread_version_id
                    AND anchor_link.message_id = message.message_id
                    AND anchor_link.link_role = 'primary_fallback'
                    AND anchor.review_state IN ('proposed', 'approved')
              )
            UNION ALL
            SELECT source.id
            FROM working.third_party_context_thread_realization_source link
            JOIN working.third_party_context_thread_source source ON source.id = link.thread_source_id
            WHERE link.realization_assertion_id = p_assertion_id
              AND link.required_for_realization AND source.source_available_from IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM context.third_party_thread_source_relative_time_anchor anchor_link
                  JOIN context.relative_time_anchor anchor ON anchor.id = anchor_link.anchor_id
                  WHERE anchor_link.thread_source_id = source.id
                    AND anchor_link.link_role = 'primary_fallback'
                    AND anchor.review_state IN ('proposed', 'approved')
              )
        ) missing_anchor;
        SELECT required_source_available_from INTO v_recorded
        FROM working.third_party_context_thread_realization_assertion WHERE id = p_assertion_id;
    ELSE
        RAISE EXCEPTION 'unknown context-thread party %', p_party;
    END IF;
    IF v_required_count = 0 OR v_missing_anchor_count <> 0
       OR v_recorded IS DISTINCT FROM v_available
       OR (v_missing_exact_count > 0 AND v_recorded IS NOT NULL) THEN
        RAISE EXCEPTION 'realization assertion availability must equal the greatest required source availability';
    END IF;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.validate_first_party_context_thread_version(p_version_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'working', 'context'
AS $function$
DECLARE
    v_version working.first_party_context_thread_version%ROWTYPE;
    v_message_count BIGINT;
    v_first TIMESTAMPTZ;
    v_last TIMESTAMPTZ;
    v_required_source_count BIGINT;
    v_missing_exact_count BIGINT;
    v_missing_anchor_count BIGINT;
    v_available TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_version FROM working.first_party_context_thread_version WHERE id = p_version_id;
    SELECT count(*), min(occurred_at), max(occurred_at)
      INTO v_message_count, v_first, v_last
    FROM working.first_party_context_thread_message WHERE thread_version_id = p_version_id;
    IF v_message_count = 0 OR (v_version.first_occurred_at, v_version.last_occurred_at)
       IS DISTINCT FROM (v_first, v_last) THEN
        RAISE EXCEPTION 'first-party thread bounds must equal its message occurred_at bounds';
    END IF;
    WITH required_member AS (
        SELECT 'message'::TEXT AS member_kind, message_id AS member_id, source_available_from
        FROM working.first_party_context_thread_message
        WHERE thread_version_id = p_version_id AND required_for_horizon
        UNION ALL
        SELECT 'source', id, source_available_from
        FROM working.first_party_context_thread_source
        WHERE thread_version_id = p_version_id AND required_for_horizon
    )
    SELECT count(*), count(*) FILTER (WHERE source_available_from IS NULL),
           CASE WHEN bool_or(source_available_from IS NULL) THEN NULL
                ELSE max(source_available_from) END
      INTO v_required_source_count, v_missing_exact_count, v_available
    FROM required_member;
    SELECT count(*) INTO v_missing_anchor_count
    FROM (
        SELECT membership.message_id
        FROM working.first_party_context_thread_message membership
        WHERE membership.thread_version_id = p_version_id
          AND membership.required_for_horizon
          AND membership.source_available_from IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM context.first_party_thread_message_relative_time_anchor link
              JOIN context.relative_time_anchor anchor ON anchor.id = link.anchor_id
              WHERE link.thread_version_id = membership.thread_version_id
                AND link.message_id = membership.message_id
                AND link.link_role = 'primary_fallback'
                AND anchor.review_state IN ('proposed', 'approved')
          )
        UNION ALL
        SELECT source.id
        FROM working.first_party_context_thread_source source
        WHERE source.thread_version_id = p_version_id
          AND source.required_for_horizon
          AND source.source_available_from IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM context.first_party_thread_source_relative_time_anchor link
              JOIN context.relative_time_anchor anchor ON anchor.id = link.anchor_id
              WHERE link.thread_source_id = source.id
                AND link.link_role = 'primary_fallback'
                AND anchor.review_state IN ('proposed', 'approved')
          )
    ) missing_anchor;
    IF v_required_source_count = 0 OR v_missing_anchor_count <> 0
       OR v_version.knowledge_available_from IS DISTINCT FROM v_available THEN
        RAISE EXCEPTION 'first-party knowledge availability must be the greatest required occurred_at availability';
    END IF;
    IF v_missing_exact_count > 0 AND v_version.knowledge_available_from IS NOT NULL THEN
        RAISE EXCEPTION 'first-party required NULL clocks prohibit an exact thread horizon';
    END IF;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.validate_message_projection()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE owner_count INTEGER;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('working.message_projection'));
  IF EXISTS (SELECT 1 FROM working.message_projection_route r
             JOIN working.normalized_record nr ON nr.id=r.normalized_record_id
             WHERE r.decision_state='approved' AND nr.record_type<>'message') THEN
    RAISE EXCEPTION 'MESSAGE_ROUTE_REQUIRES_MESSAGE_RECORD';
  END IF;
  IF EXISTS (
    SELECT 1 FROM working.message_projection_route r
    WHERE r.decision_state='approved' AND r.projection_kind='first_party'
      AND ((SELECT count(*) FROM working.message m WHERE m.derived_from_record_id=r.normalized_record_id)<>1
        OR EXISTS (SELECT 1 FROM working.third_party_message tm WHERE tm.normalized_record_id=r.normalized_record_id))) THEN
    RAISE EXCEPTION 'FIRST_PARTY_PROJECTION_CARDINALITY';
  END IF;
  IF EXISTS (SELECT 1 FROM working.message_projection_route
             WHERE decision_state='approved' AND projection_kind='acquired_third_party') THEN
    SELECT count(*) INTO owner_count FROM registry.person WHERE role_in_case='user';
    IF owner_count<>1 THEN RAISE EXCEPTION 'OWNER_IDENTITY_NOT_CONFIGURED'; END IF;
  END IF;
  IF EXISTS (
    SELECT 1 FROM working.message_projection_route r
    JOIN working.normalized_record nr ON nr.id=r.normalized_record_id
    LEFT JOIN working.third_party_message tm ON tm.normalized_record_id=r.normalized_record_id
    LEFT JOIN working.third_party_conversation tc ON tc.id=tm.conversation_id
    WHERE r.decision_state='approved' AND r.projection_kind='acquired_third_party'
      AND (tm.id IS NULL OR tc.review_status<>'approved' OR tc.case_id<>nr.case_id
        OR tc.source_artifact_id<>nr.artifact_id
        OR tm.occurred_at IS DISTINCT FROM nr.occurred_at
        OR tm.sender_raw IS NULL OR length(trim(tm.sender_raw))=0
        OR tm.sender_entity_id IS NULL
        OR (nr.attrs ? 'source_party_review_required'
            AND r.basis->>'source_party_review_resolved' IS DISTINCT FROM 'true')
        OR EXISTS (SELECT 1 FROM working.message m WHERE m.derived_from_record_id=r.normalized_record_id)
        OR (SELECT count(*) FROM working.third_party_message_participant p
            WHERE p.message_id=tm.id AND p.role='from')<>1
        OR NOT EXISTS (SELECT 1 FROM working.third_party_message_participant p
                       WHERE p.message_id=tm.id AND p.role IN ('to','cc','bcc','group'))
        OR EXISTS (SELECT 1 FROM working.third_party_message_participant p
                   WHERE p.message_id=tm.id AND p.entity_id IS NULL)
        OR NOT EXISTS (SELECT 1 FROM working.third_party_message_participant p
                       WHERE p.message_id=tm.id AND p.role='from' AND p.entity_id=tm.sender_entity_id)
        OR EXISTS (SELECT 1 FROM working.third_party_message_participant p
                   JOIN registry.person wp ON wp.id=p.entity_id
                   WHERE p.message_id=tm.id AND wp.role_in_case='user')
        OR NOT EXISTS (SELECT 1 FROM working.third_party_conversation_acquisition ca
                       JOIN evidence.acquisition a ON a.id=ca.acquisition_id
                       WHERE ca.conversation_id=tm.conversation_id
                         AND ca.approval_state='approved' AND a.acquired_at IS NOT NULL
                         AND a.asserted_by='human'))) THEN
    RAISE EXCEPTION 'ACQUIRED_THIRD_PARTY_PROJECTION_INVALID';
  END IF;
  RETURN NULL;
END $function$
;
CREATE OR REPLACE FUNCTION working.validate_realization_links()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1 FROM working.realization_event_record rer
    JOIN working.realization_event re ON re.id=rer.realization_event_id
    JOIN working.normalized_record nr ON nr.id=rer.normalized_record_id
    WHERE rer.case_id<>re.case_id OR rer.case_id<>nr.case_id) THEN
    RAISE EXCEPTION 'REALIZATION_LINK_CASE_MISMATCH';
  END IF;
  IF EXISTS (
    SELECT 1 FROM working.realization_event re
    WHERE re.approval_state='approved' AND re.trigger_record_id IS NULL
      AND NOT EXISTS (SELECT 1 FROM working.realization_event_record rer
                      WHERE rer.realization_event_id=re.id)) THEN
    RAISE EXCEPTION 'APPROVED_REALIZATION_REQUIRES_EVIDENCE_LINK';
  END IF;
  RETURN NULL;
END $function$
;
CREATE OR REPLACE FUNCTION working.validate_source_range_locator_subject(p_locator_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'context'
AS $function$
DECLARE
    v_subject_count BIGINT;
BEGIN
    SELECT (SELECT count(*) FROM context.source_object_range_locator WHERE source_range_locator_id = p_locator_id)
         + (SELECT count(*) FROM context.raw_record_range_locator WHERE source_range_locator_id = p_locator_id)
         + (SELECT count(*) FROM context.normalized_record_range_locator WHERE source_range_locator_id = p_locator_id)
      INTO v_subject_count;
    IF v_subject_count <> 1 THEN
        RAISE EXCEPTION 'source range locator requires exactly one typed subject link';
    END IF;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.validate_third_party_context_thread_version(p_version_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'working', 'context'
AS $function$
DECLARE
    v_version working.third_party_context_thread_version%ROWTYPE;
    v_message_count BIGINT;
    v_first TIMESTAMPTZ;
    v_last TIMESTAMPTZ;
    v_required_source_count BIGINT;
    v_missing_exact_count BIGINT;
    v_missing_anchor_count BIGINT;
    v_available TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_version FROM working.third_party_context_thread_version WHERE id = p_version_id;
    SELECT count(*), min(occurred_at), max(occurred_at)
      INTO v_message_count, v_first, v_last
    FROM working.third_party_context_thread_message WHERE thread_version_id = p_version_id;
    IF v_message_count = 0 OR (v_version.first_occurred_at, v_version.last_occurred_at)
       IS DISTINCT FROM (v_first, v_last) THEN
        RAISE EXCEPTION 'third-party thread bounds must equal its message occurred_at bounds';
    END IF;
    WITH required_member AS (
        SELECT 'message'::TEXT AS member_kind, message_id AS member_id, source_available_from
        FROM working.third_party_context_thread_message
        WHERE thread_version_id = p_version_id AND required_for_horizon
        UNION ALL
        SELECT 'source', id, source_available_from
        FROM working.third_party_context_thread_source
        WHERE thread_version_id = p_version_id AND required_for_horizon
    )
    SELECT count(*), count(*) FILTER (WHERE source_available_from IS NULL),
           CASE WHEN bool_or(source_available_from IS NULL) THEN NULL
                ELSE max(source_available_from) END
      INTO v_required_source_count, v_missing_exact_count, v_available
    FROM required_member;
    SELECT count(*) INTO v_missing_anchor_count
    FROM (
        SELECT membership.message_id
        FROM working.third_party_context_thread_message membership
        WHERE membership.thread_version_id = p_version_id
          AND membership.required_for_horizon
          AND membership.source_available_from IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM context.third_party_thread_message_relative_time_anchor link
              JOIN context.relative_time_anchor anchor ON anchor.id = link.anchor_id
              WHERE link.thread_version_id = membership.thread_version_id
                AND link.message_id = membership.message_id
                AND link.link_role = 'primary_fallback'
                AND anchor.review_state IN ('proposed', 'approved')
          )
        UNION ALL
        SELECT source.id
        FROM working.third_party_context_thread_source source
        WHERE source.thread_version_id = p_version_id
          AND source.required_for_horizon
          AND source.source_available_from IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM context.third_party_thread_source_relative_time_anchor link
              JOIN context.relative_time_anchor anchor ON anchor.id = link.anchor_id
              WHERE link.thread_source_id = source.id
                AND link.link_role = 'primary_fallback'
                AND anchor.review_state IN ('proposed', 'approved')
          )
    ) missing_anchor;
    IF v_required_source_count = 0 OR v_missing_anchor_count <> 0
       OR v_version.knowledge_available_from IS DISTINCT FROM v_available THEN
        RAISE EXCEPTION 'third-party knowledge availability must be the greatest required custody-backed availability';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM working.third_party_context_thread_source source
        WHERE source.thread_version_id = p_version_id
          AND NOT EXISTS (
              SELECT 1
              FROM working.third_party_context_thread_message membership
              JOIN working.third_party_message message ON message.id = membership.message_id
              WHERE membership.thread_version_id = p_version_id
                AND message.conversation_id = source.represented_conversation_id
          )
    ) THEN
        RAISE EXCEPTION 'third-party source represented conversation must belong to the same thread version';
    END IF;
    IF v_missing_exact_count > 0 AND v_version.knowledge_available_from IS NOT NULL THEN
        RAISE EXCEPTION 'third-party required NULL clocks prohibit an exact thread horizon';
    END IF;
END;
$function$
;
CREATE OR REPLACE FUNCTION working.visible_from(p_record_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$
  SELECT working.source_available_from(p_record_id);
$function$
;

-- ============ views, pass 2 ============
CREATE OR REPLACE VIEW analysis.vw_court_export AS
 SELECT id,
    case_id,
    exhibit_number,
    title,
    description,
    quote,
    context,
    evidence_type,
    evidence_date,
    date_precision,
    assertion_type,
    confidence,
    confidence_tier,
    is_authenticated,
    authentication_method,
    chain_of_custody,
    sensitivity_tier,
    redaction_status,
    source_id,
    file_node_id,
    evidence_hash_id,
    reviewed_by,
    reviewed_at
   FROM evidence.evidence_item ei
  WHERE safe_for_legal_use = true AND review_status = 'approved'::review_state AND (confidence_tier = ANY (ARRAY['high'::text, 'medium'::text])) AND is_hypothesis = false AND is_authenticated = true AND redaction_status <> 'required'::text AND sensitivity_tier <> 'sealed'::sensitivity_tier;
CREATE OR REPLACE VIEW analysis.vw_human_label_long AS
 SELECT conversation_key,
    seq,
    occurred_at,
    who,
    message_text,
    unnest(labels) AS label,
    is_clean,
    severity,
    notes
   FROM analysis.human_label
  WHERE cardinality(labels) > 0;
CREATE OR REPLACE VIEW analysis.vw_labeling_progress AS
 SELECT count(*) AS total_messages,
    count(*) FILTER (WHERE cardinality(labels) > 0 OR is_clean) AS labeled,
    count(*) FILTER (WHERE cardinality(labels) > 0) AS labeled_with_behavior,
    count(*) FILTER (WHERE is_clean) AS marked_clean,
    count(*) FILTER (WHERE cardinality(labels) = 0 AND is_clean IS NOT TRUE) AS remaining,
    round(100.0 * count(*) FILTER (WHERE cardinality(labels) > 0 OR is_clean)::numeric / NULLIF(count(*), 0)::numeric, 1) AS pct_done
   FROM analysis.human_label;
CREATE OR REPLACE VIEW analysis.vw_message_behavior AS
 SELECT m.id AS message_id,
    m.conversation_id,
    m.ts_utc,
    m.direction,
    m.has_behaviors,
    m.behavior_count,
    m.max_behavior_severity,
    count(pf.*) AS finding_count,
    count(pf.*) FILTER (WHERE pf.review_status = 'approved'::review_state) AS confirmed_count,
    bool_or(pf.category_id = 'threats'::citext) AS flag_threat_hypothesis,
    bool_or(pf.category_id = 'threats'::citext AND pf.review_status = 'approved'::review_state) AS flag_threat_confirmed,
    bool_or(pf.category_id = 'gaslighting'::citext) AS flag_gaslighting_hypothesis,
    bool_or(pf.category_id = 'minimizing'::citext) AS flag_minimizing_hypothesis,
    bool_or(pf.category_id = 'blame_shifting'::citext) AS flag_blame_hypothesis,
    array_agg(DISTINCT pf.category_id) FILTER (WHERE pf.category_id IS NOT NULL) AS categories
   FROM working.message m
     LEFT JOIN analysis.pattern_finding pf ON pf.subject_id = m.id AND pf.subject_type = 'message'::text
  GROUP BY m.id, m.conversation_id, m.ts_utc, m.direction, m.has_behaviors, m.behavior_count, m.max_behavior_severity;
CREATE OR REPLACE VIEW analysis.vw_open_tasks AS
 SELECT id,
    task_key,
    case_id,
    status,
    priority,
    priority_score,
    due_date,
    due_basis,
    human_action,
    human_action_kind,
    label_sensitivity,
    hitl_required,
    hitl_status,
    confidence_tier,
    is_hypothesis,
    ( SELECT count(*) AS count
           FROM analysis.task_dependency d
          WHERE d.depends_on = t.id AND (d.dep_kind = ANY (ARRAY['blocks'::text, 'prereq_of'::text]))) AS blocks_n,
    ( SELECT e.to_status
           FROM analysis.task_event e
          WHERE e.task_id = t.id
          ORDER BY e.ts DESC
         LIMIT 1) AS last_event
   FROM analysis.evidence_task t
  WHERE status <> ALL (ARRAY['closed_satisfied'::text, 'closed_unmet'::text, 'closed_overcome'::text, 'superseded'::text, 'archived'::text])
  ORDER BY priority, priority_score DESC NULLS LAST, due_date;
CREATE OR REPLACE VIEW evidence.vw_artifacts_without_claim AS
 SELECT s.id AS source_id,
    s.original_filename,
    s.source_type,
    s.byte_size,
    s.ingested_at,
    am.source_id IS NOT NULL AS has_metadata_row,
    ( SELECT count(*) AS count
           FROM evidence.vw_raw_all r
          WHERE r.source_id = s.id) AS raw_rows
   FROM evidence.source s
     LEFT JOIN evidence.artifact_metadata am ON am.source_id = s.id
  WHERE am.source_id IS NULL OR am.record_count_claimed IS NULL;
CREATE OR REPLACE VIEW evidence.vw_dropped_records AS
 SELECT j.id AS rejected_id,
    encode(j.source_sha256, 'hex'::text) AS h1,
    s.original_filename,
    ir.parser,
    ir.parser_version,
    ir.status AS run_status,
    j.record_index,
    j.element_tag,
    j.reason,
    j.reason_detail,
    j.content_hash,
    j.raw,
    j.created_at
   FROM raw.raw_rejected j
     JOIN evidence.ingest_run ir ON ir.id = j.ingest_run_id
     LEFT JOIN evidence.source s ON s.sha256 = j.source_sha256;
CREATE OR REPLACE VIEW evidence.vw_ingest_history AS
 SELECT id AS run_id,
    source_filename,
    status,
    parser,
    parser_version,
    runner,
    started_at,
    finished_at,
    EXTRACT(epoch FROM finished_at - started_at)::bigint AS duration_s,
    count_claimed,
    count_parsed,
    count_rejected,
    count_deduped,
    count_raw,
    count_spine,
    count_attestations,
    COALESCE(count_claimed, 0::bigint) - COALESCE(count_parsed, 0::bigint) AS claimed_minus_parsed,
    outcome_detail,
    notes
   FROM evidence.ingest_run ir
  ORDER BY started_at DESC;
CREATE OR REPLACE VIEW evidence.vw_raw_all AS
 SELECT 'evidence.raw_sms'::text AS raw_table,
    raw_sms.id,
    raw_sms.source_id,
    raw_sms.device_id,
    raw_sms.acquisition_id,
    raw_sms.medium,
    raw_sms.record_index,
    raw_sms.content_hash,
    raw_sms.parser_version,
    raw_sms.superseded_by,
    raw_sms.ingested_at
   FROM raw.raw_sms
UNION ALL
 SELECT 'evidence.raw_imessage'::text AS raw_table,
    raw_imessage.id,
    raw_imessage.source_id,
    raw_imessage.device_id,
    raw_imessage.acquisition_id,
    raw_imessage.medium,
    raw_imessage.record_index,
    raw_imessage.content_hash,
    raw_imessage.parser_version,
    raw_imessage.superseded_by,
    raw_imessage.ingested_at
   FROM raw.raw_imessage
UNION ALL
 SELECT 'evidence.raw_facebook'::text AS raw_table,
    raw_facebook.id,
    raw_facebook.source_id,
    raw_facebook.device_id,
    raw_facebook.acquisition_id,
    raw_facebook.medium,
    raw_facebook.record_index,
    raw_facebook.content_hash,
    raw_facebook.parser_version,
    raw_facebook.superseded_by,
    raw_facebook.ingested_at
   FROM raw.raw_facebook
UNION ALL
 SELECT 'evidence.raw_ai_chat'::text AS raw_table,
    raw_ai_chat.id,
    raw_ai_chat.source_id,
    raw_ai_chat.device_id,
    raw_ai_chat.acquisition_id,
    raw_ai_chat.medium,
    raw_ai_chat.record_index,
    raw_ai_chat.content_hash,
    raw_ai_chat.parser_version,
    raw_ai_chat.superseded_by,
    raw_ai_chat.ingested_at
   FROM raw.raw_ai_chat
UNION ALL
 SELECT 'evidence.raw_csv'::text AS raw_table,
    raw_csv.id,
    raw_csv.source_id,
    raw_csv.device_id,
    raw_csv.acquisition_id,
    raw_csv.medium,
    raw_csv.record_index,
    raw_csv.content_hash,
    raw_csv.parser_version,
    raw_csv.superseded_by,
    raw_csv.ingested_at
   FROM raw.raw_csv
UNION ALL
 SELECT 'evidence.raw_phone'::text AS raw_table,
    raw_phone.id,
    raw_phone.source_id,
    raw_phone.device_id,
    raw_phone.acquisition_id,
    raw_phone.medium,
    raw_phone.record_index,
    raw_phone.content_hash,
    raw_phone.parser_version,
    raw_phone.superseded_by,
    raw_phone.ingested_at
   FROM raw.raw_phone;
CREATE OR REPLACE VIEW evidence.vw_source_acquisition AS
 SELECT s.id AS source_id,
    s.original_filename,
    s.sha256,
    s.acquisition_source AS file_acquisition_source,
    s.acquisition_method AS file_acquisition_method,
    s.custodian AS file_custodian,
    s.acquired_at_utc AS file_acquired_at,
    s.provenance_tier,
    a.id AS acquisition_id,
    a.method AS event_method,
    a.authority AS event_authority,
    a.device_custodian AS event_custodian,
    a.acquired_at AS event_acquired_at,
    a.export_created_at,
    a.producible,
        CASE
            WHEN a.id IS NULL THEN 'no_acquisition_event'::text
            WHEN s.acquisition_method IS DISTINCT FROM a.method::text THEN 'METHOD_DIVERGES'::text
            WHEN s.acquired_at_utc IS NOT NULL AND a.acquired_at IS NOT NULL AND abs(EXTRACT(epoch FROM s.acquired_at_utc - a.acquired_at)) > 86400::numeric THEN 'ACQUIRED_AT_DIVERGES'::text
            ELSE 'consistent'::text
        END AS reconciliation_status
   FROM evidence.source s
     LEFT JOIN evidence.acquisition a ON a.id = s.acquisition_id;
CREATE OR REPLACE VIEW public.geography_columns AS
 SELECT current_database() AS f_table_catalog,
    n.nspname AS f_table_schema,
    c.relname AS f_table_name,
    a.attname AS f_geography_column,
    postgis_typmod_dims(a.atttypmod) AS coord_dimension,
    postgis_typmod_srid(a.atttypmod) AS srid,
    postgis_typmod_type(a.atttypmod) AS type
   FROM pg_class c,
    pg_attribute a,
    pg_type t,
    pg_namespace n
  WHERE t.typname = 'geography'::name AND a.attisdropped = false AND a.atttypid = t.oid AND a.attrelid = c.oid AND c.relnamespace = n.oid AND (c.relkind = ANY (ARRAY['r'::"char", 'v'::"char", 'm'::"char", 'f'::"char", 'p'::"char"])) AND NOT pg_is_other_temp_schema(c.relnamespace) AND has_table_privilege(c.oid, 'SELECT'::text);
CREATE OR REPLACE VIEW public.geometry_columns AS
 SELECT current_database()::character varying(256) AS f_table_catalog,
    n.nspname AS f_table_schema,
    c.relname AS f_table_name,
    a.attname AS f_geometry_column,
    COALESCE(postgis_typmod_dims(a.atttypmod), sn.ndims, 2) AS coord_dimension,
    COALESCE(NULLIF(postgis_typmod_srid(a.atttypmod), 0), sr.srid, 0) AS srid,
    replace(replace(COALESCE(NULLIF(upper(postgis_typmod_type(a.atttypmod)), 'GEOMETRY'::text), st.type, 'GEOMETRY'::text), 'ZM'::text, ''::text), 'Z'::text, ''::text)::character varying(30) AS type
   FROM pg_class c
     JOIN pg_attribute a ON a.attrelid = c.oid AND NOT a.attisdropped
     JOIN pg_namespace n ON c.relnamespace = n.oid
     JOIN pg_type t ON a.atttypid = t.oid
     LEFT JOIN ( SELECT s.connamespace,
            s.conrelid,
            s.conkey,
            (regexp_match(s.consrc, 'geometrytype\(\w+\)\s*=\s*''(\w+)'''::text, 'i'::text))[1] AS type
           FROM ( SELECT pg_constraint.connamespace,
                    pg_constraint.conrelid,
                    pg_constraint.conkey,
                    pg_get_constraintdef(pg_constraint.oid) AS consrc
                   FROM pg_constraint) s
          WHERE s.consrc ~* 'geometrytype\(\w+\)\s*=\s*''\w+'''::text) st ON st.connamespace = n.oid AND st.conrelid = c.oid AND (a.attnum = ANY (st.conkey))
     LEFT JOIN ( SELECT s.connamespace,
            s.conrelid,
            s.conkey,
            (regexp_match(s.consrc, 'ndims\(\w+\)\s*=\s*(\d+)'::text, 'i'::text))[1]::integer AS ndims
           FROM ( SELECT pg_constraint.connamespace,
                    pg_constraint.conrelid,
                    pg_constraint.conkey,
                    pg_get_constraintdef(pg_constraint.oid) AS consrc
                   FROM pg_constraint) s
          WHERE s.consrc ~* 'ndims\(\w+\)\s*=\s*\d+'::text) sn ON sn.connamespace = n.oid AND sn.conrelid = c.oid AND (a.attnum = ANY (sn.conkey))
     LEFT JOIN ( SELECT s.connamespace,
            s.conrelid,
            s.conkey,
            (regexp_match(s.consrc, 'srid\(\w+\)\s*=\s*(\d+)'::text, 'i'::text))[1]::integer AS srid
           FROM ( SELECT pg_constraint.connamespace,
                    pg_constraint.conrelid,
                    pg_constraint.conkey,
                    pg_get_constraintdef(pg_constraint.oid) AS consrc
                   FROM pg_constraint) s
          WHERE s.consrc ~* 'srid\(\w+\)\s*=\s*\d+'::text) sr ON sr.connamespace = n.oid AND sr.conrelid = c.oid AND (a.attnum = ANY (sr.conkey))
  WHERE (c.relkind = ANY (ARRAY['r'::"char", 'v'::"char", 'm'::"char", 'f'::"char", 'p'::"char"])) AND NOT c.relname = 'raster_columns'::name AND t.typname = 'geometry'::name AND NOT pg_is_other_temp_schema(c.relnamespace) AND has_table_privilege(c.oid, 'SELECT'::text);
CREATE OR REPLACE VIEW public.pg_stat_statements AS
 SELECT userid,
    dbid,
    toplevel,
    queryid,
    query,
    plans,
    total_plan_time,
    min_plan_time,
    max_plan_time,
    mean_plan_time,
    stddev_plan_time,
    calls,
    total_exec_time,
    min_exec_time,
    max_exec_time,
    mean_exec_time,
    stddev_exec_time,
    rows,
    shared_blks_hit,
    shared_blks_read,
    shared_blks_dirtied,
    shared_blks_written,
    local_blks_hit,
    local_blks_read,
    local_blks_dirtied,
    local_blks_written,
    temp_blks_read,
    temp_blks_written,
    shared_blk_read_time,
    shared_blk_write_time,
    local_blk_read_time,
    local_blk_write_time,
    temp_blk_read_time,
    temp_blk_write_time,
    wal_records,
    wal_fpi,
    wal_bytes,
    wal_buffers_full,
    jit_functions,
    jit_generation_time,
    jit_inlining_count,
    jit_inlining_time,
    jit_optimization_count,
    jit_optimization_time,
    jit_emission_count,
    jit_emission_time,
    jit_deform_count,
    jit_deform_time,
    parallel_workers_to_launch,
    parallel_workers_launched,
    stats_since,
    minmax_stats_since
   FROM pg_stat_statements(true) pg_stat_statements(userid, dbid, toplevel, queryid, query, plans, total_plan_time, min_plan_time, max_plan_time, mean_plan_time, stddev_plan_time, calls, total_exec_time, min_exec_time, max_exec_time, mean_exec_time, stddev_exec_time, rows, shared_blks_hit, shared_blks_read, shared_blks_dirtied, shared_blks_written, local_blks_hit, local_blks_read, local_blks_dirtied, local_blks_written, temp_blks_read, temp_blks_written, shared_blk_read_time, shared_blk_write_time, local_blk_read_time, local_blk_write_time, temp_blk_read_time, temp_blk_write_time, wal_records, wal_fpi, wal_bytes, wal_buffers_full, jit_functions, jit_generation_time, jit_inlining_count, jit_inlining_time, jit_optimization_count, jit_optimization_time, jit_emission_count, jit_emission_time, jit_deform_count, jit_deform_time, parallel_workers_to_launch, parallel_workers_launched, stats_since, minmax_stats_since);
CREATE OR REPLACE VIEW public.pg_stat_statements_info AS
 SELECT dealloc,
    stats_reset
   FROM pg_stat_statements_info() pg_stat_statements_info(dealloc, stats_reset);
CREATE OR REPLACE VIEW public.vw_event_evidence_package AS
 SELECT e.event_id,
    e.serial_id,
    e.title,
    e.event_type,
    ta.valid_earliest,
    ta.valid_latest,
    ta.valid_point,
    ta.ts_utc,
    ta.certainty,
    ta.assertion_type,
    ta.confidence,
    ta.disclosure_horizon,
        CASE
            WHEN ta.certainty = 'exact'::precision_class AND ta.confidence::numeric >= 0.80 THEN 'HIGH'::text
            WHEN ta.certainty = 'approximate'::precision_class AND ta.confidence::numeric >= 0.60 THEN 'MEDIUM'::text
            ELSE 'LOW'::text
        END AS temporal_confidence_tier,
    e.mcl_relevance,
    e.source_artifact_id,
    ta.reasoning
   FROM analysis.timeline_event e
     JOIN analysis.time_assertion ta ON ta.event_id = e.event_id AND upper_inf(ta.sys_period)
  WHERE e.safe_for_legal_use AND NOT e.requires_human_review AND NOT ta.requires_human_review;
CREATE OR REPLACE VIEW public.vw_llm_cost_rollup AS
 SELECT date_trunc('day'::text, created_at) AS day,
    tool_name,
    tool_category,
    count(*) AS calls,
    sum(cost_estimate) AS total_cost,
    sum(runtime_ms) AS total_ms
   FROM ops.tool_call_ledger
  GROUP BY (date_trunc('day'::text, created_at)), tool_name, tool_category
  ORDER BY (date_trunc('day'::text, created_at)) DESC, (sum(cost_estimate)) DESC NULLS LAST;
CREATE OR REPLACE VIEW public.vw_prompt_performance AS
 SELECT pr.prompt_name,
    pr.prompt_version,
    count(l.*) AS uses,
    avg(l.runtime_ms)::numeric(10,1) AS avg_runtime_ms,
    sum(l.cost_estimate) AS total_cost,
    count(*) FILTER (WHERE l.errors IS NOT NULL) AS error_count
   FROM prompt_registry pr
     LEFT JOIN ops.tool_call_ledger l ON l.prompt_version = pr.prompt_version
  GROUP BY pr.prompt_name, pr.prompt_version;
CREATE OR REPLACE VIEW timeline.vw_projection_expected_manifest AS
 SELECT g.id AS generation_id,
    g.sequence,
    g.status,
    g.membership_hash,
    g.content_hash,
    m.stable_member_id,
    m.opensearch_doc_id,
    m.member_content_hash,
    m.authority_state,
    m.change_class
   FROM timeline.timeline_projection_generation g
     JOIN timeline.timeline_projection_member m ON m.generation_id = g.id
  ORDER BY g.sequence, m.stable_member_id;
CREATE OR REPLACE VIEW timeline.vw_projection_receipt_current AS
 SELECT DISTINCT ON (generation_id, member_id, sink) generation_id,
    member_id,
    sink,
    status,
    attempt,
    expected_content_hash,
    observed_content_hash,
    opensearch_doc_id,
    opensearch_index,
    error_code,
    error_digest,
    started_at,
    finished_at,
    observed_at,
    id AS receipt_id,
    created_at
   FROM timeline.timeline_projection_receipt
  ORDER BY generation_id, member_id, sink, created_at DESC, id DESC;
CREATE OR REPLACE VIEW working.content_chunk_current_classification AS
 SELECT DISTINCT ON (chunk_id) chunk_id,
    id AS decision_id,
    decision_version,
    lane,
    review_state,
    classifier_id,
    classifier_version,
    confidence,
    reviewed_by,
    reviewed_at
   FROM analysis.content_chunk_classification_decision
  WHERE review_state = ANY (ARRAY['system_initial'::text, 'human_approved'::text])
  ORDER BY chunk_id, decision_version DESC, created_at DESC, id DESC;
CREATE OR REPLACE VIEW working.current_provenance AS
 SELECT DISTINCT ON (source_raw_table, source_raw_id) id,
    source_raw_table,
    source_raw_id,
    revision,
    occurred_at,
    export_created_at,
    acquired_at,
    ingested_at,
    realized_at,
    realized_at_source,
    realized_at_state,
    acquisition_method,
    acquisition_authority,
    source_device,
    device_custodian,
    custody_transferred_at,
    acquisition_notes,
    asserted_by,
    asserted_by_kind,
    producible,
    created_at
   FROM working.source_provenance
  ORDER BY source_raw_table, source_raw_id, revision DESC;
CREATE OR REPLACE VIEW working.knowledge_gap AS
 SELECT source_raw_table,
    source_raw_id,
    occurred_at,
    realized_at,
    realized_at - occurred_at AS gap,
    acquisition_method,
    acquisition_authority,
    producible
   FROM working.current_provenance
  WHERE occurred_at IS NOT NULL AND realized_at IS NOT NULL;
CREATE OR REPLACE VIEW working.review_queue AS
 SELECT 'entity'::text AS kind,
    e.id,
    e.created_at,
    e.confidence,
    e.source_raw_table,
    e.source_raw_id,
    e.name AS label,
    e.review_state
   FROM working.candidate_entity e
  WHERE e.review_state = 'pending'::text
UNION ALL
 SELECT 'fact'::text AS kind,
    f.id,
    f.created_at,
    f.confidence,
    f.source_raw_table,
    f.source_raw_id,
    f.statement AS label,
    f.review_state
   FROM working.candidate_fact f
  WHERE f.review_state = 'pending'::text
UNION ALL
 SELECT 'event'::text AS kind,
    v.id,
    v.created_at,
    v.confidence,
    v.source_raw_table,
    v.source_raw_id,
    v.summary AS label,
    v.review_state
   FROM working.candidate_event v
  WHERE v.review_state = 'pending'::text;
CREATE OR REPLACE VIEW working.vw_derivation_lineage AS
 SELECT nr.id AS record_id,
    nr.record_type,
    nr.occurred_at,
    "left"(nr.content, 120) AS content_preview,
    nr.derived_from_raw_table AS raw_table,
    nr.derived_from_raw_id AS raw_id,
    nr.deriver_version,
    nr.derived_at,
    r.parser_version,
    r.record_index,
    r.content_hash,
    r.superseded_by AS raw_superseded_by,
    s.id AS source_id,
    s.original_filename,
    encode(s.sha256, 'hex'::text) AS h1,
    a.id AS acquisition_id,
    a.method AS acquisition_method,
    a.authority AS acquisition_authority,
    nr.acquired_at,
    nr.export_created_at,
    nr.ingested_at
   FROM working.normalized_record nr
     LEFT JOIN evidence.vw_raw_all r ON r.id = nr.derived_from_raw_id
     LEFT JOIN evidence.source s ON s.id = r.source_id
     LEFT JOIN evidence.acquisition a ON a.id = nr.acquisition_id;
CREATE OR REPLACE VIEW working.vw_horizon_atom AS
 SELECT nr.case_id,
    'normalized_record'::text AS atom_kind,
    nr.id AS atom_id,
    nr.id AS normalized_record_id,
    NULL::uuid AS realization_event_id,
    nr.occurred_at,
    working.source_available_from(nr.id) AS visible_from,
    nr.disclosure_tier,
    nr.content,
    nr.attrs
   FROM working.normalized_record nr
UNION ALL
 SELECT re.case_id,
    'realization_event'::text AS atom_kind,
    re.id AS atom_id,
    NULL::uuid AS normalized_record_id,
    re.id AS realization_event_id,
    re.realized_at AS occurred_at,
    re.realized_at AS visible_from,
    'discovered'::text AS disclosure_tier,
    COALESCE(re.notes, ''::text) AS content,
    jsonb_build_object('kind', re.kind, 'evidence_pointer', re.evidence_pointer) AS attrs
   FROM working.realization_event re
  WHERE re.approval_state = 'approved'::text;
CREATE OR REPLACE VIEW working.vw_message_imessage AS
 SELECT m.id AS message_id,
    m.conversation_id,
    m.ts_utc,
    m.direction,
    m.is_read,
    m.external_id AS apple_guid,
    m.platform_attrs ->> 'service'::text AS service,
    m.platform_attrs ->> 'date_read'::text AS date_read,
    m.platform_attrs ->> 'date_edited'::text AS date_edited,
    m.platform_attrs ->> 'thread_originator_guid'::text AS reply_to_guid,
    m.raw_ts,
    nr.content
   FROM working.message m
     LEFT JOIN working.normalized_record nr ON nr.id = m.id
  WHERE m.platform = 'imessage'::text;
CREATE OR REPLACE VIEW working.vw_message_sms AS
 SELECT m.id AS message_id,
    m.conversation_id,
    m.ts_utc,
    m.direction,
    m.is_read,
    m.sender_e164,
    m.recipient_e164,
    m.delivery_status,
    m.status_code,
    m.is_blocked,
    m.platform_attrs ->> 'service_center'::text AS service_center,
    m.platform_attrs ->> 'sub_id'::text AS sub_id,
    m.platform_attrs ->> 'contact_name'::text AS contact_name,
    m.raw_ts,
    nr.content
   FROM working.message m
     LEFT JOIN working.normalized_record nr ON nr.id = m.id
  WHERE m.platform = 'sms'::text;
CREATE OR REPLACE VIEW working.vw_record_attestations AS
 SELECT r.id AS record_id,
    r.occurred_at,
    count(esr.link_id) AS attestation_count,
    count(*) FILTER (WHERE esr.agrees IS FALSE) AS disagreeing_count,
    array_agg(DISTINCT esr.medium) FILTER (WHERE esr.medium IS NOT NULL) AS mediums,
    array_agg(DISTINCT esr.raw_table) FILTER (WHERE esr.raw_table IS NOT NULL) AS raw_tables,
    array_agg(DISTINCT esr.source_id) FILTER (WHERE esr.source_id IS NOT NULL) AS source_ids,
        CASE
            WHEN count(*) FILTER (WHERE esr.agrees IS FALSE) > 0 THEN 'CONFLICTED'::text
            WHEN count(esr.link_id) > 1 THEN 'corroborated'::text
            WHEN count(esr.link_id) = 1 THEN 'single_source'::text
            ELSE 'unlinked'::text
        END AS attestation_status
   FROM working.normalized_record r
     LEFT JOIN working.event_source_record esr ON esr.record_id = r.id
  GROUP BY r.id, r.occurred_at;
CREATE OR REPLACE VIEW working.vw_record_disclosure AS
 SELECT id,
    occurred_at,
    acquired_at,
    realized_at,
    disclosure_tier AS disclosure_tier_asserted,
        CASE
            WHEN realized_at IS NULL AND acquired_at IS NULL THEN NULL::text
            WHEN realized_at IS NOT NULL AND occurred_at IS NOT NULL AND realized_at > (occurred_at + '30 days'::interval) THEN 'hindsight'::text
            WHEN acquired_at IS NOT NULL AND occurred_at IS NOT NULL AND acquired_at > (occurred_at + '30 days'::interval) THEN 'discovered'::text
            ELSE 'contemporaneous'::text
        END AS disclosure_tier_derived,
        CASE
            WHEN realized_at IS NOT NULL AND occurred_at IS NOT NULL THEN realized_at - occurred_at
            ELSE NULL::interval
        END AS realization_lag
   FROM working.normalized_record r;
CREATE OR REPLACE VIEW working.vw_spine_horizon AS
 SELECT id,
    artifact_id,
    record_type,
    source,
    conversation_id,
    role,
    participants,
    content,
    occurred_at,
    knowledge_time,
    disclosure_tier,
    attrs,
    created_at,
    conversation_ref,
    ts_precision,
    sensitivity_tier,
    data_tier,
    review_status,
    safe_for_legal_use,
    provenance_id,
    export_created_at,
    acquired_at,
    ingested_at,
    realized_at,
    realized_evidence,
    acquisition_id,
    device_id,
    sender_entity_id,
    derived_from_raw_table,
    derived_from_raw_id,
    deriver_version,
    derived_at,
    attestation_count,
    case_id,
    domain,
    topic_tags,
    knowledge_actor,
    ontology_version,
    source_record_key,
    source_content_sha256,
    sender,
    recipients,
    message_corpus
   FROM working.normalized_record r
  WHERE case_id = COALESCE(NULLIF(current_setting('app.case_id'::text, true), ''::text), 'primary'::text) AND working.horizon_record_visible(id, NULLIF(current_setting('app.horizon'::text, true), ''::text)::timestamp with time zone, NULLIF(current_setting('app.base_version'::text, true), ''::text)) AND (NULLIF(current_setting('app.horizon'::text, true), ''::text) IS NULL OR disclosure_tier <> 'hindsight'::text);
CREATE OR REPLACE VIEW working.vw_walk_base_version_input AS
 SELECT nr.case_id,
    'normalized_record'::text AS input_kind,
    nr.id::text AS input_key,
    jsonb_build_object('content_sha256', encode(COALESCE(nr.source_content_sha256, digest(convert_to(nr.content, 'UTF8'::name), 'sha256'::text)), 'hex'::text), 'occurred_at', nr.occurred_at, 'disclosure_tier', nr.disclosure_tier) AS input_payload
   FROM working.normalized_record nr
UNION ALL
 SELECT nr.case_id,
    'message_projection_route'::text AS input_kind,
    r.normalized_record_id::text AS input_key,
    jsonb_build_object('projection_kind', r.projection_kind, 'decision_state', r.decision_state, 'approved_at', r.approved_at, 'deriver_version', r.deriver_version) AS input_payload
   FROM working.message_projection_route r
     JOIN working.normalized_record nr ON nr.id = r.normalized_record_id
UNION ALL
 SELECT tc.case_id,
    'third_party_acquisition'::text AS input_kind,
    ca.id::text AS input_key,
    jsonb_build_object('conversation_id', ca.conversation_id, 'acquisition_id', ca.acquisition_id, 'approval_state', ca.approval_state, 'acquired_at', a.acquired_at) AS input_payload
   FROM working.third_party_conversation_acquisition ca
     JOIN working.third_party_conversation tc ON tc.id = ca.conversation_id
     JOIN evidence.acquisition a ON a.id = ca.acquisition_id
UNION ALL
 SELECT re.case_id,
    'realization_event'::text AS input_kind,
    re.id::text AS input_key,
    jsonb_build_object('kind', re.kind, 'realized_at', re.realized_at, 'approval_state', re.approval_state, 'trigger_record_id', re.trigger_record_id) AS input_payload
   FROM working.realization_event re
UNION ALL
 SELECT rer.case_id,
    'realization_event_record'::text AS input_kind,
    (rer.realization_event_id::text || ':'::text) || rer.normalized_record_id::text AS input_key,
    jsonb_build_object('realization_event_id', rer.realization_event_id, 'normalized_record_id', rer.normalized_record_id) AS input_payload
   FROM working.realization_event_record rer;
CREATE OR REPLACE VIEW working.vw_walk_contamination AS
 SELECT s.walk_run_id,
    s.step_no,
    s.horizon_at,
    ret.record_id,
    ret.store,
    ret.was_used,
    working.source_available_from(ret.record_id) AS visible_from
   FROM working.walk_step s
     JOIN working.walk_step_retrieval ret ON ret.walk_step_id = s.id
  WHERE working.source_available_from(ret.record_id) IS NULL OR s.horizon_at IS NOT NULL AND working.source_available_from(ret.record_id) > s.horizon_at
UNION ALL
 SELECT s.walk_run_id,
    s.step_no,
    s.horizon_at,
    NULL::uuid AS record_id,
    ret.store,
    ret.was_used,
    re.realized_at AS visible_from
   FROM working.walk_step s
     JOIN working.walk_step_realization_retrieval ret ON ret.walk_step_id = s.id
     JOIN working.realization_event re ON re.id = ret.realization_event_id
  WHERE re.approval_state <> 'approved'::text OR s.horizon_at IS NOT NULL AND re.realized_at > s.horizon_at;
CREATE OR REPLACE VIEW working.vw_walk_delta AS
 SELECT s.walk_run_id,
    s.step_no,
    s.horizon_at,
    s.record_id AS focal_record_id,
    s.conclusion AS believed_then,
    nr.content AS actual,
    nr.occurred_at,
    working.source_available_from(s.record_id) AS actual_known_from,
        CASE
            WHEN rz.first_realized_at IS NOT NULL AND nr.occurred_at IS NOT NULL THEN rz.first_realized_at - nr.occurred_at
            ELSE NULL::interval
        END AS realization_lag,
    rz.first_realized_at
   FROM working.walk_step s
     JOIN working.normalized_record nr ON nr.id = s.record_id
     LEFT JOIN LATERAL ( SELECT min(re.realized_at) AS first_realized_at
           FROM working.realization_event_record rer
             JOIN working.realization_event re ON re.id = rer.realization_event_id
          WHERE rer.normalized_record_id = s.record_id AND re.approval_state = 'approved'::text) rz ON true
  WHERE s.record_id IS NOT NULL;

-- ============ comments ============
COMMENT ON TABLE analysis.chunk_classification IS 'DRAFT classification output of the n8n/Temporal pipeline (D-068). Versioned drafts only — classifier_version stamps provenance; re-runs add rows under new versions; low confidence lands as review_state=unreviewed (never a flag). No evidence-status effect.';
COMMENT ON TABLE analysis.content_chunk_classification_decision IS 'Context-first append-only reviewed classification history. It deliberately has no evidence lane.';
COMMENT ON TABLE analysis.graphrag_comparison_join IS 'Joins the two lane receipts for one stage. Both lanes must cite the same manifest_digest; no automatic fusion of results (D-093).';
COMMENT ON TABLE analysis.graphrag_comparison_run IS 'D-093 side-by-side evaluation run. horizon_at pins the pre-ranking horizon boundary both lanes share.';
COMMENT ON TABLE analysis.graphrag_eligibility_manifest IS 'The single PostgreSQL-authorized eligibility set both lanes receive. Sealing computes membership_digest; both lanes cite the same digest or the comparison is invalid.';
COMMENT ON TABLE analysis.graphrag_lane_candidate IS 'Per-lane candidates carrying the PG source coordinate (source_version_id, normalized_record_id, text_unit_id) so two lanes can be diffed on provenance without first resolving entity identity.';
COMMENT ON TABLE analysis.human_label IS 'Prompt-example set: labeled messages for few-shot prompting / model training. Deliberately UNLINKED from live tables (owner ruling 2026-08-24 — linking caused problems every test). Stripped to message+label essentials by 0032; full-fidelity pre-strip copy = analysis.human_label_gold.';
COMMENT ON TABLE analysis.human_label_gold IS 'Dependency-free archive of the owner-authored ground-truth labels. NO foreign keys by design: on 2026-08-01 human_label.message_id was found to be BOTH the primary key AND an ON DELETE CASCADE FK to analysis.message, so a routine clear of the message tables would have deleted all 1918 rows outright. This table cannot be reached by any cascade. legacy_message_id is a plain UUID column, deliberately not a reference.';
COMMENT ON TABLE analysis.knowledge_evidence_promotion IS 'Append-only, idempotent ledger for promoting a canonical Knowledge result into a default-unsafe evidence_item. Retrieval IDs are supporting metadata; normalized record, custody hash, source/file, and run references are the authoritative provenance.';
COMMENT ON TABLE analysis.matter_knowledge_partition IS 'Explicit partition-to-matter/default-case mapping created by an authorized application caller.';
COMMENT ON VIEW analysis.vw_message_behavior IS 'One-click behavior filters for UI. *_hypothesis = a finding exists (unreviewed OK); *_confirmed = human-approved only. Replaces the old containsThreat/Blame booleans WITHOUT bypassing the court-safety review gate.';
COMMENT ON TABLE canon.canonical_table IS 'The canon boundary. The spine accepts proposals only against rows of tables registered here. Registration is an owner act. current_generation is the per-table staleness anchor: proposals record it at filing, adoption checks it.';
COMMENT ON TABLE canon.change_application IS 'The receipt. prior_values preserves what canon said before the change, so no correction ever silently destroys the original reading — history by recording, not by immutability guards (D-110).';
COMMENT ON TABLE canon.change_proposal IS 'The universal write path to canon. Nothing authors canonical rows directly: extractors, the Workbench, graph reconciliation, agents and humans all file here. Rejected proposals are retained and marked, never deleted.';
COMMENT ON TABLE canon.recompute_queue IS 'One row per (applied change x downstream target). Consumers poll their target, mark claimed/done. This is the leg that forces derived work to recalculate after re-canonicalization. It ships with the spine so it cannot become another consumer-less outbox.';
COMMENT ON TABLE context.first_party_thread_version_relative_time_anchor IS 'Typed first-party fallback link. Primary availability remains occurred_at, never screenshot/export metadata.';
COMMENT ON TABLE context.hash_receipt IS 'R02 context integrity fingerprints plus normalized reproducibility digests. These rows are not custody H1/H2/H3.';
COMMENT ON TABLE context.normalization_lineage IS 'Real raw-to-normalized M:N lineage through FKs. Replaces any format-table/id polymorphic pointer.';
COMMENT ON TABLE context.raw_record_identity IS 'The sole persistence home for every parser-emitted ordered span. Parsed records and rejected, malformed, unknown, unparsed, and envelope spans are all rows here; no orphan span table is permitted.';
COMMENT ON TABLE context.relative_time_anchor IS 'Append-only reviewed fallback placement when an authoritative primary timestamp is unavailable. JSON payloads are presentation only; typed link tables are authority.';
COMMENT ON TABLE context.source_range_locator IS 'Canonical typed half-open [start,end) UTF-8-byte or Unicode-codepoint source locator. locator_projection is non-authoritative.';
COMMENT ON TABLE context.third_party_thread_version_relative_time_anchor IS 'Typed third-party fallback link. Primary availability remains custody-backed acquisition; capture/export clocks never backdate it.';
COMMENT ON TABLE context.uiw_preview_binding IS 'Opaque browser handle bound server-side to the UIW request, source reference, and Temporal identity.';
COMMENT ON TABLE context.uiw_source_context_revision IS 'Append-only operator assertions kept separate from immutable preview-only source observations. Preview hashes are not custody hashes. Each revision is actor-bound and receipt-addressed.';
COMMENT ON TABLE evidence.acquisition IS 'One row per acquisition event (device/export). HITL-authored, append-only, non-producible by default. Referenced by evidence.source; never duplicated per message.';
COMMENT ON TABLE evidence.artifact_metadata IS 'Wide, cold, one row per artifact. Records filesystem / embedded / derived metadata layers separately and never collapses them. Precedence for export time: embedded > filename > filesystem. Filesystem times are observations — they do not survive copying or cloud sync.';
COMMENT ON TABLE evidence.evidence_item IS 'THE promotion target. A row here is promoted evidence: exhibit_number, is_authenticated, chain_of_custody, safe_for_legal_use, anchored to raw via evidence_hash_id/normalized_record_id. Written only via a canon.change_proposal of kind promote, after owner ruling. Part of the litigation loop: finding -> evidence_task -> evidence_item -> factor_citation -> legal_timeline_event.';
COMMENT ON TABLE evidence.ingest_run IS 'One row per ingest ATTEMPT, written outside the ingest transaction so failed and rolled-back runs survive. The count_* columns are the funnel: claimed -> parsed -> rejected/deduped -> raw -> spine -> attestations. Added 2026-08-01 after a parser dropped 516 records with no trace.';
COMMENT ON VIEW evidence.vw_artifacts_without_claim IS 'Artifacts that cannot be reconciled because nothing recorded what they claim about themselves - either no artifact_metadata row exists, or its record_count_claimed is NULL. Every row here is a blind spot.';
COMMENT ON VIEW evidence.vw_dropped_records IS 'Everything a parser refused, joined to the run that refused it. An empty result means nothing was dropped - which is only believable if vw_reconciliation also says RECONCILED.';
COMMENT ON VIEW evidence.vw_ingest_history IS 'Every ingest attempt including failures and rollbacks. A rolled_back row with a populated funnel is the most useful diagnostic in the system: it shows exactly which stage stopped agreeing.';
COMMENT ON VIEW evidence.vw_raw_all IS 'Every raw row across all six per-format raw tables, restricted to the columns they share. The tables stay separate on purpose; this view exists because "how many raw records does this artifact have" is a cross-format question.';
COMMENT ON VIEW evidence.vw_source_acquisition IS 'Reconciles the PER-FILE acquisition columns on evidence.source (live, written by custody.py at ingest) against the PER-EVENT evidence.acquisition row. These are different grains, not duplicates: one export session or device handoff covers many files. reconciliation_status flags divergence; no_acquisition_event means the file predates the acquisition intake form and needs one.';
COMMENT ON TABLE ops.audit_ledger IS 'ADR-0047 / D-042: ONE append-only, hash-chained ledger of every decision, action, modification, and READ. server/core/audit.py::record() is the sole writer. No raw case content — hashes and references only.';
COMMENT ON TABLE ops.workflow_run_review_action IS 'Append-only operator decisions attached to a durable workflow report. Original stage outcomes are never rewritten; corrections and overrides are new actions.';
COMMENT ON TABLE public.app_setting IS 'Versionable key/value config (clustering thresholds, etc.).';
COMMENT ON TABLE public.canon_registry IS 'Every algorithm/recipe that produces durable artifacts, as data with test vectors. NEVER change a recipe in place — add a new canon_name version and mark the old one superseded.';
COMMENT ON TABLE public.platform_consolidation_receipt_claim IS 'One immutable claim per receipt. The primary key serializes verified binding against supersession, including concurrent transactions.';
COMMENT ON TABLE raw.raw_ai_chat IS 'RAW per-source layer for ai_chat. The ONLY insert target for this format. Verbatim and never edited; spine and projection are derived from it. Dedup on (device, medium, content) only - a screenshot of the same message is a separate attestation, not a duplicate.';
COMMENT ON TABLE raw.raw_csv IS 'RAW per-source layer for csv. The ONLY insert target for this format. Verbatim and never edited; spine and projection are derived from it. Dedup on (device, medium, content) only - a screenshot of the same message is a separate attestation, not a duplicate.';
COMMENT ON TABLE raw.raw_facebook IS 'RAW per-source layer for facebook. The ONLY insert target for this format. Verbatim and never edited; spine and projection are derived from it. Dedup on (device, medium, content) only - a screenshot of the same message is a separate attestation, not a duplicate.';
COMMENT ON TABLE raw.raw_imessage IS 'RAW per-source layer for imessage. The ONLY insert target for this format. Verbatim and never edited; spine and projection are derived from it. Dedup on (device, medium, content) only - a screenshot of the same message is a separate attestation, not a duplicate.';
COMMENT ON TABLE raw.raw_phone IS 'RAW per-source layer for phone. The ONLY insert target for this format. Verbatim and never edited; spine and projection are derived from it. Dedup on (device, medium, content) only - a screenshot of the same message is a separate attestation, not a duplicate.';
COMMENT ON TABLE raw.raw_rejected IS 'Every record a parser refused, stored verbatim with the reason. A dropped record is an absence and cannot be queried after the fact - it must be written at the moment of refusal. dedup_duplicate_in_source rows are the losing side of a raw dedup collapse and are how "raw < parsed" is PROVEN rather than assumed.';
COMMENT ON TABLE raw.raw_sms IS 'RAW per-source layer for sms. The ONLY insert target for this format. Verbatim and never edited; spine and projection are derived from it. Dedup on (device, medium, content) only - a screenshot of the same message is a separate attestation, not a duplicate.';
COMMENT ON TABLE reference.format_resolver IS 'AI-assisted field-mapping registry for unknown message-export formats. mappings[].method records HOW each field was resolved (exact/fuzzy/content/ai) — court-defensibility: a human can see which columns were deterministic vs model-inferred. Seed dict + cascade ported from schema_resolver.py.';
COMMENT ON TABLE reference.lexicon_sync IS 'External lexicon import provenance. HurtLex pinned v1.2 (valeriobasile/hurtlex); level conservative|inclusive; isCustom terms protected on resync (enforced in importer, not here).';
COMMENT ON TABLE reference.topic_code IS 'Human-readable conversation topic codes (6-char). Seed = topic_detector.py TOPIC_MAPPING.';
COMMENT ON TABLE registry.court_case IS 'Identity registry: legal cases. Moved from analysis (0057) — a case is the coordinate system analysis happens IN, not a conclusion produced by it.';
COMMENT ON TABLE registry.device IS 'Identity registry: physical devices evidence was acquired from. Moved from working (0057) — a purge of working must never delete the registry of phones the evidence came from.';
COMMENT ON TABLE registry.matter IS 'Identity registry: matters. Moved from analysis (0057), same reasoning as court_case.';
COMMENT ON TABLE timeline.event_candidate IS 'Any-context event proposal (ADR-0060). CANDIDATE authority only -- D-082: an AI-chat-derived row is a lead, never evidence. A correction is a NEW row (new extraction_run_id), never an edit to this one -- see the append-only trigger below.';
COMMENT ON TABLE timeline.event_candidate_relative_time_anchor IS 'Typed append-only relative-time link for event-candidate temporal roles. Corrections are new anchor versions/links, never JSON authority.';
COMMENT ON TABLE timeline.event_candidate_source_range IS 'Independent event-extraction provenance over the same immutable source_version/range primitive; it never carves content out of or depends on chunks.';
COMMENT ON TABLE timeline.timeline_collection IS 'D-072 single-case timeline collection(s). Curated membership set -- authority stays with the member row it points at, never copied here.';
COMMENT ON TABLE timeline.timeline_member IS 'Curated timeline membership (ADR-0060). Retains candidate vs evidence-approved authority via member_authority; never copies the source row''s own content. An edit to an evidence_approved member is out of this table''s scope -- it becomes a WP-F02 amendment candidate elsewhere, never an UPDATE here.';
COMMENT ON TABLE timeline.timeline_projection_activation IS 'Append-only activation attestation log (R09 Phase 7). Current active generation = the row with the latest activated_at; never mutate a prior row to "deactivate" it.';
COMMENT ON TABLE timeline.timeline_projection_generation IS 'Immutable, sealed Timesketch export generation (ADR-0060/D-085). sequence is the monotonically comparable outbox-style cursor R09 walks; idempotency_key makes rebuilding from an unchanged member set a no-op instead of a duplicate.';
COMMENT ON TABLE timeline.timeline_projection_member IS 'One immutable row per member per sealed generation (ADR-0060 canonical mapping). stable_member_id/opensearch_doc_id are deterministic functions of source_member_id, never of the generation, so rebuild/replay always targets the same logical OpenSearch document.';
COMMENT ON TABLE timeline.timeline_projection_receipt IS 'Append-only delivery/read-back receipt (R09 common-receipt shape). A current-status view is derived below -- rows here are never updated, a new attempt/observation is a new row.';
COMMENT ON VIEW timeline.vw_projection_expected_manifest IS 'R09/WP-H01 expected-manifest read: ordered (generation, member) rows with the hashes a reconciliation run diffs against OpenSearch read-back observations.';
COMMENT ON VIEW timeline.vw_projection_receipt_current IS 'Latest receipt per (generation, member, sink) -- the derived current-status read, not a source of truth (the append-only receipt rows are).';
COMMENT ON TABLE working.chat_conversation IS 'PER-SOURCE conversation: one AI-chat export''s conversation. Vocabulary ruling D-116: "conversation" = per-source; "thread" = cross-platform human conversation. Never mixed.';
COMMENT ON TABLE working.content_chunk IS 'THE chunk model (D-116). chat_chunk and normalized_record_chunk are deleted. Hash column convention: content_sha256; "content_hash" is banned.';
COMMENT ON TABLE working.content_chunk_generation IS 'Version-pinned derived chunk manifest. Reruns create new generations; sealed/aborted generations are immutable.';
COMMENT ON TABLE working.content_chunk_projection IS 'Fresh-ingest projection state for content_chunk (successor to chat_chunk_projection, 0058). Re-projection after an approved canon change is canon.recompute_queue''s job — deliberately separate processes.';
COMMENT ON TABLE working.content_chunk_source_span IS 'Same-source ordered chunk membership referencing the typed context.source_range_locator half-open primitive.';
COMMENT ON TABLE working.context_archive IS 'CONTEXT-tier record of a whole chat-export archive (owner 2026-08-12: process the zip as a whole unit). Separate from the evidence spine (no evidence FK). See server/analysis/chat_archive.py + sql/0021.';
COMMENT ON TABLE working.context_asset IS 'CONTEXT-tier index of generated docs/code/images from a chat-export archive; bytes in R2 (r2_key), small text inline. Option B: NOT the evidence-tier artifact_registry (CONTEXT-never-EVIDENCE boundary). content_hash UNIQUE = idempotent materialization.';
COMMENT ON TABLE working.context_record IS 'PG source of truth for AI-chat CONTEXT ingest (owner ruling 2026-08-12: PG first, change-detection projects to Weaviate). Standalone by design — NO evidence FK, referenced by NO evidence surface — which is the CONTEXT-never-EVIDENCE boundary (owner 2026-08-01). *_synced_at NULL = pending projection. See server/analysis/context_chat_ingest.py + ADR-0051.';
COMMENT ON TABLE working.extraction_run IS 'One extraction pass. Every candidate FKs here so a bad model version can be traced and its output re-reviewed or discarded wholesale.';
COMMENT ON TABLE working.first_party_context_thread IS 'THE cross-platform first-party thread model: one human conversation across SMS+iMessage+Facebook+... The winner of the conversation war (D-116). working.conversation and conversation_group are deleted; do not rebuild parallel models.';
COMMENT ON VIEW working.knowledge_gap IS 'occurred_at vs realized_at. The gap between what was true and when it was understood is the evidence of manipulation, not a discrepancy to reconcile.';
COMMENT ON TABLE working.promotion IS 'Every crossing of the human gate, labelled by which analysis pass it feeds: as_lived (Graphiti, keyed on realized_at), hindsight (Semantica/Neo4j, keyed on occurred_at), or consolidated (SurrealDB). Revocations are recorded, not deleted.';
COMMENT ON TABLE working.record_visible_from IS 'Materialized projection of working.visible_from (ADR-0045 §A) — the FAST path for the spine view. Sole writer = the derivation-engine refresher (W1.4 grants; pg_advisory_lock F13). A cached row is trusted only when its base_version matches app.base_version; otherwise the predicate recomputes from authored state. NULL source availability always denies. ';
COMMENT ON VIEW working.review_queue IS 'Everything awaiting human judgement, lowest-confidence first is the intended read: ORDER BY confidence NULLS FIRST, created_at.';
COMMENT ON TABLE working.source_provenance IS 'Append-only revisions of the six clocks and the acquisition block for one source row. Never UPDATE — a correction is a new revision. Provenance may only be asserted by a human (asserted_by_kind is CHECKed to human).';
COMMENT ON TABLE working.third_party_context_thread IS 'Stable cross-source/cross-platform acquired-third-party human thread identity. Owner participation is structurally rejected.';
COMMENT ON TABLE working.third_party_context_thread_source IS 'One immutable representation assertion per source version/version. Screenshots, OCR, native exports and device captures coexist; none is collapsed or selected as canonical.';
COMMENT ON TABLE working.third_party_conversation IS 'PER-SOURCE conversation from an acquired third-party export. See D-116 vocabulary ruling.';
COMMENT ON TABLE working.third_party_conversation_acquisition IS 'Reviewed link from a derived third-party conversation to an authored human acquisition event; acquired_at gates raw-source availability.';
COMMENT ON VIEW working.vw_derivation_lineage IS 'Every spine record traced back to the raw row it came from, whatever format that was, the artifact it came from, and how that artifact was acquired. A record with a NULL raw_id has no lineage and should not exist.';
COMMENT ON VIEW working.vw_message_imessage IS 'iMessage typed view. date_read/date_edited/service/reply_to_guid populate only after a chat.db re-export (current HTML export lacks them — see extracted-code-sweep-ADDENDUM.md §4).';
COMMENT ON VIEW working.vw_message_sms IS 'SMS-Backup&Restore fields as typed columns from platform_attrs.';
COMMENT ON VIEW working.vw_record_attestations IS 'Every source attesting each spine record. attestation_status: CONFLICTED (an attestation disagrees — a finding), corroborated (multiple independent sources), single_source, unlinked. Multiple mediums for one message is expected and valuable.';
COMMENT ON VIEW working.vw_record_disclosure IS 'Authoritative disclosure tier, derived from the clocks. disclosure_tier_asserted is the parse-time hint (parsers hardcode contemporaneous and cannot know better). realization_lag = realized_at - occurred_at is the as-lived gap.';
COMMENT ON VIEW working.vw_spine_horizon IS 'Spine filtered by the ADR-0045 §A horizon clock (visible_from), NOT the superseded knowledge_time. SET app.case_id / app.horizon / app.actor first. app.horizon unset/empty = hindsight (whole case incl. hindsight-tagged rows); set = ignorant agent at that cutoff (excludes hindsight-tagged + anything whose source_available_from is after the cutoff). Uses a base-version-pinned materialized fast path and fails closed for NULL availability. Repointed 2026-08-14 (0028); old knowledge_time predicate retired from the view.';
COMMENT ON VIEW working.vw_walk_base_version_input IS 'Deterministically ordered inputs for a walk base-version hash, including visibility-bearing projection, acquisition, and realization decisions.';
COMMENT ON VIEW working.vw_walk_contamination IS 'ADR-0045 §A contamination detector: a record retrieved at a step whose visible_from(record_id) > the step horizon_at was knowable only later — the ignorant agent saw a future fact. Non-empty here = the delta is silently corrupted. Uses visible_from (the §A clock), NOT the superseded knowledge_time.';
COMMENT ON TABLE working.walk_checkpoint IS 'Healthy checkpoints are resumable. Failure seals are immutable diagnostic snapshots and never resume; create rewalk_of_id for a clean rewalk.';
COMMENT ON TABLE working.walk_run IS 'ADR-0045 §B DERIVED pass materialization: one agent executing one pass over a case at a pinned base_version. A pass is a knowledge horizon bound to an agent (canon §1), not a table. DERIVED — never hand-authored; the refresher (server/evidence/derivation.py) is the SOLE writer (pg_advisory_lock F13 + W1.4 grants). Re-derivation at the same base_version MUST reproduce the identical hash chain. Append-only: a new base_version is a NEW run.';
COMMENT ON TABLE working.walk_step IS 'ADR-0045 §B: one checkpoint in a walk_run. As-lived walks append the newly-visible slice per step and chain-hash it (prev_hash -> prior corpus_hash; step 1 prev_hash = run.genesis_hash). corpus_hash attests to the visible slice; the chain proves the walk was not tampered with. Re-derivation at the same base_version reproduces the identical chain. DERIVED — refresher is sole writer.';
COMMENT ON TABLE working.walk_step_retrieval IS 'What a walk_step retrieved: record, store, rank, score, and whether the agent used it. Feeds vw_walk_contamination (retrieved a record whose visible_from > the step horizon) and the delta provenance. DERIVED — refresher is sole writer.';
