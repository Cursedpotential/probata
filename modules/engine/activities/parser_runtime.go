package activities

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/Cursedpotential/probata/engine/parser"
	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/stagegraph"
)

// ParserSelectionSpec is the immutable selection decision persisted by
// select_parser_activity. It contains only capability identity and compact
// workflow coordinates; selection never receives source bytes or records.
type ParserSelectionSpec struct {
	RequestID        string
	SourceVersionRef proffer.Ref
	DeclaredFormat   parser.FormatID
	ParserID         string
	ParserVersion    string
	Attempt          int32
}

// PersistedParserSelection is the exact selection loaded by
// execute_parser_activity. The parser ID/version is an execution pin, not a
// hint to repeat selection after registry drift.
type PersistedParserSelection struct {
	SourceVersionRef proffer.Ref
	DeclaredFormat   parser.FormatID
	ParserID         string
	ParserVersion    string
}

// ParserExecutionSpec is the compact execution receipt payload. BundleRef was
// minted by the caller-owned BundleWriter; persist_raw_generation_activity,
// not this parser Activity, later owns canonical raw-record persistence.
type ParserExecutionSpec struct {
	RequestID          string
	SourceVersionRef   proffer.Ref
	ParserSelectionRef proffer.Ref
	ParserID           string
	ParserVersion      string
	BundleRef          proffer.Ref
	Attempt            int32
}

// ParserActivityStore is the persistence/reference boundary for the parser
// Activities. It resolves all source references outside Temporal history and
// persists immutable activity receipts; it never exposes a record array on an
// Activity request or result.
type ParserActivityStore interface {
	PersistParserSelection(context.Context, ParserSelectionSpec) (selectionRef proffer.Ref, receiptRef proffer.Ref, err error)
	LoadParserSelection(context.Context, proffer.Ref) (PersistedParserSelection, error)
	ResolveParserInput(context.Context, proffer.StageRequest, PersistedParserSelection) (parser.ParserInput, error)
	OpenParserBundleWriter(context.Context, proffer.StageRequest, PersistedParserSelection, parser.ParserInput) (parser.BundleWriter, error)
	PersistParserExecution(context.Context, ParserExecutionSpec) (resultRef proffer.Ref, receiptRef proffer.Ref, err error)
}

// ParserActivities implements the two parser-related atomic Activity bodies.
// Attempt is injectable for tests and defaults to one for direct callers; a
// Temporal worker supplies activity.GetInfo(ctx).Attempt during registration.
type ParserActivities struct {
	Registry      *parser.Registry
	Store         ParserActivityStore
	Authorization HandlerExecutionAuthorizationStore
	Attempt       Attempt
}

func (a ParserActivities) validate() error {
	if a.Registry == nil {
		return errors.New("parser activities: registry is required")
	}
	if a.Store == nil {
		return errors.New("parser activities: store is required")
	}
	return nil
}

func (a ParserActivities) attempt(ctx context.Context) int32 {
	if a.Attempt == nil {
		return 1
	}
	attempt := a.Attempt(ctx)
	if attempt < 1 {
		return 1
	}
	return attempt
}

// SelectParser persists the one declared-format/quality selection decision.
// Registry accepts no input size, source bytes, or hash data, so selection is
// strictly capability coverage and quality as required by the v1 contract.
func (a ParserActivities) SelectParser(ctx context.Context, req proffer.StageRequest) (proffer.StageResult, error) {
	if err := a.validate(); err != nil {
		return proffer.StageResult{}, err
	}
	if err := ctx.Err(); err != nil {
		return proffer.StageResult{}, err
	}
	if strings.TrimSpace(req.RequestID) == "" || req.SourceVersionRef == "" {
		return proffer.StageResult{}, errors.New("select parser requires request and source version references")
	}
	format := parser.FormatID(req.DeclaredFormat)
	capability, err := a.capabilityForSelection(ctx, req, format)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("select parser for format %q: %w", req.DeclaredFormat, err)
	}
	selectionRef, receiptRef, err := a.Store.PersistParserSelection(ctx, ParserSelectionSpec{
		RequestID:        req.RequestID,
		SourceVersionRef: req.SourceVersionRef,
		DeclaredFormat:   format,
		ParserID:         capability.ParserID,
		ParserVersion:    capability.ParserVersion,
		Attempt:          a.attempt(ctx),
	})
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("persist parser selection: %w", err)
	}
	if selectionRef == "" || receiptRef == "" {
		return proffer.StageResult{}, errors.New("persisted parser selection lacks result or activity receipt reference")
	}
	return parserStageSuccess(stagegraph.SelectParser, selectionRef, receiptRef), nil
}

