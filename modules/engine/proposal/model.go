// Package proposal defines the frozen, precommit artifact contract used by
// Proffer's prepare/review/approve/commit workflow.
package proposal

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"
)

const (
	SchemaVersion        = "proffer-proposal/v1"
	TableDigestAlgorithm = "proffer-table-json-v1"
)

type State string

const (
	StateBuilding   State = "building"
	StateFrozen     State = "frozen"
	StateApproved   State = "approved"
	StateCommitting State = "committing"
	StateCommitted  State = "committed"
	StateFailed     State = "failed"
	StateStopped    State = "stopped"
	StateSuperseded State = "superseded"
)

type Destination string

const (
	DestinationPostgresControl Destination = "postgres_control"
	DestinationPostgresMessage Destination = "postgres_messages"
	DestinationWeaviateContext Destination = "weaviate_context"
	DestinationNeo4jGraph      Destination = "neo4j_graph"
	DestinationContextIndex    Destination = "context_index"
	DestinationSurrealDBManual Destination = "surrealdb_manual_projection"
)

// AutomaticDestinations are the destinations that may be selected as part of
// the exact proposal approval. SurrealDB is deliberately excluded: it is a
// later, separately approved manual projection.
var AutomaticDestinations = []Destination{
	DestinationPostgresControl,
	DestinationPostgresMessage,
	DestinationWeaviateContext,
	DestinationNeo4jGraph,
	DestinationContextIndex,
}

type SourcePackage struct {
	Locator string `json:"locator"`
	Digest  string `json:"digest"`
}

type Counts struct {
	SourceRecords       int64 `json:"source_records"`
	Records             int64 `json:"records"`
	Metadata            int64 `json:"metadata"`
	Attachments         int64 `json:"attachments"`
	EntityMentions      int64 `json:"entity_mentions"`
	Entities            int64 `json:"entities"`
	Relationships       int64 `json:"relationships"`
	TemporalExpressions int64 `json:"temporal_expressions"`
	Chunks              int64 `json:"chunks"`
	Lineage             int64 `json:"lineage"`
	Warnings            int64 `json:"warnings"`
	SinkOperations      int64 `json:"sink_operations"`
}

// TableDigest binds the canonical logical rows of one proposal relation. It
// never represents the physical DuckDB file bytes.
type TableDigest struct {
	Table     string `json:"table"`
	Algorithm string `json:"algorithm"`
	Rows      int64  `json:"rows"`
	Digest    string `json:"digest"`
}

type DestinationPlan struct {
	Destination    Destination `json:"destination"`
	Selected       bool        `json:"selected"`
	OperationCount int64       `json:"operation_count"`
	SnapshotDigest string      `json:"snapshot_digest,omitempty"`
}

type ToolReceipt struct {
	Stage          string `json:"stage"`
	ToolID         string `json:"tool_id"`
	ToolVersion    string `json:"tool_version"`
	ConfigDigest   string `json:"config_digest"`
	InputDigest    string `json:"input_digest"`
	OutputDigest   string `json:"output_digest"`
	ActivityID     string `json:"activity_id,omitempty"`
	N8NExecutionID string `json:"n8n_execution_id,omitempty"`
}

// Manifest describes every artifact and destination operation in one immutable
// attempt. ProposalDigest is empty while building and is populated only by
// Freeze after validation and canonical ordering.
type Manifest struct {
	SchemaVersion  string            `json:"schema_version"`
	OperationID    string            `json:"operation_id"`
	AttemptID      string            `json:"attempt_id"`
	Mode           string            `json:"mode"`
	MatterID       string            `json:"matter_id"`
	CourtCaseID    string            `json:"court_case_id"`
	CreatedAt      time.Time         `json:"created_at"`
	State          State             `json:"state"`
	SourcePackage  SourcePackage     `json:"source_package"`
	ConfigDigest   string            `json:"config_digest"`
	TableDigests   []TableDigest     `json:"table_digests"`
	Counts         Counts            `json:"counts"`
	ToolReceipts   []ToolReceipt     `json:"tool_receipts"`
	Destinations   []DestinationPlan `json:"destinations"`
	ProposalDigest string            `json:"proposal_digest,omitempty"`
}

