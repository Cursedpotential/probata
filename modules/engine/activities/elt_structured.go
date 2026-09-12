// Package activities implements the DuckDB-backed structured extraction
// Activity. DuckDB replaces only execute_parser_activity for formats it owns:
// it emits the same immutable parser bundle consumed by the existing raw,
// normalize, lineage, and verification stages. It never writes raw rows.
package activities

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/Cursedpotential/probata/engine/parser"
	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/stagegraph"
)

// StructuredELTFormat identifies one bounded DuckDB query template.
type StructuredELTFormat string

const (
	StructuredELTFormatCSV          StructuredELTFormat = "csv"
	StructuredELTFormatNDJSON       StructuredELTFormat = "ndjson"
	StructuredELTFormatSMSXML       StructuredELTFormat = "sms_xml"
	StructuredELTFormatChatGPTJSON  StructuredELTFormat = "chatgpt_json_array"
	StructuredELTFormatIMessageText StructuredELTFormat = "imessage_text"
)

const (
	// These distinct Temporal names let Proffer route an exact format to the
	// DuckDB implementation without colliding with the decoder Activities.
	SelectStructuredELTActivityName  = proffer.SelectStructuredELTActivityName
	ExecuteStructuredELTActivityName = proffer.ExecuteStructuredELTActivityName

	// The selection receipt and raw-generation manifest must identify the
	// implementation that actually produced the bundle.
	StructuredELTParserID      = "duckdb_structured_elt"
	StructuredELTParserVersion = "1.0.0"
)

var structuredELTDecisionRefs = [...]string{
	"handler_recommendation",
	"handler_decision",
	"handler_validation",
	"detected_format",
	"content_signature",
	"handler_compatibility",
}

// StructuredELTActivities implements the ExecuteStructuredELT Activity body.
// Attempt is injectable for tests and defaults to one; a Temporal worker
// binds it to activity.GetInfo(ctx).Attempt like every other Activities
// struct in this package (see NewStructuredELTActivities in register.go).
type StructuredELTActivities struct {
	Rows    StructuredELTRowRepository
	Store   ParserActivityStore
	Attempt Attempt
}

func (a StructuredELTActivities) validateStore() error {
	if a.Store == nil {
		return errors.New("structured elt activities: parser store is required")
	}
	return nil
}

func (a StructuredELTActivities) validateExecute() error {
	if err := a.validateStore(); err != nil {
		return err
	}
	if a.Rows == nil {
		return errors.New("structured elt activities: row repository is required")
	}
	return nil
}

func (a StructuredELTActivities) attempt(ctx context.Context) int32 {
	if a.Attempt == nil {
		return 1
	}
	attempt := a.Attempt(ctx)
	if attempt < 1 {
		return 1
	}
	return attempt
}

// StructuredELTRow is one source-native record emitted by a bounded DuckDB
// query template. It becomes a standard parser.RawRecordEnvelope before it
// leaves this Activity; DuckDB never writes raw tables directly.
type StructuredELTRow struct {
	StoredBytes    []byte
	NativeFields   json.RawMessage
	NativeMetadata json.RawMessage
	RecordStatus   parser.RecordStatus
	StatusReason   string
}

func (r StructuredELTRow) validate(expectedTemplate string) error {
	if r.StoredBytes == nil {
		return errors.New("structured elt row requires an exact stored byte value")
	}
	status := r.RecordStatus
	if status == "" {
		status = parser.StatusParsed
	}
	if err := status.Validate(); err != nil {
		return err
	}
	if status != parser.StatusParsed && strings.TrimSpace(r.StatusReason) == "" {
		return fmt.Errorf("structured elt row status %q requires a reason", status)
	}
	objects := make(map[string]map[string]any, 2)
	for name, value := range map[string]json.RawMessage{
		"native fields": r.NativeFields, "native metadata": r.NativeMetadata,
	} {
		var decoded any
		if len(value) == 0 || !json.Valid(value) || json.Unmarshal(value, &decoded) != nil {
			return fmt.Errorf("structured elt row %s must be a valid JSON object", name)
		}
		object, ok := decoded.(map[string]any)
		if !ok {
			return fmt.Errorf("structured elt row %s must be a JSON object", name)
		}
		objects[name] = object
	}
	if actual, ok := objects["native metadata"]["duckdb_template"].(string); !ok || actual != expectedTemplate {
		return fmt.Errorf("structured elt row template %q does not match pinned template %q", actual, expectedTemplate)
	}
	return nil
}

// StructuredELTRowReader streams query output so the Activity never
// materializes a complete source in Go or Temporal history.
type StructuredELTRowReader interface {
	Next(context.Context) (StructuredELTRow, error)
	Close() error
}

// StructuredELTRowRepository owns only DuckDB extraction. Bundle persistence
// and execute-parser receipts remain on ParserActivityStore.
type StructuredELTRowRepository interface {
	OpenStructuredELTRows(context.Context, proffer.StageRequest, StructuredELTFormat) (StructuredELTRowReader, error)
}

