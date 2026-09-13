// New Run uses the same context-intake surface as /intake, never the legacy Python run port.
import { useEffect, useState } from "react";
import { UnifiedIntake } from "@/components/intake/unified-intake";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { listFiles } from "@/lib/api-client";
import { useNewRunDialog } from "@/lib/new-run-dialog-context";
import type { StagedFile } from "@/lib/shared/types";

export function NewRunDialog() {
  const { open, prefill, closeNewRun } = useNewRunDialog();
  const [files, setFiles] = useState<StagedFile[]>([]);
  const [selectedId, setSelectedId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  useEffect(() => {
    if (!open) return;
    let cancelled = false;
    queueMicrotask(() => {
      if (cancelled) return;
      setSelectedId(prefill?.stagedId ?? "");
      setError(null);
      setLoading(true);
      listFiles({ status: "staged" }).then((rows) => {
        if (!cancelled) setFiles(rows);
      }).catch(() => {
        if (!cancelled) setError("Staged sources could not be listed. Local and R2 intake remain available.");
      }).finally(() => {
        if (!cancelled) setLoading(false);
      });
    });
    return () => { cancelled = true; };
  }, [open, prefill]);
  const staged = files.find((file) => file.id === selectedId);
  return (
    <Dialog open={open} onOpenChange={(next) => !next && closeNewRun()}>
      <DialogContent className="max-h-[95vh] overflow-y-auto sm:max-w-[95vw]">
        <DialogHeader>
          <DialogTitle>New context import</DialogTitle>
          <DialogDescription>Use the engine intake flow. Context ingestion does not promote evidence or create custody.</DialogDescription>
        </DialogHeader>
        <label className="grid gap-2 text-sm">
          Source
          <select aria-label="Staged source" className="rounded border bg-background p-2" value={selectedId} onChange={(event) => setSelectedId(event.target.value)}>
            <option value="">Choose a local file or browse R2</option>
            {files.map((file) => <option key={file.id} value={file.id}>{file.name}</option>)}
          </select>
        </label>
        {error && <p role="alert">{error}</p>}
        {selectedId && !staged ? <p role="status">{loading ? "Loading selected staged source…" : "The selected staged source is unavailable. Choose another source above."}</p> : open && <UnifiedIntake key={selectedId || "new"} stagedSource={staged ? { id: staged.id, name: staged.name, byte_length: staged.size } : undefined} />}
      </DialogContent>
    </Dialog>
  );
}
