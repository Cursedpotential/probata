// Command atomicparse runs one SBV parse-only decoder directly against one
// file, with no DB, no Temporal, no custody writes. It exists solely to
// produce owner-authorized atomic parse-test statistics.
package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/lowcarbdev/sbv/pkg/parseonly"
)

// localSink is a throwaway filesystem-only ImmutableArtifactSink: no DB, no
// custody, no registrar. It exists only so MMS/attachment records inside an
// SBV parse can complete instead of aborting the whole run.
type localSink struct {
	root string
}

func newLocalSink(root string) (*localSink, error) {
	if err := os.MkdirAll(root, 0o755); err != nil {
		return nil, err
	}
	return &localSink{root: root}, nil
}

func (s *localSink) ArtifactDir(_ context.Context, sourceAssociation, attemptID string) (string, error) {
	dir := filepath.Join(s.root, safe(sourceAssociation), safe(attemptID))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	return dir, nil
}

func (s *localSink) Store(_ context.Context, artifact parseonly.Artifact) (parseonly.ArtifactLocator, error) {
	f, err := os.Open(artifact.StagedPath)
	if err != nil {
		return parseonly.ArtifactLocator{}, err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return parseonly.ArtifactLocator{}, err
	}
	digest := hex.EncodeToString(h.Sum(nil))
	return parseonly.ArtifactLocator{
		StorageClass: "local-test",
		URI:          "file://" + artifact.StagedPath,
		ContentHash:  digest,
	}, nil
}

func (s *localSink) CompleteAttempt(_ context.Context, _, _ string) error { return nil }

func (s *localSink) QuarantineAttempt(_ context.Context, sourceAssociation, attemptID, reason string) error {
	fmt.Fprintf(os.Stderr, "quarantine attempt %s/%s: %s\n", sourceAssociation, attemptID, reason)
	return nil
}

func safe(s string) string {
	out := make([]rune, 0, len(s))
	for _, r := range s {
		if r == '/' || r == '\\' || r == ':' || r == ' ' {
			out = append(out, '_')
			continue
		}
		out = append(out, r)
	}
	if len(out) == 0 {
		return "x"
	}
	return string(out)
}

type rejectSample struct {
	pos     string
	reason  string
	rawLen  int
	excerpt string
}

// maskDigits renders a bounded excerpt with every digit replaced, so phone
// numbers, dates and message ids never reach a report.
func maskDigits(raw []byte, limit int) string {
	if len(raw) > limit {
		raw = raw[:limit]
	}
	out := make([]rune, 0, limit)
	for _, r := range string(raw) {
		switch {
		case r >= '0' && r <= '9':
			out = append(out, '#')
		case r == '\n' || r == '\r':
			out = append(out, ' ')
		default:
			out = append(out, r)
		}
	}
	return string(out)
}

func countNULs(path string) (int64, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	buf := make([]byte, 1<<20)
	var total int64
	for {
		n, err := f.Read(buf)
		for _, b := range buf[:n] {
			if b == 0 {
				total++
			}
		}
		if err == io.EOF {
			return total, nil
		}
		if err != nil {
			return total, err
		}
	}
}