// StructuredELTFormatForDeclaredFormat maps source signatures to explicit
// templates. Unknown formats fail closed rather than falling into a catch-all
// query or running both DuckDB and a decoder.
func StructuredELTFormatForDeclaredFormat(declared string) (StructuredELTFormat, error) {
	switch strings.TrimSpace(declared) {
	case "csv":
		return StructuredELTFormatCSV, nil
	case "ndjson", "jsonl":
		return StructuredELTFormatNDJSON, nil
	case "smsbackuprestore_xml":
		return StructuredELTFormatSMSXML, nil
	case "chatgpt_official_json":
		return StructuredELTFormatChatGPTJSON, nil
	case "messages_transcript":
		return StructuredELTFormatIMessageText, nil
	default:
		return "", fmt.Errorf("declared format %q has no DuckDB structured-ELT template", declared)
	}
}

// StructuredELTTemplateForFormat pins the SQL template revision covered by
// StructuredELTParserVersion. Every emitted row must repeat this identifier
// in native_metadata so an implementation/template mismatch fails before the
// bundle or parser-execution receipt can be committed.
func StructuredELTTemplateForFormat(format StructuredELTFormat) (string, error) {
	switch format {
	case StructuredELTFormatCSV:
		return "csv_v1", nil
	case StructuredELTFormatNDJSON:
		return "ndjson_v1", nil
	case StructuredELTFormatSMSXML:
		return "sms_xml_v1", nil
	case StructuredELTFormatChatGPTJSON:
		return "chatgpt_json_array_v1", nil
	case StructuredELTFormatIMessageText:
		return "imessage_text_v1", nil
	default:
		return "", fmt.Errorf("structured elt format %q has no pinned template", format)
	}
}

// requireStructuredELTDecisionRefs prevents the DuckDB pair from being used
// as an extension-based shortcut. The workflow supplies these references only
// after content inspection, an actor-bound choice, and durable compatibility
// validation. The references themselves remain compact; their payloads stay
// in PostgreSQL rather than Temporal history.
func requireStructuredELTDecisionRefs(req proffer.StageRequest) error {
	for _, name := range structuredELTDecisionRefs {
		if strings.TrimSpace(string(req.Refs[name])) == "" {
			return fmt.Errorf("structured elt requires durable %q reference", name)
		}
	}
	return nil
}

// SelectStructuredELT records the exact DuckDB implementation and template
// version for an eligible declared format. Proffer routes select and execute
// together, so a source can never carry an SBV selection receipt while being
// extracted by DuckDB.
func (a StructuredELTActivities) SelectStructuredELT(ctx context.Context, req proffer.StageRequest) (proffer.StageResult, error) {
	if err := a.validateStore(); err != nil {
		return proffer.StageResult{}, err
	}
	if err := ctx.Err(); err != nil {
		return proffer.StageResult{}, err
	}
	if strings.TrimSpace(req.RequestID) == "" || req.SourceVersionRef == "" {
		return proffer.StageResult{}, errors.New("select structured elt requires request and source version references")
	}
	if err := requireStructuredELTDecisionRefs(req); err != nil {
		return proffer.StageResult{}, err
	}
	if _, err := StructuredELTFormatForDeclaredFormat(req.DeclaredFormat); err != nil {
		return proffer.StageResult{}, err
	}
	selectionRef, receiptRef, err := a.Store.PersistParserSelection(ctx, ParserSelectionSpec{
		RequestID: req.RequestID, SourceVersionRef: req.SourceVersionRef,
		DeclaredFormat: parser.FormatID(req.DeclaredFormat),
		ParserID:       StructuredELTParserID, ParserVersion: StructuredELTParserVersion,
		Attempt: a.attempt(ctx),
	})
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("persist structured-ELT selection: %w", err)
	}
	if selectionRef == "" || receiptRef == "" {
		return proffer.StageResult{}, errors.New("persisted structured-ELT selection lacks result or activity receipt reference")
	}
	return parserStageSuccess(stagegraph.SelectParser, selectionRef, receiptRef), nil
}

