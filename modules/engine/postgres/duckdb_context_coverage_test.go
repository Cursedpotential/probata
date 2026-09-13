package postgres

import (
	"context"
	"reflect"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type coverageProofRow struct {
	values []any
	err    error
}

func (r coverageProofRow) Scan(dest ...any) error {
	if r.err != nil {
		return r.err
	}
	for i, value := range r.values {
		reflect.ValueOf(dest[i]).Elem().Set(reflect.ValueOf(value))
	}
	return nil
}

type coverageProofTx struct {
	pgx.Tx
	rows    []pgx.Row
	queries []string
}

func (t *coverageProofTx) QueryRow(_ context.Context, query string, _ ...any) pgx.Row {
	t.queries = append(t.queries, query)
	row := t.rows[0]
	t.rows = t.rows[1:]
	return row
}

func TestDuckDBContextCoverageRequiresDurableIdentityAndEveryRowTemplate(t *testing.T) {
	for _, test := range []struct {
		name, detected           string
		identity, rowValid, want bool
	}{
		{"validated SMS", "smsbackuprestore_xml", true, true, true},
		{"wrong source or handler or failed validation", "smsbackuprestore_xml", false, true, false},
		{"unregistered template", "unknown_xml", true, true, false},
		{"wrong template on one row", "smsbackuprestore_xml", true, false, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			tx := &coverageProofTx{}
			if test.identity {
				tx.rows = append(tx.rows, coverageProofRow{values: []any{"xml", test.detected, uuid.NewString()}})
			} else {
				tx.rows = append(tx.rows, coverageProofRow{err: pgx.ErrNoRows})
			}
			tx.rows = append(tx.rows, coverageProofRow{values: []any{test.rowValid}})
			proof, err := loadDuckDBContextCoverageProof(context.Background(), tx, uuid.New(), uuid.New(), "request")
			if err != nil {
				t.Fatal(err)
			}
			if (proof != nil) != test.want {
				t.Fatalf("proof=%v want=%v", proof, test.want)
			}
			if proof != nil && proof["byte_coverage_proven"] != false {
				t.Fatal("fabricated source coverage")
			}
			for _, condition := range []string{"generation.source_version_id=$2", "source.workflow_id=$3", "receipt.status='success'", "validation.created_at<=generation.created_at", "compatibility.handler_id=generation.parser_id", "compatibility.handler_version=generation.parser_version", "signature.original_object_id=source.original_object_id"} {
				if !strings.Contains(tx.queries[0], condition) {
					t.Fatalf("missing durable bound %s", condition)
				}
			}
		})
	}
}