// BundleEnvelope is written only after proposal_control contains the frozen
// logical proposal digest and the DuckDB file is closed. DatabaseByteDigest is
// therefore an external transport hash and is deliberately excluded from
// Manifest and ProposalDigest, avoiding circular self-hashing.
type BundleEnvelope struct {
	SchemaVersion      string           `json:"schema_version"`
	OperationID        string           `json:"operation_id"`
	AttemptID          string           `json:"attempt_id"`
	ProposalDigest     string           `json:"proposal_digest"`
	DatabaseLocator    string           `json:"database_locator"`
	DatabaseByteDigest string           `json:"database_byte_digest"`
	DatabaseBytes      int64            `json:"database_bytes"`
	ExternalArtifacts  []BundleArtifact `json:"external_artifacts"`
	FinalizedAt        time.Time        `json:"finalized_at"`
	BundleDigest       string           `json:"bundle_digest,omitempty"`
}

type BundleArtifact struct {
	Name       string `json:"name"`
	Locator    string `json:"locator"`
	ByteDigest string `json:"byte_digest"`
	Bytes      int64  `json:"bytes"`
}

// ApprovalBinding is the immutable assertion sent to the commit workflow.
// The destination plan is already inside ProposalDigest, so changing a selected
// destination necessarily invalidates this binding.
type ApprovalBinding struct {
	OperationID    string    `json:"operation_id"`
	AttemptID      string    `json:"attempt_id"`
	ProposalDigest string    `json:"proposal_digest"`
	BundleDigest   string    `json:"bundle_digest,omitempty"`
	ActorSubject   string    `json:"actor_subject"`
	ApprovedAt     time.Time `json:"approved_at"`
}

// ManualSurrealProjection is a separate request over already committed material.
// It cannot be smuggled into the automatic Context destination plan.
type ManualSurrealProjection struct {
	OperationID             string    `json:"operation_id"`
	AttemptID               string    `json:"attempt_id"`
	CommittedProposalDigest string    `json:"committed_proposal_digest"`
	ScopeDigest             string    `json:"scope_digest"`
	ActorSubject            string    `json:"actor_subject"`
	RequestedAt             time.Time `json:"requested_at"`
}

