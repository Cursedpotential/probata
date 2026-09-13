// Byline: Codex · GPT-5.6 · 2026-08-29
"use client";

import { FileText, MessageSquareText, Search } from "lucide-react";
import { useMemo, useState } from "react";

import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import type { ProfferPreviewMessage, ProfferPreviewParticipant } from "@/lib/shared/types";

interface PlatformMessageViewerProps {
  messages: ProfferPreviewMessage[];
  participants: ProfferPreviewParticipant[];
  loading: boolean;
  error: string | null;
  previewHandle: string;
  hasMore: boolean;
  onLoadMore: () => void;
}

/** Native Workbench port of SBV's useful viewing behavior over platform rows. */
export function PlatformMessageViewer({
  messages,
  participants,
  loading,
  error,
  previewHandle,
  hasMore,
  onLoadMore,
}: PlatformMessageViewerProps) {
  const [query, setQuery] = useState("");
  const participantMap = useMemo(
    () => new Map(participants.map((participant) => [participant.participant_id, participant])),
    [participants],
  );
  const visibleMessages = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return messages
      .filter((message) => {
        if (!needle) return true;
        const sender = message.sender_participant_id
          ? participantMap.get(message.sender_participant_id)?.display_name ?? ""
          : "";
        return `${message.body} ${sender} ${message.attachments.map((item) => item.filename ?? "").join(" ")}`
          .toLowerCase()
          .includes(needle);
      })
      .sort((left, right) => left.ordinal - right.ordinal);
  }, [messages, participantMap, query]);

  function formatBytes(value: number | null | undefined) {
    if (value === null || value === undefined) return "size unavailable";
    if (value < 1024) return `${value} bytes`;
    return `${(value / 1024).toFixed(1)} KB`;
  }

  return (
    <section className="platform-panel flex min-h-[34rem] flex-col overflow-hidden rounded-md" aria-label="Message records">
      <header className="flex flex-wrap items-center justify-between gap-3 border-b px-4 py-3">
        <div>
          <p className="platform-kicker">SBV viewing client</p>
          <h2 className="mt-1 flex items-center gap-2 text-base font-semibold">
            <MessageSquareText className="size-4" aria-hidden="true" />
            Message records
          </h2>
        </div>
        <Badge variant="outline">{messages.length} platform messages</Badge>
      </header>

      <div className="border-b p-3">
        <label className="relative block">
          <span className="sr-only">Filter message records</span>
          <Search className="pointer-events-none absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
          <Input
            className="pl-9"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Filter messages, people, or record types"
          />
        </label>
      </div>

      <div className="flex-1 overflow-y-auto bg-muted/25 p-4">
        {loading && messages.length === 0 && (
          <p className="text-sm text-muted-foreground" role="status">Loading platform messages…</p>
        )}
        {error && (
          <div className="rounded border border-destructive/40 bg-destructive/5 p-3 text-sm text-destructive" role="alert">
            {error}
          </div>
        )}
        {!loading && !error && visibleMessages.length === 0 && (
          <div className="mx-auto max-w-md py-16 text-center">
            <MessageSquareText className="mx-auto size-8 text-muted-foreground" aria-hidden="true" />
            <p className="mt-3 text-sm font-medium">No message records are available for this attempt yet.</p>
            <p className="mt-1 text-xs text-muted-foreground">
              The client reads normalized platform records; it does not open an SBV SQLite database.
            </p>
          </div>
        )}
        {visibleMessages.length > 0 && (
          <ol className="space-y-3" aria-live="polite">
            {visibleMessages.map((message) => {
              const sender = message.sender_participant_id
                ? participantMap.get(message.sender_participant_id)
                : undefined;
              return (
                <li key={message.message_id} className="flex justify-start">
                  <article className="max-w-[92%] rounded-md border bg-card px-3 py-2 shadow-sm">
                    <header className="mb-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-[11px]">
                      <strong>{sender?.display_name ?? "Unattributed sender"}</strong>
                      {sender?.canonical_address && <span className="font-mono text-muted-foreground">{sender.canonical_address}</span>}
                      <time dateTime={message.sent_at ?? undefined}>
                        {message.sent_at ? new Date(message.sent_at).toLocaleString() : "Timestamp unavailable"}
                      </time>
                      <span className="font-mono">#{message.ordinal}</span>
                    </header>
                    <p className="whitespace-pre-wrap break-words text-sm leading-5">{message.body}</p>
                    <div className="mt-2 space-y-0.5 border-t pt-2 font-mono text-[10px] text-muted-foreground">
                      <div className="break-all">message {message.message_id}</div>
                      <div className="break-all">source {message.source_locator_ref}</div>
                      <div className="break-all">participants {message.participant_ids.join(", ") || "none recorded"}</div>
                    </div>
                    {message.attachments.length > 0 && (
                      <ul className="mt-2 space-y-1 border-t pt-2 text-[11px] text-muted-foreground">
                        {message.attachments.map((attachment) => (
                          <li key={attachment.attachment_id} className="grid grid-cols-[auto_1fr] gap-x-1.5">
                            <FileText className="mt-0.5 size-3" />
                            <div className="min-w-0"><div>{attachment.filename ?? "Attachment"}{attachment.media_type ? ` · ${attachment.media_type}` : ""} · {formatBytes(attachment.byte_length)}</div><div className="break-all font-mono text-[10px]">attachment {attachment.attachment_id}</div><div className="break-all font-mono text-[10px]">source {attachment.source_locator_ref}</div>{attachment.sha256 && <div className="break-all font-mono text-[10px]">sha256 {attachment.sha256}</div>}</div>
                          </li>
                        ))}
                      </ul>
                    )}
                  </article>
                </li>
              );
            })}
          </ol>
        )}
      </div>

      {hasMore && (
        <div className="border-t p-3 text-center">
          <button className="text-xs font-medium underline-offset-4 hover:underline" disabled={loading} onClick={onLoadMore}>
            {loading ? "Loading…" : "Load more messages"}
          </button>
        </div>
      )}

      <footer className="border-t px-4 py-2 text-[11px] text-muted-foreground">
        Attempt {previewHandle} · read-only platform projection · PostgreSQL remains canonical
      </footer>
    </section>
  );
}
