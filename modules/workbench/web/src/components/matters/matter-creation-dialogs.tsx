// Byline: Codex · GPT-5 · 2026-08-15 (operator-owned Matter/CourtCase creation)
"use client";

import { useState } from "react";
import { BriefcaseBusiness, Loader2, Scale } from "lucide-react";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { createCourtCase, createMatter } from "@/lib/api-client";
import { useFixedCase } from "@/lib/fixed-case-context";
import type { CourtCase, Matter } from "@/lib/shared/types";

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "The case-management request failed";
}

interface CreateMatterDialogProps {
  onCreated: (matter: Matter) => void;
}

export function CreateMatterDialog({ onCreated }: CreateMatterDialogProps) {
  const { mode } = useFixedCase();
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [partitionKey, setPartitionKey] = useState("");
  const [error, setError] = useState<string | null>(null);

  function reset() {
    setTitle("");
    setDescription("");
    setPartitionKey("");
    setError(null);
  }

  async function submit() {
    if (!title.trim()) return;
    setSaving(true);
    setError(null);
    try {
      const matter = await createMatter({
        title: title.trim(),
        description: description.trim() || undefined,
        partition_key: partitionKey.trim() || undefined,
      }, mode);
      onCreated(matter);
      setOpen(false);
      reset();
    } catch (requestError) {
      setError(errorMessage(requestError));
    } finally {
      setSaving(false);
    }
  }

  return (
    <>
      <Button type="button" onClick={() => setOpen(true)}>
        <BriefcaseBusiness aria-hidden="true" /> New Matter
      </Button>
      <Dialog open={open} onOpenChange={(next) => { setOpen(next); if (!next) reset(); }}>
        <DialogContent aria-busy={saving}>
          <DialogHeader>
            <DialogTitle>Create a Matter workspace</DialogTitle>
            <DialogDescription>
              A Matter is the enduring workspace. A neutral primary CourtCase is created with it; docket facts can be added later.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            {error && <p className="rounded-md border border-destructive p-3 text-sm text-destructive">{error}</p>}
            <div className="space-y-1">
              <Label htmlFor="matter-title">Matter title</Label>
              <Input id="matter-title" maxLength={300} value={title} onChange={(event) => setTitle(event.target.value)} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="matter-description">Description (optional)</Label>
              <Textarea id="matter-description" maxLength={10000} value={description} onChange={(event) => setDescription(event.target.value)} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="matter-partition">Knowledge partition (optional)</Label>
              <Input id="matter-partition" maxLength={200} value={partitionKey} onChange={(event) => setPartitionKey(event.target.value)} placeholder="Generated from the Matter ID when blank" />
              <p className="text-xs text-muted-foreground">This is a retrieval boundary, not a court docket or tenant identifier.</p>
            </div>
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
            <Button type="button" disabled={saving || !title.trim()} onClick={() => void submit()}>
              {saving && <Loader2 className="animate-spin" aria-hidden="true" />} Create Matter
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

interface CreateCourtCaseDialogProps {
  matterId: string;
  onCreated: (courtCase: CourtCase) => void;
}

export function CreateCourtCaseDialog({ matterId, onCreated }: CreateCourtCaseDialogProps) {
  const { mode } = useFixedCase();
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [caption, setCaption] = useState("");
  const [docketNumber, setDocketNumber] = useState("");
  const [courtName, setCourtName] = useState("");
  const [jurisdiction, setJurisdiction] = useState("");
  const [isPrimary, setIsPrimary] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function reset() {
    setCaption("");
    setDocketNumber("");
    setCourtName("");
    setJurisdiction("");
    setIsPrimary(false);
    setError(null);
  }

  async function submit() {
    if (!caption.trim()) return;
    setSaving(true);
    setError(null);
    try {
      const courtCase = await createCourtCase(matterId, {
        caption: caption.trim(),
        docket_number: docketNumber.trim() || undefined,
        court_name: courtName.trim() || undefined,
        jurisdiction: jurisdiction.trim() || undefined,
        is_primary: isPrimary,
      }, mode);
      onCreated(courtCase);
      setOpen(false);
      reset();
    } catch (requestError) {
      setError(errorMessage(requestError));
    } finally {
      setSaving(false);
    }
  }

  return (
    <>
      <Button type="button" size="sm" variant="outline" onClick={() => setOpen(true)}>
        <Scale aria-hidden="true" /> Add proceeding
      </Button>
      <Dialog open={open} onOpenChange={(next) => { setOpen(next); if (!next) reset(); }}>
        <DialogContent aria-busy={saving}>
          <DialogHeader>
            <DialogTitle>Add a court proceeding</DialogTitle>
            <DialogDescription>
              CourtCase metadata stays inside this Matter and never replaces its Knowledge partition.
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-4 sm:grid-cols-2">
            {error && <p className="rounded-md border border-destructive p-3 text-sm text-destructive sm:col-span-2">{error}</p>}
            <div className="space-y-1 sm:col-span-2">
              <Label htmlFor="case-caption">Caption</Label>
              <Input id="case-caption" maxLength={300} value={caption} onChange={(event) => setCaption(event.target.value)} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="case-docket">Docket number (optional)</Label>
              <Input id="case-docket" maxLength={200} value={docketNumber} onChange={(event) => setDocketNumber(event.target.value)} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="case-court">Court (optional)</Label>
              <Input id="case-court" maxLength={500} value={courtName} onChange={(event) => setCourtName(event.target.value)} />
            </div>
            <div className="space-y-1 sm:col-span-2">
              <Label htmlFor="case-jurisdiction">Jurisdiction (optional)</Label>
              <Input id="case-jurisdiction" maxLength={300} value={jurisdiction} onChange={(event) => setJurisdiction(event.target.value)} />
            </div>
            <label className="flex items-center gap-2 text-sm sm:col-span-2">
              <input type="checkbox" checked={isPrimary} onChange={(event) => setIsPrimary(event.target.checked)} />
              Make this the default proceeding for the Matter’s Knowledge partition
            </label>
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
            <Button type="button" disabled={saving || !caption.trim()} onClick={() => void submit()}>
              {saving && <Loader2 className="animate-spin" aria-hidden="true" />} Add proceeding
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