func validDigest(value string) bool {
	if len(value) != sha256.Size*2 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

func automaticDestination(destination Destination) bool {
	return slices.Contains(AutomaticDestinations, destination)
}

func (m Manifest) ValidateBuilding() error {
	if m.SchemaVersion != SchemaVersion {
		return fmt.Errorf("schema_version must be %q", SchemaVersion)
	}
	if strings.TrimSpace(m.OperationID) == "" || strings.TrimSpace(m.AttemptID) == "" {
		return errors.New("operation_id and attempt_id are required")
	}
	if m.Mode != "TEST" && m.Mode != "REAL" {
		return errors.New("mode must be TEST or REAL")
	}
	if strings.TrimSpace(m.MatterID) == "" || strings.TrimSpace(m.CourtCaseID) == "" {
		return errors.New("matter_id and court_case_id are required")
	}
	if m.CreatedAt.IsZero() {
		return errors.New("created_at is required")
	}
	if strings.TrimSpace(m.SourcePackage.Locator) == "" || !validDigest(m.SourcePackage.Digest) {
		return errors.New("source package locator and SHA-256 digest are required")
	}
	if !validDigest(m.ConfigDigest) {
		return errors.New("config_digest must be a SHA-256 digest")
	}
	for label, count := range map[string]int64{
		"source_records":       m.Counts.SourceRecords,
		"records":              m.Counts.Records,
		"metadata":             m.Counts.Metadata,
		"attachments":          m.Counts.Attachments,
		"entity_mentions":      m.Counts.EntityMentions,
		"entities":             m.Counts.Entities,
		"relationships":        m.Counts.Relationships,
		"temporal_expressions": m.Counts.TemporalExpressions,
		"chunks":               m.Counts.Chunks,
		"lineage":              m.Counts.Lineage,
		"warnings":             m.Counts.Warnings,
		"sink_operations":      m.Counts.SinkOperations,
	} {
		if count < 0 {
			return fmt.Errorf("proposal count %q must not be negative", label)
		}
	}

	expectedRows := m.logicalRowCounts()
	tableDigests := make(map[string]struct{}, len(m.TableDigests))
	for _, table := range m.TableDigests {
		if _, required := expectedRows[table.Table]; !required {
			return fmt.Errorf("logical table digest %q is not required", table.Table)
		}
		if table.Algorithm != TableDigestAlgorithm {
			return fmt.Errorf(
				"logical table digest %q must use algorithm %q",
				table.Table,
				TableDigestAlgorithm,
			)
		}
		if table.Rows != expectedRows[table.Table] || !validDigest(table.Digest) {
			return fmt.Errorf("logical table digest %q has an invalid digest or row count", table.Table)
		}
		if _, exists := tableDigests[table.Table]; exists {
			return fmt.Errorf("logical table digest %q is duplicated", table.Table)
		}
		tableDigests[table.Table] = struct{}{}
	}
	for _, table := range LogicalContentTables {
		if _, exists := tableDigests[table]; !exists {
			return fmt.Errorf("logical table digest %q is required", table)
		}
	}

	destinations := make(map[Destination]struct{}, len(m.Destinations))
	plannedOperations := int64(0)
	for _, plan := range m.Destinations {
		if !automaticDestination(plan.Destination) {
			return fmt.Errorf("destination %q is not an automatic Context destination", plan.Destination)
		}
		if plan.OperationCount < 0 {
			return fmt.Errorf("destination %q has a negative operation count", plan.Destination)
		}
		if plan.SnapshotDigest != "" && !validDigest(plan.SnapshotDigest) {
			return fmt.Errorf("destination %q has an invalid snapshot digest", plan.Destination)
		}
		if _, exists := destinations[plan.Destination]; exists {
			return fmt.Errorf("destination %q is duplicated", plan.Destination)
		}
		destinations[plan.Destination] = struct{}{}
		plannedOperations += plan.OperationCount
	}
	if plannedOperations != m.Counts.SinkOperations {
		return fmt.Errorf(
			"sink operation count is %d, destination plan requires %d",
			m.Counts.SinkOperations,
			plannedOperations,
		)
	}

	for _, receipt := range m.ToolReceipts {
		if strings.TrimSpace(receipt.Stage) == "" || strings.TrimSpace(receipt.ToolID) == "" || strings.TrimSpace(receipt.ToolVersion) == "" {
			return errors.New("every tool receipt requires stage, tool_id, and tool_version")
		}
		for label, digest := range map[string]string{
			"config_digest": receipt.ConfigDigest,
			"input_digest":  receipt.InputDigest,
			"output_digest": receipt.OutputDigest,
		} {
			if !validDigest(digest) {
				return fmt.Errorf("tool receipt %q has an invalid %s", receipt.Stage, label)
			}
		}
	}

	return nil
}

func canonical(m Manifest) Manifest {
	clone := m
	clone.ProposalDigest = ""
	clone.State = StateFrozen
	clone.CreatedAt = clone.CreatedAt.UTC()
	clone.TableDigests = slices.Clone(m.TableDigests)
	clone.ToolReceipts = slices.Clone(m.ToolReceipts)
	clone.Destinations = slices.Clone(m.Destinations)
	slices.SortFunc(clone.TableDigests, func(a, b TableDigest) int {
		return strings.Compare(a.Table, b.Table)
	})
	slices.SortFunc(clone.ToolReceipts, func(a, b ToolReceipt) int {
		return strings.Compare(a.Stage+"\x00"+a.ToolID+"\x00"+a.OutputDigest, b.Stage+"\x00"+b.ToolID+"\x00"+b.OutputDigest)
	})
	slices.SortFunc(clone.Destinations, func(a, b DestinationPlan) int {
		return strings.Compare(string(a.Destination), string(b.Destination))
	})
	return clone
}

func (m Manifest) logicalRowCounts() map[string]int64 {
	return map[string]int64{
		"proposed_source_records":       m.Counts.SourceRecords,
		"proposed_records":              m.Counts.Records,
		"proposed_metadata":             m.Counts.Metadata,
		"proposed_attachments":          m.Counts.Attachments,
		"proposed_entity_mentions":      m.Counts.EntityMentions,
		"proposed_entities":             m.Counts.Entities,
		"proposed_relationships":        m.Counts.Relationships,
		"proposed_temporal_expressions": m.Counts.TemporalExpressions,
		"proposed_chunks":               m.Counts.Chunks,
		"proposed_lineage":              m.Counts.Lineage,
		"proposed_warnings":             m.Counts.Warnings,
		"proposed_sink_operations":      m.Counts.SinkOperations,
		"tool_receipts":                 int64(len(m.ToolReceipts)),
	}
}

func (e BundleEnvelope) ValidateFor(m Manifest) error {
	if !validDigest(e.BundleDigest) {
		return errors.New("bundle_digest must be a SHA-256 digest")
	}
	expected, err := digestBundle(e)
	if err != nil {
		return err
	}
	if !strings.EqualFold(expected, e.BundleDigest) {
		return errors.New("bundle digest does not match the finalized transport envelope")
	}
	return e.validateContentsFor(m)
}

func (e BundleEnvelope) validateContentsFor(m Manifest) error {
	if err := m.VerifyFrozen(); err != nil {
		return err
	}
	if e.SchemaVersion != SchemaVersion || e.OperationID != m.OperationID || e.AttemptID != m.AttemptID {
		return errors.New("bundle envelope identity does not match proposal")
	}
	if !strings.EqualFold(e.ProposalDigest, m.ProposalDigest) {
		return errors.New("bundle envelope logical digest does not match proposal")
	}
	if strings.TrimSpace(e.DatabaseLocator) == "" || !validDigest(e.DatabaseByteDigest) || e.DatabaseBytes <= 0 {
		return errors.New("bundle envelope requires database locator, byte digest, and positive size")
	}
	if e.FinalizedAt.IsZero() {
		return errors.New("bundle envelope finalized_at is required")
	}
	names := make(map[string]struct{}, len(e.ExternalArtifacts))
	for _, artifact := range e.ExternalArtifacts {
		if strings.TrimSpace(artifact.Name) == "" || strings.TrimSpace(artifact.Locator) == "" ||
			!validDigest(artifact.ByteDigest) || artifact.Bytes < 0 {
			return errors.New("every external bundle artifact requires name, locator, byte digest, and non-negative size")
		}
		if _, exists := names[artifact.Name]; exists {
			return fmt.Errorf("external bundle artifact %q is duplicated", artifact.Name)
		}
		names[artifact.Name] = struct{}{}
	}
	return nil
}

func digestBundle(envelope BundleEnvelope) (string, error) {
	canonical := envelope
	canonical.BundleDigest = ""
	canonical.FinalizedAt = canonical.FinalizedAt.UTC()
	canonical.ExternalArtifacts = slices.Clone(envelope.ExternalArtifacts)
	slices.SortFunc(canonical.ExternalArtifacts, func(a, b BundleArtifact) int {
		return strings.Compare(a.Name+"\x00"+a.Locator, b.Name+"\x00"+b.Locator)
	})
	payload, err := json.Marshal(canonical)
	if err != nil {
		return "", fmt.Errorf("marshal canonical bundle envelope: %w", err)
	}
	digest := sha256.Sum256(payload)
	return hex.EncodeToString(digest[:]), nil
}

func FinalizeBundle(m Manifest, envelope BundleEnvelope) (BundleEnvelope, error) {
	if envelope.BundleDigest != "" {
		return BundleEnvelope{}, errors.New("unfinalized bundle envelope must not carry a bundle digest")
	}
	if err := envelope.validateContentsFor(m); err != nil {
		return BundleEnvelope{}, err
	}
	canonical := envelope
	canonical.FinalizedAt = canonical.FinalizedAt.UTC()
	canonical.ExternalArtifacts = slices.Clone(envelope.ExternalArtifacts)
	slices.SortFunc(canonical.ExternalArtifacts, func(a, b BundleArtifact) int {
		return strings.Compare(a.Name+"\x00"+a.Locator, b.Name+"\x00"+b.Locator)
	})
	digest, err := digestBundle(canonical)
	if err != nil {
		return BundleEnvelope{}, err
	}
	canonical.BundleDigest = digest
	return canonical, nil
}

func digestManifest(m Manifest) (string, error) {
	payload, err := json.Marshal(m)
	if err != nil {
		return "", fmt.Errorf("marshal canonical proposal manifest: %w", err)
	}
	sum := sha256.Sum256(payload)
	return hex.EncodeToString(sum[:]), nil
}

// Freeze validates, canonically orders, and digests a complete proposal. It
// returns a new value and never mutates the caller's manifest.
func Freeze(building Manifest) (Manifest, error) {
	if building.State != "" && building.State != StateBuilding {
		return Manifest{}, fmt.Errorf("proposal must be building before freeze, got %q", building.State)
	}
	if building.ProposalDigest != "" {
		return Manifest{}, errors.New("building proposal must not carry a proposal digest")
	}
	if err := building.ValidateBuilding(); err != nil {
		return Manifest{}, err
	}
	frozen := canonical(building)
	digest, err := digestManifest(frozen)
	if err != nil {
		return Manifest{}, err
	}
	frozen.ProposalDigest = digest
	return frozen, nil
}

func (m Manifest) VerifyFrozen() error {
	if m.State != StateFrozen && m.State != StateApproved && m.State != StateCommitting && m.State != StateCommitted {
		return fmt.Errorf("proposal state %q is not frozen", m.State)
	}
	if !validDigest(m.ProposalDigest) {
		return errors.New("proposal_digest must be a SHA-256 digest")
	}
	building := m
	building.State = StateBuilding
	building.ProposalDigest = ""
	if err := building.ValidateBuilding(); err != nil {
		return err
	}
	expectedBase := canonical(m)
	expected, err := digestManifest(expectedBase)
	if err != nil {
		return err
	}
	if !strings.EqualFold(expected, m.ProposalDigest) {
		return errors.New("proposal digest does not match the frozen manifest")
	}
	return nil
}

func (a ApprovalBinding) ValidateFor(m Manifest) error {
	if a.BundleDigest != "" {
		return errors.New("bundle-bound approval requires ValidateForBundle")
	}
	if m.State != StateFrozen {
		return fmt.Errorf("approval requires proposal state %q, got %q", StateFrozen, m.State)
	}
	if err := m.VerifyFrozen(); err != nil {
		return err
	}
	if a.OperationID != m.OperationID || a.AttemptID != m.AttemptID {
		return errors.New("approval operation or attempt does not match proposal")
	}
	if !strings.EqualFold(a.ProposalDigest, m.ProposalDigest) {
		return errors.New("approval digest does not match proposal")
	}
	if strings.TrimSpace(a.ActorSubject) == "" || a.ApprovedAt.IsZero() {
		return errors.New("approval actor and timestamp are required")
	}
	return nil
}

// ValidateForBundle binds approval to both logical proposal content and the
// external finalized-byte envelope. Nothing from the external envelope is
// written back into DuckDB, so this adds no self-hash cycle.
func (a ApprovalBinding) ValidateForBundle(m Manifest, envelope *BundleEnvelope) error {
	logicalApproval := a
	logicalApproval.BundleDigest = ""
	if err := logicalApproval.ValidateFor(m); err != nil {
		return err
	}
	if envelope == nil {
		if a.BundleDigest != "" {
			return errors.New("approval carries bundle_digest but no bundle envelope was supplied")
		}
		return nil
	}
	if !validDigest(a.BundleDigest) {
		return errors.New("approval bundle_digest must be a SHA-256 digest")
	}
	if err := envelope.ValidateFor(m); err != nil {
		return err
	}
	if !strings.EqualFold(a.BundleDigest, envelope.BundleDigest) {
		return errors.New("approval bundle digest does not match finalized bundle")
	}
	return nil
}

func (r ManualSurrealProjection) Validate() error {
	if strings.TrimSpace(r.OperationID) == "" || strings.TrimSpace(r.AttemptID) == "" {
		return errors.New("operation_id and attempt_id are required")
	}
	if !validDigest(r.CommittedProposalDigest) || !validDigest(r.ScopeDigest) {
		return errors.New("committed proposal and projection scope require SHA-256 digests")
	}
	if strings.TrimSpace(r.ActorSubject) == "" || r.RequestedAt.IsZero() {
		return errors.New("manual projection actor and timestamp are required")
	}
	return nil
}
