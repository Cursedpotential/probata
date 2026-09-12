// Package postgres implements the PostgreSQL-hosted DuckDB row-stream
// boundary. Queries read shared object storage and return source-native rows;
// the Activity writes those rows to the standard immutable parser bundle.
// This repository never inserts raw records directly.
package postgres

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/Cursedpotential/probata/engine/activities"
	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// eltDuckDBQuoteTag is the dollar-quote tag wrapping the inner DuckDB SQL
// text passed to duckdb.query(). A distinctive tag (rather than bare "$$")
// avoids collision with any "$$" that could appear inside a pathological
// source URL.
const eltDuckDBQuoteTag = "elt_duckdb_sql"

// StructuredELTRepository implements activities.StructuredELTRowRepository.
type StructuredELTRepository struct {
	acquire func(context.Context) (structuredELTSession, error)
}

// structuredELTSession is a leased PostgreSQL connection. pg_duckdb keeps
// extension load state on that backend session, so Webbed must be loaded and
// the DuckDB query must execute through the same lease. A transaction is not
// used: the R2 read can be slow and must not hold an open PostgreSQL
// transaction while it streams.
type structuredELTSession interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
	Query(context.Context, string, ...any) (pgx.Rows, error)
	QueryRow(context.Context, string, ...any) pgx.Row
	Release()
}

// NewStructuredELTRepository constructs a repository. db must reach a
// PostgreSQL instance with pg_duckdb installed and an R2/S3 secret already
// provisioned (server.core.session.ensure_duckdb_r2_secret at API startup,
// or server.api.runtime_support.ensure_duckdb_r2_secret); this repository
// never provisions a secret itself.
func NewStructuredELTRepository(pool *pgxpool.Pool) (*StructuredELTRepository, error) {
	if pool == nil {
		return nil, errors.New("postgres structured elt repository: database is required")
	}
	return newStructuredELTRepository(func(ctx context.Context) (structuredELTSession, error) {
		return pool.Acquire(ctx)
	}), nil
}

func newStructuredELTRepository(acquire func(context.Context) (structuredELTSession, error)) *StructuredELTRepository {
	return &StructuredELTRepository{acquire: acquire}
}

// OpenStructuredELTRows implements activities.StructuredELTRowRepository.
// It resolves the canonical acquisition locator from context.source.source_key
// because a retained file:// copy belongs to the worker host and is not
// necessarily visible inside PostgreSQL. Current R2 locators are translated to
// DuckDB's s3:// filesystem after workflow/source ownership is proven.
func (r *StructuredELTRepository) OpenStructuredELTRows(
	ctx context.Context, req proffer.StageRequest, format activities.StructuredELTFormat,
) (activities.StructuredELTRowReader, error) {
	if strings.TrimSpace(req.RequestID) == "" || req.SourceVersionRef == "" {
		return nil, errors.New("structured elt row query requires request and source version references")
	}
	sourceID, err := uuid.Parse(string(req.SourceVersionRef))
	if err != nil {
		return nil, fmt.Errorf("structured elt source version reference: %w", err)
	}
	originalRef := req.Refs["original"]
	if strings.TrimSpace(string(originalRef)) == "" {
		return nil, errors.New("structured elt row query requires original reference")
	}
	originalID, err := uuid.Parse(string(originalRef))
	if err != nil {
		return nil, fmt.Errorf("structured elt original reference: %w", err)
	}
	if r.acquire == nil {
		return nil, errors.New("structured elt row query requires a PostgreSQL session acquirer")
	}
	session, err := r.acquire(ctx)
	if err != nil {
		return nil, fmt.Errorf("acquire structured elt PostgreSQL session: %w", err)
	}
	releaseSession := true
	defer func() {
		if releaseSession {
			session.Release()
		}
	}()

	var sourceKey, workflowID, sourceStatus, declaredFormat string
	if err := session.QueryRow(ctx, `
		SELECT source.source_key, version.workflow_id, version.status, version.declared_format
		FROM context.source_version version
		JOIN context.source source ON source.id = version.source_id
		WHERE version.id = $1::uuid AND version.original_object_id = $2::uuid`,
		sourceID, originalID,
	).Scan(&sourceKey, &workflowID, &sourceStatus, &declaredFormat); err != nil {
		return nil, fmt.Errorf("resolve structured elt source locator: %w", err)
	}
	if workflowID != req.RequestID || sourceStatus != "retained" {
		return nil, errors.New("structured elt source is not retained by this workflow")
	}
	if declaredFormat != req.DeclaredFormat {
		return nil, errors.New("structured elt declared format does not match retained source")
	}
	sourceURL, err := duckDBSourceURL(sourceKey)
	if err != nil {
		return nil, err
	}
	if structuredELTRequiresWebbed(format) {
		if err := ensureWebbedLoaded(ctx, session); err != nil {
			return nil, err
		}
	}
	innerSQL, err := structuredELTQuery(format, sourceURL)
	if err != nil {
		return nil, err
	}
	query := fmt.Sprintf(
		`SELECT stored_bytes, native_fields, native_metadata FROM duckdb.query($%[1]s$%[2]s$%[1]s$) AS elt`,
		eltDuckDBQuoteTag, innerSQL,
	)
	rows, err := session.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("query DuckDB structured rows: %w", err)
	}
	releaseSession = false
	return &structuredELTRows{rows: rows, release: session.Release}, nil
}

