package stagegraph

import (
	"math/bits"
	"testing"
)

// requiredStages is the exact stage list mandated by the Lane C0 spec,
// independent of the registry's own declaration, so a regression that
// silently renames or drops a stage in registry.go still fails a test that
// does not import registry.go's own constant list for its expectations.
var requiredStages = map[StageID]bool{
	RegisterSource:                 true,
	RetainOriginal:                 true,
	AssessSourceRepair:             true,
	ResolveSourceRepair:            true,
	CaptureFilesystemMetadata:      true,
	FingerprintSource:              true,
	InventoryContainer:             true,
	ExtractEmbeddedMetadata:        true,
	SelectParser:                   true,
	ExecuteParser:                  true,
	PersistRawGeneration:           true,
	FingerprintRawRecords:          true,
	FingerprintRawGeneration:       true,
	ReconcileRecordAccounting:      true,
	ReconcileByteCoverage:          true,
	VerifyRawCoverageAgainstSource: true,
	NormalizeGeneration:            true,
	PersistNormalizedGeneration:    true,
	PersistLineage:                 true,
	ValidateRawLineage:             true,
	HashNormalizedRecords:          true,
	HashNormalizedGeneration:       true,
	VerifyNormalizedGeneration:     true,
	PublishPreview:                 true,
	SealGeneration:                 true,
	PublishGeneration:              true,
}

func TestGraphIsAcyclic(t *testing.T) {
	g, err := NewGraph()
	if err != nil {
		t.Fatalf("NewGraph returned an error, graph is not a valid DAG: %v", err)
	}

	order := g.TopologicalOrder()
	if len(order) != len(Stages) {
		t.Fatalf("topological order has %d stages, want %d — some stages are unreachable or cyclic", len(order), len(Stages))
	}

	position := make(map[StageID]int, len(order))
	for i, id := range order {
		position[id] = i
	}
	for _, d := range Stages {
		for _, dep := range d.DependsOn {
			if position[dep] >= position[d.ID] {
				t.Errorf("stage %q is ordered before its dependency %q", d.ID, dep)
			}
		}
	}
}

func TestEveryRequiredStageAppearsExactlyOnce(t *testing.T) {
	seen := make(map[StageID]int, len(Stages))
	for _, d := range Stages {
		seen[d.ID]++
	}

	for id, count := range seen {
		if count != 1 {
			t.Errorf("stage %q appears %d times, want exactly 1", id, count)
		}
	}

	if len(seen) != len(requiredStages) {
		t.Fatalf("registry has %d distinct stages, want %d", len(seen), len(requiredStages))
	}
	for id := range requiredStages {
		if seen[id] != 1 {
			t.Errorf("required stage %q is missing from the registry", id)
		}
	}
	for id := range seen {
		if !requiredStages[id] {
			t.Errorf("registry contains stage %q, which is not in the required stage list", id)
		}
	}
}

func TestOptionalNonMessagingChunkStageIsVersionedAfterNormalizedVerification(t *testing.T) {
	if len(OptionalStages) != 1 {
		t.Fatalf("optional stage count = %d, want exactly the D-158 non-messaging chunk stage", len(OptionalStages))
	}
	d := OptionalStages[0]
	if d.ID != ChunkDocument || d.Responsibility != RespChunk {
		t.Fatalf("optional stage = %+v, want atomic chunk_document_activity", d)
	}
	if len(d.DependsOn) != 1 || d.DependsOn[0] != VerifyNormalizedGeneration {
		t.Fatalf("chunk stage dependencies = %v, want verified normalized generation only", d.DependsOn)
	}
	if requiredStages[ChunkDocument] {
		t.Fatal("non-messaging chunk stage was made mandatory for the messaging path")
	}
}

func TestPublishRequiresAllGates(t *testing.T) {
	g, err := NewGraph()
	if err != nil {
		t.Fatalf("NewGraph failed: %v", err)
	}

	ancestors := g.Ancestors(PublishGeneration)
	for _, d := range Stages {
		if d.ID == PublishGeneration {
			continue
		}
		if !ancestors[d.ID] {
			t.Errorf("stage %q is not a required ancestor of %q; publish could run without it", d.ID, PublishGeneration)
		}
	}
	if len(ancestors) != len(Stages)-1 {
		t.Errorf("publish has %d ancestors, want %d (every other stage)", len(ancestors), len(Stages)-1)
	}
}