// ExecuteParser loads the exact prior selection and executes that parser only.
// It does not call Registry.Select: a missing, stale, or wrong selection is a
// hard error rather than an opportunity to choose a newer parser.
func (a ParserActivities) ExecuteParser(ctx context.Context, req proffer.StageRequest) (proffer.StageResult, error) {
	if err := a.validate(); err != nil {
		return proffer.StageResult{}, err
	}
	if err := ctx.Err(); err != nil {
		return proffer.StageResult{}, err
	}
	if strings.TrimSpace(req.RequestID) == "" || req.SourceVersionRef == "" {
		return proffer.StageResult{}, errors.New("execute parser requires request and source version references")
	}
	selectionRef, err := requiredParserRef(req, "parser_selection")
	if err != nil {
		return proffer.StageResult{}, err
	}
	if _, err := requiredParserRef(req, "original"); err != nil {
		return proffer.StageResult{}, err
	}
	selection, err := a.Store.LoadParserSelection(ctx, selectionRef)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("load persisted parser selection %q: %w", selectionRef, err)
	}
	if err := validatePersistedSelection(req, selection); err != nil {
		return proffer.StageResult{}, err
	}
	if err := a.validateExecutionAuthorization(ctx, req, selection); err != nil {
		return proffer.StageResult{}, err
	}
	input, err := a.Store.ResolveParserInput(ctx, req, selection)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("resolve parser input: %w", err)
	}
	if err := validateResolvedInput(req, selection, input); err != nil {
		return proffer.StageResult{}, err
	}
	writer, err := a.Store.OpenParserBundleWriter(ctx, req, selection, input)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("open parser bundle writer: %w", err)
	}
	executionInput := input
	if present, _ := handlerDecisionRefsPresent(req); present {
		authorization, authorizationErr := a.loadDecoderAuthorization(ctx, req)
		if authorizationErr != nil {
			return proffer.StageResult{}, authorizationErr
		}
		executionInput.DeclaredFormat = parser.FormatID(authorization.DetectedFormat)
		writer = declaredFormatBundleWriter{BundleWriter: writer, declared: input.DeclaredFormat}
	}
	bundleResult, err := a.Registry.ExecuteSelected(ctx, executionInput, selection.ParserID, selection.ParserVersion, writer)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("execute persisted parser %q version %q: %w", selection.ParserID, selection.ParserVersion, err)
	}
	resultRef, receiptRef, err := a.Store.PersistParserExecution(ctx, ParserExecutionSpec{
		RequestID:          req.RequestID,
		SourceVersionRef:   req.SourceVersionRef,
		ParserSelectionRef: selectionRef,
		ParserID:           selection.ParserID,
		ParserVersion:      selection.ParserVersion,
		BundleRef:          proffer.Ref(bundleResult.BundleRef),
		Attempt:            a.attempt(ctx),
	})
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("persist parser execution: %w", err)
	}
	if resultRef == "" || receiptRef == "" {
		return proffer.StageResult{}, errors.New("persisted parser execution lacks result or activity receipt reference")
	}
	return parserStageSuccess(stagegraph.ExecuteParser, resultRef, receiptRef), nil
}

func (a ParserActivities) capabilityForSelection(ctx context.Context, req proffer.StageRequest, format parser.FormatID) (parser.Capability, error) {
	present, err := handlerDecisionRefsPresent(req)
	if err != nil {
		return parser.Capability{}, err
	}
	if !present {
		return a.Registry.SelectCapability(format)
	}
	authorization, err := a.loadDecoderAuthorization(ctx, req)
	if err != nil {
		return parser.Capability{}, err
	}
	_, capability, err := a.Registry.Lookup(authorization.HandlerID, authorization.HandlerVersion)
	if err != nil {
		return parser.Capability{}, err
	}
	if !capabilityDeclaresFormat(capability, parser.FormatID(authorization.DetectedFormat)) {
		return parser.Capability{}, fmt.Errorf("authorized parser %q version %q does not declare format %q", capability.ParserID, capability.ParserVersion, format)
	}
	return capability, nil
}