func structuredELTRequiresWebbed(format activities.StructuredELTFormat) bool {
	return format == activities.StructuredELTFormatSMSXML
}

// ensureWebbedLoaded performs an explicit, idempotent load and then verifies
// the extension from DuckDB itself. It intentionally runs on the exact same
// leased PostgreSQL connection that will execute read_xml; a global autoload
// flag cannot prove per-session readiness for a community extension.
func ensureWebbedLoaded(ctx context.Context, session structuredELTSession) error {
	if _, err := session.Exec(ctx, `SELECT duckdb.load_extension('webbed')`); err != nil {
		return fmt.Errorf("load DuckDB Webbed extension on extraction session: %w", err)
	}
	var loaded bool
	if err := session.QueryRow(ctx, `
		SELECT loaded
		FROM duckdb.query($webbed_status$
			SELECT loaded FROM duckdb_extensions() WHERE extension_name = 'webbed'
		$webbed_status$) AS extension_status`).Scan(&loaded); err != nil {
		return fmt.Errorf("verify DuckDB Webbed extension on extraction session: %w", err)
	}
	if !loaded {
		return errors.New("DuckDB Webbed extension is installed but not loaded on extraction session")
	}
	return nil
}

type structuredELTRows struct {
	rows    pgx.Rows
	release func()
	closed  bool
}

func (r *structuredELTRows) Next(ctx context.Context) (activities.StructuredELTRow, error) {
	if err := ctx.Err(); err != nil {
		return activities.StructuredELTRow{}, err
	}
	if !r.rows.Next() {
		if err := r.rows.Err(); err != nil {
			_ = r.Close()
			return activities.StructuredELTRow{}, err
		}
		_ = r.Close()
		return activities.StructuredELTRow{}, io.EOF
	}
	var storedBytes, nativeFields, nativeMetadata string
	if err := r.rows.Scan(&storedBytes, &nativeFields, &nativeMetadata); err != nil {
		return activities.StructuredELTRow{}, err
	}
	return activities.StructuredELTRow{
		StoredBytes: []byte(storedBytes), NativeFields: []byte(nativeFields),
		NativeMetadata: []byte(nativeMetadata),
	}, nil
}

func (r *structuredELTRows) Close() error {
	if r.closed {
		return nil
	}
	r.closed = true
	r.rows.Close()
	if r.release != nil {
		r.release()
	}
	return nil
}

