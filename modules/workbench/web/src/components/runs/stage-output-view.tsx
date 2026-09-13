// Byline: Claude Code · Sonnet (agent) · 2026-07-20
"use client";

/**
 * Typed rendering of a stage's `output`, keyed by stage `name` per the
 * historical ingest contract (source verification/parse/store/knowledge). An
 * unrecognized stage name (or a shape that doesn't match) falls back to a
 * pretty-printed JSON blob instead of erroring — the spine is a parallel
 * build, so the exact field set was not independently verified.
 */
import { useState } from "react";
import { Copy, Check } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import type {
  RawSourceVerificationOutput,
  KnowledgeOutput,
  ParseOutput,
  StoreOutput,
} from "@/lib/shared/types";

/** Exported so run-detail-dialog.tsx's failed-run banner can reuse it
 * (C2.6 requirement 3) instead of duplicating a copy-to-clipboard button. */
export function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <Button
      type="button"
      variant="ghost"
      size="icon-xs"
      onClick={() => {
        navigator.clipboard.writeText(text).catch(() => {});
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
      }}
      title="Copy"
    >
      {copied ? <Check className="size-3" /> : <Copy className="size-3" />}
    </Button>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-4 py-1 text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className="text-right">{children}</span>
    </div>
  );
}

function RawJson({ value }: { value: unknown }) {
  const text = JSON.stringify(value, null, 2);
  return (
    <div className="relative">
      <div className="absolute right-1 top-1">
        <CopyButton text={text} />
      </div>
      <pre className="max-h-64 overflow-auto rounded-md border bg-muted/30 p-3 text-xs">{text}</pre>
    </div>
  );
}

function RawSourceVerificationView({ output }: { output: RawSourceVerificationOutput }) {
  return (
    <div className="space-y-1">
      {output.sha256 && (
        <Field label="Source fingerprint (SHA-256)">
          <span className="flex items-center gap-1 font-mono text-xs">
            {output.sha256}
            <CopyButton text={output.sha256} />
          </span>
        </Field>
      )}
      {output.artifact_id && <Field label="Artifact ID">{output.artifact_id}</Field>}
      {output.duplicate !== undefined && (
        <Field label="Duplicate">
          <Badge variant={output.duplicate ? "secondary" : "outline"}>
            {output.duplicate ? "duplicate" : "new"}
          </Badge>
        </Field>
      )}
      {output.blob_key !== null && output.blob_key !== undefined && (
        <Field label="Blob key">
          <span className="font-mono text-xs">{String(output.blob_key)}</span>
        </Field>
      )}
    </div>
  );
}

function ParseView({ output }: { output: ParseOutput }) {
  return (
    <div className="space-y-2">
      <div className="space-y-1">
        {output.parser_id && <Field label="Parser">{output.parser_id}</Field>}
        {output.schema_recognized !== undefined && (
          <Field label="Schema recognized">
            <Badge variant={output.schema_recognized ? "default" : "destructive"}>
              {output.schema_recognized ? "yes" : "no"}
            </Badge>
          </Field>
        )}
        {output.record_count !== undefined && <Field label="Records">{output.record_count}</Field>}
        {output.alt_parse !== undefined && (
          <Field label="Fallback parser used">
            <Badge variant={output.alt_parse ? "secondary" : "outline"}>
              {output.alt_parse ? "yes" : "no"}
            </Badge>
          </Field>
        )}
      </div>
      {Array.isArray(output.attempts) && output.attempts.length > 0 && (
        <div>
          <p className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Attempts
          </p>
          <RawJson value={output.attempts} />
        </div>
      )}
      {Array.isArray(output.sample_records) && output.sample_records.length > 0 && (
        <div>
          <p className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Sample records
          </p>
          {/* Server-side already JSON.dumps()+truncates these to 500 chars —
              render as text (a table already got them once). */}
          <div className="max-h-64 space-y-1.5 overflow-y-auto">
            {output.sample_records.map((sample, i) => (
              <pre key={i} className="overflow-x-auto rounded-md border bg-muted/30 p-2 text-xs whitespace-pre-wrap">
                {sample}
              </pre>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function StoreView({ output }: { output: StoreOutput }) {
  return (
    <div className="space-y-1">
      {output.rows_stored !== undefined && <Field label="Rows stored">{output.rows_stored}</Field>}
      {output.table && <Field label="Table">{output.table}</Field>}
    </div>
  );
}

function KnowledgeView({ output }: { output: KnowledgeOutput }) {
  return (
    <div className="space-y-1">
      {output.docs_ingested !== undefined && <Field label="Docs ingested">{output.docs_ingested}</Field>}
      {output.domain && <Field label="Domain">{output.domain}</Field>}
      {output.skipped !== undefined && (
        <Field label="Skipped">
          <Badge variant={output.skipped ? "secondary" : "outline"}>{output.skipped ? "yes" : "no"}</Badge>
        </Field>
      )}
    </div>
  );
}

export function StageOutputView({ stageName, output }: { stageName: string; output: unknown }) {
  if (output === null || output === undefined) {
    return <p className="text-sm text-muted-foreground">No output recorded for this stage.</p>;
  }
  switch (stageName.toLowerCase()) {
    case "custody":
    case "raw_source_verification":
      return <RawSourceVerificationView output={output as RawSourceVerificationOutput} />;
    case "parse":
      return <ParseView output={output as ParseOutput} />;
    case "store":
      return <StoreView output={output as StoreOutput} />;
    case "knowledge":
      return <KnowledgeView output={output as KnowledgeOutput} />;
    default:
      return <RawJson value={output} />;
  }
}
