// Command proposal-bundle freezes and verifies Proffer's attempt-local DuckDB
// proposal manifests without linking the Go engine to a CGO DuckDB driver.
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/Cursedpotential/probata/engine/proposal"
)

const maxManifestBytes = 16 << 20

type artifactFlags []string

func (values *artifactFlags) String() string { return strings.Join(*values, ",") }
func (values *artifactFlags) Set(value string) error {
	if strings.TrimSpace(value) == "" {
		return errors.New("artifact must use name=absolute-path")
	}
	*values = append(*values, value)
	return nil
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	var err error
	switch os.Args[1] {
	case "freeze":
		err = freeze(os.Args[2:])
	case "bundle":
		err = bundle(os.Args[2:])
	case "verify":
		err = verify(os.Args[2:])
	default:
		usage()
	}
	if err != nil {
		_, _ = fmt.Fprintln(os.Stderr, "proposal-bundle:", err)
		os.Exit(1)
	}
}

func usage() {
	_, _ = fmt.Fprintln(os.Stderr, "usage: proposal-bundle freeze|bundle|verify [options]")
	os.Exit(2)
}

func freeze(arguments []string) error {
	flags := flag.NewFlagSet("freeze", flag.ContinueOnError)
	input := flags.String("input", "", "building logical manifest JSON")
	output := flags.String("output", "", "new frozen logical manifest JSON")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	var building proposal.Manifest
	if err := readJSON(*input, &building); err != nil {
		return fmt.Errorf("read building manifest: %w", err)
	}
	frozen, err := proposal.Freeze(building)
	if err != nil {
		return fmt.Errorf("freeze logical proposal: %w", err)
	}
	if err := writeJSONExclusive(*output, frozen); err != nil {
		return fmt.Errorf("write frozen manifest: %w", err)
	}
	return nil
}

func bundle(arguments []string) error {
	flags := flag.NewFlagSet("bundle", flag.ContinueOnError)
	manifestPath := flags.String("manifest", "", "frozen logical manifest JSON")
	databasePath := flags.String("database", "", "closed proposal.duckdb")
	output := flags.String("output", "", "new finalized bundle envelope JSON")
	var artifactArgs artifactFlags
	flags.Var(&artifactArgs, "artifact", "repeatable name=absolute-path external artifact")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	var manifest proposal.Manifest
	if err := readJSON(*manifestPath, &manifest); err != nil {
		return fmt.Errorf("read frozen manifest: %w", err)
	}
	databaseDigest, databaseBytes, err := hashRegularFile(*databasePath)
	if err != nil {
		return fmt.Errorf("hash proposal database: %w", err)
	}
	external := make([]proposal.BundleArtifact, 0, len(artifactArgs))
	for _, raw := range artifactArgs {
		name, path, ok := strings.Cut(raw, "=")
		name, path = strings.TrimSpace(name), strings.TrimSpace(path)
		if !ok || name == "" || path == "" {
			return fmt.Errorf("artifact %q must use name=absolute-path", raw)
		}
		digest, bytes, hashErr := hashRegularFile(path)
		if hashErr != nil {
			return fmt.Errorf("hash artifact %q: %w", name, hashErr)
		}
		external = append(external, proposal.BundleArtifact{
			Name: name, Locator: path, ByteDigest: digest, Bytes: bytes,
		})
	}
	envelope, err := proposal.FinalizeBundle(manifest, proposal.BundleEnvelope{
		SchemaVersion:      manifest.SchemaVersion,
		OperationID:        manifest.OperationID,
		AttemptID:          manifest.AttemptID,
		ProposalDigest:     manifest.ProposalDigest,
		DatabaseLocator:    *databasePath,
		DatabaseByteDigest: databaseDigest,
		DatabaseBytes:      databaseBytes,
		ExternalArtifacts:  external,
		FinalizedAt:        time.Now().UTC(),
	})
	if err != nil {
		return fmt.Errorf("finalize bundle: %w", err)
	}
	if err := writeJSONExclusive(*output, envelope); err != nil {
		return fmt.Errorf("write bundle envelope: %w", err)
	}
	return nil
}

func verify(arguments []string) error {
	flags := flag.NewFlagSet("verify", flag.ContinueOnError)
	manifestPath := flags.String("manifest", "", "frozen logical manifest JSON")
	bundlePath := flags.String("bundle", "", "finalized bundle envelope JSON")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	var manifest proposal.Manifest
	if err := readJSON(*manifestPath, &manifest); err != nil {
		return fmt.Errorf("read frozen manifest: %w", err)
	}
	var envelope proposal.BundleEnvelope
	if err := readJSON(*bundlePath, &envelope); err != nil {
		return fmt.Errorf("read bundle envelope: %w", err)
	}
	if err := envelope.ValidateFor(manifest); err != nil {
		return fmt.Errorf("validate bundle contract: %w", err)
	}
	digest, bytes, err := hashRegularFile(envelope.DatabaseLocator)
	if err != nil {
		return fmt.Errorf("hash proposal database: %w", err)
	}
	if !strings.EqualFold(digest, envelope.DatabaseByteDigest) || bytes != envelope.DatabaseBytes {
		return errors.New("proposal database bytes do not match finalized bundle")
	}
	for _, artifact := range envelope.ExternalArtifacts {
		digest, bytes, hashErr := hashRegularFile(artifact.Locator)
		if hashErr != nil {
			return fmt.Errorf("hash external artifact %q: %w", artifact.Name, hashErr)
		}
		if !strings.EqualFold(digest, artifact.ByteDigest) || bytes != artifact.Bytes {
			return fmt.Errorf("external artifact %q does not match finalized bundle", artifact.Name)
		}
	}
	return nil
}

func readJSON(path string, destination any) error {
	if strings.TrimSpace(path) == "" {
		return errors.New("absolute JSON path is required")
	}
	file, err := openRegular(path)
	if err != nil {
		return err
	}
	defer file.Close()
	decoder := json.NewDecoder(io.LimitReader(file, maxManifestBytes+1))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return errors.New("JSON input must contain exactly one object")
	}
	return nil
}

func openRegular(path string) (*os.File, error) {
	if !filepath.IsAbs(path) || strings.TrimSpace(path) != path {
		return nil, errors.New("path must be absolute and trimmed")
	}
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return nil, errors.New("path must name a regular non-symlink file")
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	opened, err := file.Stat()
	if err != nil || !opened.Mode().IsRegular() || !os.SameFile(info, opened) {
		file.Close()
		return nil, errors.New("file identity changed while opening")
	}
	return file, nil
}

func hashRegularFile(path string) (string, int64, error) {
	file, err := openRegular(path)
	if err != nil {
		return "", 0, err
	}
	defer file.Close()
	hash := sha256.New()
	bytes, err := io.Copy(hash, file)
	if err != nil {
		return "", 0, err
	}
	return hex.EncodeToString(hash.Sum(nil)), bytes, nil
}

func writeJSONExclusive(path string, value any) error {
	if !filepath.IsAbs(path) || strings.TrimSpace(path) != path {
		return errors.New("output path must be absolute and trimmed")
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")
	encodeErr := encoder.Encode(value)
	closeErr := file.Close()
	if encodeErr != nil {
		return encodeErr
	}
	return closeErr
}