// duckDBSourceURL maps only locators that the PostgreSQL-hosted DuckDB can
// resolve. upload:// and retained worker-local file:// references fail closed;
// callers must first retain the source at a shared object-store locator.
func duckDBSourceURL(sourceKey string) (string, error) {
	trimmed := strings.TrimSpace(sourceKey)
	if strings.Contains(trimmed, "$"+eltDuckDBQuoteTag+"$") {
		return "", errors.New("structured elt source locator contains the reserved DuckDB quote tag")
	}
	switch {
	case strings.HasPrefix(trimmed, "r2://"):
		return "s3://" + strings.TrimPrefix(trimmed, "r2://"), nil
	case strings.HasPrefix(trimmed, "s3://"), strings.HasPrefix(trimmed, "https://"):
		return trimmed, nil
	default:
		return "", fmt.Errorf("structured elt source locator %q is not PostgreSQL/DuckDB-readable", sourceKey)
	}
}

// structuredELTQuery returns one query with the exact three-column wire shape
// consumed by structuredELTRows. Each template preserves source-native data in
// stored_bytes/native_metadata and projects the common native fields needed by
// the existing generic normalizer. No template writes a database table.
func structuredELTQuery(format activities.StructuredELTFormat, sourceURL string) (string, error) {
	if strings.TrimSpace(sourceURL) == "" {
		return "", errors.New("structured elt requires a non-empty DuckDB source url")
	}
	url := strings.ReplaceAll(sourceURL, "'", "''")
	switch format {
	case activities.StructuredELTFormatCSV:
		return fmt.Sprintf(`
			WITH source_rows AS (
				SELECT to_json(row_value)::VARCHAR AS raw_json
				FROM read_csv_auto('%s', all_varchar=true) AS row_value
			)
			SELECT raw_json AS stored_bytes,
				json_object('record_kind', 'row', 'body', raw_json)::VARCHAR AS native_fields,
				json_object('duckdb_template', 'csv_v1', 'source_row', raw_json::JSON)::VARCHAR AS native_metadata
			FROM source_rows`, url), nil
	case activities.StructuredELTFormatNDJSON:
		return fmt.Sprintf(`
			WITH source_rows AS (
				SELECT to_json(row_value)::VARCHAR AS raw_json
				FROM read_json_auto('%s', format='newline_delimited') AS row_value
			)
			SELECT raw_json AS stored_bytes,
				json_object('record_kind', 'object', 'body', raw_json)::VARCHAR AS native_fields,
				json_object('duckdb_template', 'ndjson_v1', 'source_row', raw_json::JSON)::VARCHAR AS native_metadata
			FROM source_rows`, url), nil
	case activities.StructuredELTFormatSMSXML:
		return fmt.Sprintf(`
			WITH source_rows AS (
				SELECT 'sms' AS source_kind, to_json(row_value)::JSON AS source_row
				FROM read_xml('%[1]s', record_element := 'sms', all_varchar := true) AS row_value
				UNION ALL
				SELECT 'mms' AS source_kind, to_json(row_value)::JSON AS source_row
				FROM read_xml('%[1]s', record_element := 'mms', all_varchar := true) AS row_value
			), projected AS (
				SELECT *,
					json_extract_string(source_row, '$."@address"') AS address,
					json_extract_string(source_row, '$."@type"') AS message_type,
					json_extract_string(source_row, '$."@date"') AS date_ms,
					coalesce(
						nullif(json_extract_string(source_row, '$."@body"'), 'null'),
						json_extract_string(source_row, '$.parts.part[0]."@text"'),
						json_extract_string(source_row, '$.parts.part."@text"'),
						''
					) AS body
				FROM source_rows
			)
			SELECT source_row::VARCHAR AS stored_bytes,
				json_object(
					'record_kind', 'message', 'body', body,
					'sender', CASE WHEN message_type = '2' THEN 'self' ELSE address END,
					'recipients', CASE WHEN message_type = '2' THEN json_array(address) ELSE json_array('self') END,
					'participants', json_array('self', address)
				)::VARCHAR AS native_fields,
				json_object(
					'duckdb_template', 'sms_xml_v1', 'source_kind', source_kind,
					'date_ms', date_ms, 'source_row', source_row
				)::VARCHAR AS native_metadata
			FROM projected
			ORDER BY try_cast(date_ms AS BIGINT), source_kind`, url), nil
	case activities.StructuredELTFormatChatGPTJSON:
		return fmt.Sprintf(`
			WITH source_document AS (
				SELECT content::JSON AS document FROM read_text('%s')
			), conversations AS (
				SELECT try_cast(conversation.key AS BIGINT) AS conversation_index,
					conversation.value AS conversation
				FROM source_document, json_each(document) AS conversation
			), nodes AS (
				SELECT conversation_index, conversation, node.key AS node_id,
					json_extract(node.value, '$.message') AS message
				FROM conversations, json_each(json_extract(conversation, '$.mapping')) AS node
			), messages AS (
				SELECT *, json_extract_string(message, '$.author.role') AS role,
					coalesce(json_extract_string(message, '$.content.parts[0]'), '') AS body,
					coalesce(
						try_cast(json_extract_string(message, '$.create_time') AS DOUBLE),
						try_cast(json_extract_string(conversation, '$.create_time') AS DOUBLE)
					) AS created_at
				FROM nodes WHERE json_type(message) = 'OBJECT'
			)
			SELECT message::VARCHAR AS stored_bytes,
				json_object(
					'record_kind', 'message', 'body', body, 'sender', role,
					'participants', json_array(role)
				)::VARCHAR AS native_fields,
				json_object(
					'duckdb_template', 'chatgpt_json_array_v1',
					'conversation_index', conversation_index,
					'conversation_id', json_extract_string(conversation, '$.id'),
					'conversation_title', json_extract_string(conversation, '$.title'),
					'node_id', node_id, 'created_at', created_at
				)::VARCHAR AS native_metadata
			FROM messages WHERE length(trim(body)) > 0
			ORDER BY conversation_index, created_at, node_id`, url), nil
	case activities.StructuredELTFormatIMessageText:
		return fmt.Sprintf(`
			WITH source_document AS (
				SELECT regexp_split_to_array(content, '\r?\n\r?\n+') AS record_blocks
				FROM read_text('%s')
			), blocks AS (
				SELECT generate_subscripts(record_blocks, 1) AS block_index,
					unnest(record_blocks) AS raw_block
				FROM source_document
			), parsed AS (
				SELECT *, regexp_split_to_array(raw_block, '\r?\n') AS lines
				FROM blocks WHERE length(trim(raw_block)) > 0
			), projected AS (
				SELECT *,
					CASE WHEN array_length(lines) >= 2 AND length(trim(list_extract(lines, 2))) > 0
						THEN trim(list_extract(lines, 2)) ELSE 'system' END AS sender,
					CASE WHEN array_length(lines) >= 3
						THEN array_to_string(list_slice(lines, 3, array_length(lines)), '\n')
						ELSE regexp_replace(raw_block, '^[^\r\n]*[AP]M\s*', '') END AS body
				FROM parsed
			)
			SELECT raw_block AS stored_bytes,
				json_object(
					'record_kind', 'message', 'body', trim(body),
					'sender', CASE WHEN lower(sender) IN ('me', 'you') THEN 'self' ELSE sender END,
					'participants', CASE WHEN lower(sender) IN ('me', 'you')
						THEN json_array('self') ELSE json_array('self', sender) END
				)::VARCHAR AS native_fields,
				json_object(
					'duckdb_template', 'imessage_text_v1', 'block_index', block_index,
					'raw_timestamp', regexp_extract(raw_block, '^([^\r\n]+?[AP]M)', 1),
					'sender_label', sender
				)::VARCHAR AS native_metadata
			FROM projected ORDER BY block_index`, url), nil
	default:
		return "", fmt.Errorf("structured elt format %q has no query template", format)
	}
}