func TestNoStageReachesPublishWithoutItsOwnGate(t *testing.T) {
	// Complementary to TestPublishRequiresAllGates: for every non-publish
	// stage, publish must NOT be reachable by walking dependencies starting
	// from that stage skipped — i.e. removing any single stage from the
	// dependency set breaks the chain to publish. We prove this structurally:
	// every stage other than publish itself must have at least one dependent
	// (direct or transitive) that is, or leads to, publish.
	g, err := NewGraph()
	if err != nil {
		t.Fatalf("NewGraph failed: %v", err)
	}

	leadsToPublish := make(map[StageID]bool)
	var walk func(StageID) bool
	visiting := make(map[StageID]bool)
	walk = func(id StageID) bool {
		if id == PublishGeneration {
			return true
		}
		if v, ok := leadsToPublish[id]; ok {
			return v
		}
		if visiting[id] {
			return false
		}
		visiting[id] = true
		defer delete(visiting, id)

		for _, dependent := range g.dependents[id] {
			if walk(dependent) {
				leadsToPublish[id] = true
				return true
			}
		}
		leadsToPublish[id] = false
		return false
	}

	for _, d := range Stages {
		if d.ID == PublishGeneration {
			continue
		}
		if !walk(d.ID) {
			t.Errorf("stage %q has no path to %q; it could be skipped entirely", d.ID, PublishGeneration)
		}
	}
}

func TestFiveHashComputationStagesAreDistinct(t *testing.T) {
	// Five hash computation stages: three context integrity fingerprints
	// (fingerprint_source, fingerprint_raw_records, fingerprint_raw_generation)
	// plus two normalized reproducibility digests (hash_normalized_records,
	// hash_normalized_generation). Context fingerprints are NOT custody H1/H2/H3
	// — those are created only by R04 owner promotion. See vendored/sbv/CUSTODY.md
	// for custody definitions.
	var hashStages []StageID
	for _, d := range Stages {
		if d.Responsibility == RespComputeHash {
			hashStages = append(hashStages, d.ID)
		}
	}

	if len(hashStages) != 5 {
		t.Fatalf("found %d hash-computation stages, want exactly 5: %v", len(hashStages), hashStages)
	}

	want := map[StageID]bool{
		FingerprintSource:        true,
		FingerprintRawRecords:    true,
		FingerprintRawGeneration: true,
		HashNormalizedRecords:    true,
		HashNormalizedGeneration: true,
	}
	seen := make(map[StageID]bool, len(hashStages))
	for _, id := range hashStages {
		if seen[id] {
			t.Errorf("hash-computation stage %q listed more than once", id)
		}
		seen[id] = true
		if !want[id] {
			t.Errorf("unexpected hash-computation stage %q", id)
		}
	}
	for id := range want {
		if !seen[id] {
			t.Errorf("expected hash-computation stage %q not found", id)
		}
	}

	// Distinct results too: five hashes over five different representations
	// (three context fingerprints plus two normalized reproducibility digests)
	// must not collapse to the same receipt name.
	results := make(map[string]StageID, len(hashStages))
	for _, id := range hashStages {
		d, _ := findDescriptor(id)
		if owner, dup := results[d.Result]; dup {
			t.Errorf("hash stages %q and %q share the result label %q", owner, id, d.Result)
		}
		results[d.Result] = id
	}
}

func TestComputeAndVerifyStagesRemainSeparate(t *testing.T) {
	verifyStages := map[StageID]bool{
		VerifyRawCoverageAgainstSource: true,
		VerifyNormalizedGeneration:     true,
	}
	for _, d := range Stages {
		isHash := d.Responsibility == RespComputeHash
		isVerify := d.Responsibility == RespVerify
		if isHash && isVerify {
			t.Errorf("stage %q carries both compute-hash and verify responsibility", d.ID)
		}
		if verifyStages[d.ID] && !isVerify {
			t.Errorf("stage %q was expected to carry verify responsibility, has %v", d.ID, d.Responsibility)
		}
		if isVerify && !verifyStages[d.ID] {
			t.Errorf("unexpected verify-responsibility stage %q", d.ID)
		}
	}
}

func TestNormalizeAndPersistStagesRemainSeparate(t *testing.T) {
	normalize, ok := findDescriptor(NormalizeGeneration)
	if !ok {
		t.Fatal("normalize_generation_activity missing from registry")
	}
	if normalize.Responsibility&RespPersist != 0 {
		t.Errorf("%q must not carry persistence responsibility", NormalizeGeneration)
	}
	if normalize.Responsibility != RespNormalize {
		t.Errorf("%q responsibility = %v, want only RespNormalize", NormalizeGeneration, normalize.Responsibility)
	}

	for _, id := range []StageID{PersistRawGeneration, PersistNormalizedGeneration, PersistLineage} {
		d, ok := findDescriptor(id)
		if !ok {
			t.Fatalf("%q missing from registry", id)
		}
		if d.Responsibility&RespNormalize != 0 {
			t.Errorf("%q must not carry normalize responsibility", id)
		}
		if d.Responsibility != RespPersist {
			t.Errorf("%q responsibility = %v, want only RespPersist", id, d.Responsibility)
		}
	}
}

