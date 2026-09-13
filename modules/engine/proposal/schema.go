package proposal

import _ "embed"

// DuckDBSchema is the complete v1 per-attempt artifact schema. All proposed
// domain content remains in DuckDB through review. proposal_control contains
// PostgreSQL matter coordinates but no proposed domain rows.
//
//go:embed schema.sql
var DuckDBSchema string

var RequiredTables = []string{
	"proposal_control",
	"proposed_source_records",
	"proposed_records",
	"proposed_metadata",
	"proposed_attachments",
	"proposed_entity_mentions",
	"proposed_entities",
	"proposed_relationships",
	"proposed_temporal_expressions",
	"proposed_chunks",
	"proposed_lineage",
	"proposed_warnings",
	"proposed_sink_operations",
	"tool_receipts",
}

// LogicalContentTables are hashed independently before Freeze. proposal_control
// is excluded because it stores the resulting proposal digest and freeze state;
// including its physical row would create a circular digest.
var LogicalContentTables = []string{
	"proposed_source_records",
	"proposed_records",
	"proposed_metadata",
	"proposed_attachments",
	"proposed_entity_mentions",
	"proposed_entities",
	"proposed_relationships",
	"proposed_temporal_expressions",
	"proposed_chunks",
	"proposed_lineage",
	"proposed_warnings",
	"proposed_sink_operations",
	"tool_receipts",
}