// ExecuteStructuredELT is the DuckDB implementation of the canonical
// ExecuteParser stage. It emits the same immutable bundle and receipt as the
// decoder implementation; PersistRawGeneration and every later gate remain
// unchanged.
func (a StructuredELTActivities) ExecuteStructuredELT(ctx context.Context, req proffer.StageRequest) (proffer.StageResult, error) {
	if err := a.validateExecute(); err != nil {
		return proffer.StageResult{}, err
	}
	if err := ctx.Err(); err != nil {
		return proffer.StageResult{}, err
	}
	if strings.TrimSpace(req.RequestID) == "" || req.SourceVersionRef == "" {
		return proffer.StageResult{}, errors.New("execute structured elt requires request and source version references")
	}
	if err := requireStructuredELTDecisionRefs(req); err != nil {
		return proffer.StageResult{}, err
	}
	selectionRef, err := requiredParserRef(req, "parser_selection")
	if err != nil {
		return proffer.StageResult{}, err
	}
	if _, err := requiredParserRef(req, "original"); err != nil {
		return proffer.StageResult{}, err
	}
	format, err := StructuredELTFormatForDeclaredFormat(req.DeclaredFormat)
	if err != nil {
		return proffer.StageResult{}, err
	}
	templateID, err := StructuredELTTemplateForFormat(format)
	if err != nil {
		return proffer.StageResult{}, err
	}
	selection, err := a.Store.LoadParserSelection(ctx, selectionRef)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("load persisted structured-ELT selection %q: %w", selectionRef, err)
	}
	if err := validatePersistedSelection(req, selection); err != nil {
		return proffer.StageResult{}, err
	}
	if selection.ParserID != StructuredELTParserID || selection.ParserVersion != StructuredELTParserVersion {
		return proffer.StageResult{}, errors.New("persisted parser selection is not the pinned DuckDB structured-ELT implementation")
	}
	input, err := a.Store.ResolveParserInput(ctx, req, selection)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("resolve structured-ELT input: %w", err)
	}
	if err := validateResolvedInput(req, selection, input); err != nil {
		return proffer.StageResult{}, err
	}
	writer, err := a.Store.OpenParserBundleWriter(ctx, req, selection, input)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("open structured-ELT bundle writer: %w", err)
	}
	finalized := false
	defer func() {
		if !finalized {
			_ = writer.Abort(context.WithoutCancel(ctx))
		}
	}()
	if err := writer.Begin(ctx, parser.BundleHeader{
		ContractVersion: parser.ContractVersion, ParserID: selection.ParserID,
		ParserVersion: selection.ParserVersion, SourceVersionRef: string(req.SourceVersionRef),
		FormatID: parser.FormatID(req.DeclaredFormat),
	}); err != nil {
		return proffer.StageResult{}, fmt.Errorf("begin structured-ELT bundle: %w", err)
	}
	rows, err := a.Rows.OpenStructuredELTRows(ctx, req, format)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("open DuckDB structured rows: %w", err)
	}
	defer rows.Close()

	var ordinal uint64
	var accounting parser.BundleAccounting
	for {
		row, nextErr := rows.Next(ctx)
		if errors.Is(nextErr, io.EOF) {
			break
		}
		if nextErr != nil {
			return proffer.StageResult{}, fmt.Errorf("read DuckDB structured row %d: %w", ordinal, nextErr)
		}
		if err := row.validate(templateID); err != nil {
			return proffer.StageResult{}, fmt.Errorf("DuckDB structured row %d: %w", ordinal, err)
		}
		status := row.RecordStatus
		if status == "" {
			status = parser.StatusParsed
		}
		envelope := parser.RawRecordEnvelope{
			RecordOrdinal: ordinal, RecordStatus: status, StatusReason: strings.TrimSpace(row.StatusReason),
			StoredBytes:    &parser.StoredBytes{Bytes: append([]byte(nil), row.StoredBytes...)},
			FormatID:       parser.FormatID(req.DeclaredFormat),
			NativeFields:   append(json.RawMessage(nil), row.NativeFields...),
			NativeMetadata: append(json.RawMessage(nil), row.NativeMetadata...),
		}
		if err := envelope.Validate(parser.FormatID(req.DeclaredFormat)); err != nil {
			return proffer.StageResult{}, fmt.Errorf("validate DuckDB structured row %d: %w", ordinal, err)
		}
		if err := writer.Emit(ctx, envelope); err != nil {
			return proffer.StageResult{}, fmt.Errorf("emit DuckDB structured row %d: %w", ordinal, err)
		}
		tallyStructuredELT(&accounting, envelope)
		ordinal++
	}
	if ordinal == 0 {
		return proffer.StageResult{}, errors.New("DuckDB structured extraction produced no records")
	}
	bundleResult, err := writer.Finalize(ctx, accounting)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("finalize structured-ELT bundle: %w", err)
	}
	finalized = true
	if strings.TrimSpace(bundleResult.BundleRef) == "" {
		return proffer.StageResult{}, errors.New("structured-ELT bundle writer returned an empty reference")
	}
	resultRef, receiptRef, err := a.Store.PersistParserExecution(ctx, ParserExecutionSpec{
		RequestID: req.RequestID, SourceVersionRef: req.SourceVersionRef,
		ParserSelectionRef: selectionRef, ParserID: selection.ParserID,
		ParserVersion: selection.ParserVersion, BundleRef: proffer.Ref(bundleResult.BundleRef),
		Attempt: a.attempt(ctx),
	})
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("persist structured-ELT execution: %w", err)
	}
	if resultRef == "" || receiptRef == "" {
		return proffer.StageResult{}, errors.New("persisted structured-ELT execution lacks result or activity receipt reference")
	}
	return parserStageSuccess(stagegraph.ExecuteParser, resultRef, receiptRef), nil
}

func tallyStructuredELT(accounting *parser.BundleAccounting, record parser.RawRecordEnvelope) {
	accounting.Attachments += uint64(len(record.Attachments))
	switch record.RecordStatus {
	case parser.StatusParsed:
		accounting.Emitted++
	case parser.StatusRejected:
		accounting.Rejected++
	case parser.StatusMalformed:
		accounting.Malformed++
	case parser.StatusUnknown:
		accounting.Unknown++
	case parser.StatusUnparsed:
		accounting.Unparsed++
	}
}