func main() {
	format := flag.String("format", "auto", `canonical parseonly format id, or "auto" to detect`)
	path := flag.String("file", "", "path to source file")
	sinkDir := flag.String("sinkdir", "", "scratch dir for attachment staging (required if format may carry attachments)")
	flag.Parse()
	if *path == "" {
		fmt.Fprintln(os.Stderr, "usage: atomicparse [-format <fmt>|auto] -file <path> [-sinkdir <dir>]")
		os.Exit(2)
	}

	f, err := os.Open(*path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "open file: %v\n", err)
		os.Exit(1)
	}
	defer f.Close()

	// Count NUL bytes and, when asked, detect the format from the real head
	// rather than guessing: a guessed format can parse to zero records with no
	// error at all.
	nulCount, scanErr := countNULs(*path)
	if scanErr != nil {
		fmt.Fprintf(os.Stderr, "scan file: %v\n", scanErr)
		os.Exit(1)
	}
	detected, detectOK := "", false
	head := make([]byte, parseonly.DetectHeadBytes)
	n, _ := io.ReadFull(f, head)
	detected, detectOK = parseonly.DetectFormat(head[:n], filepath.Base(*path))
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		fmt.Fprintf(os.Stderr, "rewind file: %v\n", err)
		os.Exit(1)
	}
	resolved := *format
	if resolved == "" || resolved == "auto" {
		if !detectOK {
			fmt.Fprintf(os.Stderr, "no SBV importer claims %s\n", *path)
			os.Exit(1)
		}
		resolved = detected
	}

	importer, err := parseonly.New(resolved)
	if err != nil {
		fmt.Fprintf(os.Stderr, "resolve importer: %v\n", err)
		os.Exit(1)
	}

	var parsed, rejected int
	rejectReasons := map[string]int{}
	var rejectSamples []rejectSample
	var minT, maxT *time.Time
	participants := map[string]bool{}
	var participantOrder []string
	var attachments int
	var attachmentFailures int
	type firstRec struct {
		sender string
		ts     string
	}
	var firstTwo []firstRec

	emit := func(_ context.Context, rec parseonly.Record) error {
		switch rec.Status {
		case parseonly.StatusParsed:
			parsed++
			if rec.OccurredAt != nil {
				t := *rec.OccurredAt
				if minT == nil || t.Before(*minT) {
					minT = &t
				}
				if maxT == nil || t.After(*maxT) {
					maxT = &t
				}
			}
			for _, p := range rec.Participants {
				if p == "" {
					continue
				}
				if !participants[p] {
					participants[p] = true
					participantOrder = append(participantOrder, p)
				}
			}
			if rec.Sender != "" && !participants[rec.Sender] {
				participants[rec.Sender] = true
				participantOrder = append(participantOrder, rec.Sender)
			}
			attachments += len(rec.Attachments)
			attachmentFailures += len(rec.AttachmentFailures)
			if len(firstTwo) < 2 {
				ts := ""
				if rec.OccurredAt != nil {
					ts = rec.OccurredAt.Format(time.RFC3339)
				}
				firstTwo = append(firstTwo, firstRec{sender: rec.Sender, ts: ts})
			}
		case parseonly.StatusRejected:
			rejected++
			reason := rec.StatusReason
			if reason == "" {
				reason = "(no reason given)"
			}
			rejectReasons[reason]++
			if len(rejectSamples) < 5 {
				rejectSamples = append(rejectSamples, rejectSample{
					pos: rec.SourcePos, reason: reason, rawLen: len(rec.Raw),
					excerpt: maskDigits(rec.Raw, 200),
				})
			}
		}
		return nil
	}

	start := time.Now()
	var runErr error
	if *sinkDir != "" {
		sink, sErr := newLocalSink(*sinkDir)
		if sErr != nil {
			fmt.Fprintf(os.Stderr, "create local sink: %v\n", sErr)
			os.Exit(1)
		}
		runErr = importer.ParseWithArtifacts(context.Background(), f, filepath.Base(*path), sink, emit)
	} else {
		runErr = importer.Parse(context.Background(), f, emit)
	}
	elapsed := time.Since(start)

	fmt.Printf("=== %s (%s) ===\n", *path, resolved)
	fmt.Printf("format_requested: %s\n", *format)
	fmt.Printf("format_detected: %s (claimed=%v)\n", detected, detectOK)
	fmt.Printf("nul_bytes: %d\n", nulCount)
	fmt.Printf("wall_time: %s\n", elapsed)
	if runErr != nil {
		fmt.Printf("run_error: %v\n", runErr)
	}
	fmt.Printf("parsed: %d\n", parsed)
	fmt.Printf("rejected: %d\n", rejected)
	if len(rejectReasons) > 0 {
		reasons := make([]string, 0, len(rejectReasons))
		for r := range rejectReasons {
			reasons = append(reasons, r)
		}
		sort.Strings(reasons)
		fmt.Println("reject_reasons:")
		for _, r := range reasons {
			fmt.Printf("  %dx: %s\n", rejectReasons[r], r)
		}
		fmt.Println("reject_samples (digits masked, never message bodies verbatim):")
		for _, s := range rejectSamples {
			fmt.Printf("  pos=%s raw_bytes=%d reason=%s\n", s.pos, s.rawLen, s.reason)
			fmt.Printf("    first200_masked: %s\n", s.excerpt)
		}
	}
	if minT != nil {
		fmt.Printf("date_min: %s\n", minT.Format(time.RFC3339))
		fmt.Printf("date_max: %s\n", maxT.Format(time.RFC3339))
	} else {
		fmt.Println("date_min: (none)")
	}
	fmt.Printf("participants: %d\n", len(participantOrder))
	limit := 3
	if len(participantOrder) < limit {
		limit = len(participantOrder)
	}
	fmt.Printf("participants_first3: %v\n", participantOrder[:limit])
	fmt.Printf("attachments: %d\n", attachments)
	fmt.Printf("attachment_failures: %d\n", attachmentFailures)
	for i, rec := range firstTwo {
		fmt.Printf("first_record_%d: sender=%q ts=%q\n", i+1, rec.sender, rec.ts)
	}
}