// The detected signature selects decoder coverage; the original intake
// declaration remains unchanged on persisted bundles and records.
type declaredFormatBundleWriter struct {
	parser.BundleWriter
	declared parser.FormatID
}

func (w declaredFormatBundleWriter) Begin(ctx context.Context, header parser.BundleHeader) error {
	header.FormatID = w.declared
	return w.BundleWriter.Begin(ctx, header)
}

func (w declaredFormatBundleWriter) Emit(ctx context.Context, record parser.RawRecordEnvelope) error {
	record.FormatID = w.declared
	return w.BundleWriter.Emit(ctx, record)
}

func (a ParserActivities) validateExecutionAuthorization(ctx context.Context, req proffer.StageRequest, selection PersistedParserSelection) error {
	present, err := handlerDecisionRefsPresent(req)
	if err != nil {
		return err
	}
	if !present {
		return nil
	}
	authorization, err := a.loadDecoderAuthorization(ctx, req)
	if err != nil {
		return err
	}
	if authorization.HandlerID != selection.ParserID || authorization.HandlerVersion != selection.ParserVersion {
		return errors.New("persisted parser selection does not match the exact authorized decoder identity")
	}
	return nil
}

func (a ParserActivities) loadDecoderAuthorization(ctx context.Context, req proffer.StageRequest) (HandlerExecutionAuthorization, error) {
	if a.Authorization == nil {
		return HandlerExecutionAuthorization{}, errors.New("content-validated parser request requires a handler authorization store")
	}
	authorization, err := a.Authorization.LoadHandlerExecutionAuthorization(ctx, req)
	if err != nil {
		return HandlerExecutionAuthorization{}, fmt.Errorf("load exact decoder authorization: %w", err)
	}
	if authorization.ExecutionPath != proffer.HandlerPathDecoder {
		return HandlerExecutionAuthorization{}, errors.New("validated handler authorization is not a decoder execution")
	}
	if strings.TrimSpace(authorization.HandlerID) == "" || strings.TrimSpace(authorization.HandlerVersion) == "" {
		return HandlerExecutionAuthorization{}, errors.New("validated decoder authorization lacks parser identity")
	}
	return authorization, nil
}

func capabilityDeclaresFormat(capability parser.Capability, format parser.FormatID) bool {
	for _, declared := range capability.DeclaredFormats {
		if declared == format {
			return true
		}
	}
	return false
}

func parserStageSuccess(stage stagegraph.StageID, resultRef, receiptRef proffer.Ref) proffer.StageResult {
	return proffer.StageResult{Stage: stage, Status: proffer.StatusSuccess, Ref: resultRef, ReceiptRef: receiptRef}
}

func requiredParserRef(req proffer.StageRequest, name string) (proffer.Ref, error) {
	ref := req.Refs[name]
	if ref == "" {
		return "", fmt.Errorf("%s requires non-empty %q reference", stagegraph.ExecuteParser, name)
	}
	return ref, nil
}

func validatePersistedSelection(req proffer.StageRequest, selection PersistedParserSelection) error {
	if selection.SourceVersionRef != req.SourceVersionRef {
		return errors.New("persisted parser selection belongs to a different source version")
	}
	if selection.DeclaredFormat != parser.FormatID(req.DeclaredFormat) {
		return errors.New("persisted parser selection declared format does not match execution request")
	}
	if strings.TrimSpace(selection.ParserID) == "" || strings.TrimSpace(selection.ParserVersion) == "" {
		return errors.New("persisted parser selection lacks parser id or version")
	}
	return nil
}

func validateResolvedInput(req proffer.StageRequest, selection PersistedParserSelection, input parser.ParserInput) error {
	if err := input.Validate(); err != nil {
		return fmt.Errorf("resolved parser input: %w", err)
	}
	if input.SourceVersionRef != string(req.SourceVersionRef) {
		return errors.New("resolved parser input belongs to a different source version")
	}
	if input.DeclaredFormat != selection.DeclaredFormat {
		return errors.New("resolved parser input declared format does not match persisted selection")
	}
	return nil
}