func TestSealAndPublishStagesRemainSeparate(t *testing.T) {
	seal, ok := findDescriptor(SealGeneration)
	if !ok {
		t.Fatal("seal_generation_activity missing from registry")
	}
	publish, ok := findDescriptor(PublishGeneration)
	if !ok {
		t.Fatal("publish_generation_activity missing from registry")
	}

	if seal.Responsibility&RespPublish != 0 {
		t.Errorf("%q must not carry publish responsibility", SealGeneration)
	}
	if publish.Responsibility&RespSeal != 0 {
		t.Errorf("%q must not carry seal responsibility", PublishGeneration)
	}
	if seal.Responsibility != RespSeal {
		t.Errorf("%q responsibility = %v, want only RespSeal", SealGeneration, seal.Responsibility)
	}
	if publish.Responsibility != RespPublish {
		t.Errorf("%q responsibility = %v, want only RespPublish", PublishGeneration, publish.Responsibility)
	}

	// publish must depend on seal having completed, never the reverse.
	dependsOnSeal := false
	for _, dep := range publish.DependsOn {
		if dep == SealGeneration {
			dependsOnSeal = true
		}
	}
	if !dependsOnSeal {
		t.Errorf("%q must directly depend on %q", PublishGeneration, SealGeneration)
	}
	for _, dep := range seal.DependsOn {
		if dep == PublishGeneration {
			t.Errorf("%q must not depend on %q", SealGeneration, PublishGeneration)
		}
	}
}

func TestParserExecutionHasNoPersistenceResponsibility(t *testing.T) {
	d, ok := findDescriptor(ExecuteParser)
	if !ok {
		t.Fatal("execute_parser_activity missing from registry")
	}
	if d.Responsibility&RespPersist != 0 {
		t.Errorf("%q descriptor carries persistence responsibility; the parser contract forbids it from writing canonical state", ExecuteParser)
	}
	if d.Responsibility != RespParse {
		t.Errorf("%q responsibility = %v, want only RespParse", ExecuteParser, d.Responsibility)
	}
}

func TestEveryDescriptorHasExactlyOneResponsibilityBit(t *testing.T) {
	for _, d := range Stages {
		n := bits.OnesCount32(uint32(d.Responsibility))
		if n != 1 {
			t.Errorf("stage %q has %d responsibility bits set (%v), want exactly 1 — the canon document requires one atomic responsibility per Activity", d.ID, n, d.Responsibility)
		}
	}
}

func TestSafeParallelFanOutAfterRetainOriginal(t *testing.T) {
	fanOut := []StageID{
		CaptureFilesystemMetadata,
		FingerprintSource,
		InventoryContainer,
		ExtractEmbeddedMetadata,
	}
	fanOutSet := make(map[StageID]bool, len(fanOut))
	for _, id := range fanOut {
		fanOutSet[id] = true
	}

	for _, id := range fanOut {
		d, ok := findDescriptor(id)
		if !ok {
			t.Fatalf("%q missing from registry", id)
		}
		if len(d.DependsOn) != 1 || d.DependsOn[0] != ResolveSourceRepair {
			t.Errorf("%q must depend only on %q to be safely parallel after repair resolution, got %v", id, ResolveSourceRepair, d.DependsOn)
		}
		for _, dep := range d.DependsOn {
			if fanOutSet[dep] {
				t.Errorf("%q depends on fan-out sibling %q; fan-out stages must be mutually independent", id, dep)
			}
		}
	}

	g, err := NewGraph()
	if err != nil {
		t.Fatalf("NewGraph failed: %v", err)
	}
	for _, a := range fanOut {
		ancestorsOfA := g.Ancestors(a)
		for _, b := range fanOut {
			if a == b {
				continue
			}
			if ancestorsOfA[b] {
				t.Errorf("%q transitively depends on fan-out sibling %q", a, b)
			}
		}
	}
}

func findDescriptor(id StageID) (Descriptor, bool) {
	for _, d := range Stages {
		if d.ID == id {
			return d, true
		}
	}
	return Descriptor{}, false
}
