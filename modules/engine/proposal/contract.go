package proposal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

var ErrFrozenArtifactExists = errors.New("frozen proposal artifact already exists; overwrite refused")

// SchemaExecutor applies the versioned SQL contract to a new per-attempt
// DuckDB artifact. It is deliberately smaller than database/sql and carries no
// dependency on a particular DuckDB driver.
type SchemaExecutor interface {
	Exec(context.Context, string) error
}

func InitializeArtifact(ctx context.Context, executor SchemaExecutor) error {
	if executor == nil {
		return errors.New("proposal schema executor is required")
	}
	if err := executor.Exec(ctx, DuckDBSchema); err != nil {
		return fmt.Errorf("initialize proposal artifact schema: %w", err)
	}
	return nil
}

// Inspector is the narrow read interface required to validate a DuckDB
// artifact. A runtime adapter can implement it with the supported DuckDB CLI or
// driver without coupling this package to CGO.
type Inspector interface {
	TableNames(context.Context) ([]string, error)
	RowCount(context.Context, string) (int64, error)
}

// FrozenWriter performs one atomic create of proposal_control's logical freeze
// fields. Implementations must return ErrFrozenArtifactExists when those fields
// have already been populated.
type FrozenWriter interface {
	CreateFrozen(context.Context, []byte, string, time.Time) error
}

type TableValidation struct {
	Table    string
	Expected int64
	Actual   int64
}

type ValidationReport struct {
	Tables []TableValidation
}

func ExpectedRowCounts(m Manifest) (map[string]int64, error) {
	if err := m.VerifyFrozen(); err != nil {
		return nil, err
	}
	return map[string]int64{
		"proposal_control":              1,
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
	}, nil
}

func ValidateArtifact(ctx context.Context, inspector Inspector, manifest Manifest) (ValidationReport, error) {
	if inspector == nil {
		return ValidationReport{}, errors.New("proposal artifact inspector is required")
	}
	expected, err := ExpectedRowCounts(manifest)
	if err != nil {
		return ValidationReport{}, err
	}
	tables, err := inspector.TableNames(ctx)
	if err != nil {
		return ValidationReport{}, fmt.Errorf("list proposal tables: %w", err)
	}
	present := make(map[string]struct{}, len(tables))
	for _, table := range tables {
		present[strings.ToLower(strings.TrimSpace(table))] = struct{}{}
	}
	report := ValidationReport{Tables: make([]TableValidation, 0, len(RequiredTables))}
	for _, table := range RequiredTables {
		if _, ok := present[table]; !ok {
			return report, fmt.Errorf("required proposal table %q is missing", table)
		}
		actual, countErr := inspector.RowCount(ctx, table)
		if countErr != nil {
			return report, fmt.Errorf("count proposal table %q: %w", table, countErr)
		}
		check := TableValidation{Table: table, Expected: expected[table], Actual: actual}
		report.Tables = append(report.Tables, check)
		if actual != check.Expected {
			return report, fmt.Errorf("proposal table %q row count is %d, expected %d", table, actual, check.Expected)
		}
	}
	return report, nil
}

func FreezeOnce(existing *Manifest, building Manifest) (Manifest, error) {
	if existing != nil {
		return Manifest{}, ErrFrozenArtifactExists
	}
	return Freeze(building)
}

func PersistFrozen(ctx context.Context, writer FrozenWriter, frozen Manifest, frozenAt time.Time) error {
	if writer == nil {
		return errors.New("frozen proposal writer is required")
	}
	if frozen.State != StateFrozen {
		return fmt.Errorf("only state %q may be persisted as a frozen artifact", StateFrozen)
	}
	if err := frozen.VerifyFrozen(); err != nil {
		return err
	}
	if frozenAt.IsZero() {
		return errors.New("frozen_at is required")
	}
	payload, err := json.Marshal(frozen)
	if err != nil {
		return fmt.Errorf("marshal frozen proposal: %w", err)
	}
	if err := writer.CreateFrozen(ctx, payload, frozen.ProposalDigest, frozenAt.UTC()); err != nil {
		if errors.Is(err, ErrFrozenArtifactExists) {
			return ErrFrozenArtifactExists
		}
		return fmt.Errorf("persist frozen proposal: %w", err)
	}
	return nil
}

func CanTransition(from, to State) bool {
	allowed := map[State][]State{
		StateBuilding:   {StateFrozen, StateFailed, StateStopped},
		StateFrozen:     {StateApproved, StateFailed, StateStopped, StateSuperseded},
		StateApproved:   {StateCommitting, StateStopped, StateSuperseded},
		StateCommitting: {StateCommitted, StateFailed},
		StateCommitted:  {StateSuperseded},
	}
	for _, candidate := range allowed[from] {
		if candidate == to {
			return true
		}
	}
	return false
}

func ValidateTransition(from, to State) error {
	if !CanTransition(from, to) {
		return fmt.Errorf("illegal proposal state transition %q -> %q", from, to)
	}
	return nil
}
