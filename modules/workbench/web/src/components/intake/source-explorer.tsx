"use client";

import {
  type ColumnDef,
  type ExpandedState,
  type Row,
  flexRender,
  getCoreRowModel,
  getExpandedRowModel,
  useReactTable,
} from "@tanstack/react-table";
import { ChevronDown, ChevronLeft, ChevronRight, FileText, FolderOpen, Loader2, Search, X } from "lucide-react";
import { useMemo, useState } from "react";

import { Button } from "@/components/ui/button";
import type { ProfferSourceBrowserResponse, ProfferSourceObject, ProfferSourcePrefix } from "@/lib/shared/types";

type SourceRow = ProfferSourcePrefix | ProfferSourceObject;

function bytes(value: number) {
  if (value < 1024) return `${value} bytes`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / (1024 * 1024)).toFixed(1)} MB`;
}

function parentPrefix(prefix: string) {
  return prefix.replace(/[^/]+\/$/, "");
}

function breadcrumbParts(prefix: string) {
  const parts = prefix.split("/").filter(Boolean);
  return parts.map((label, index) => ({ label, prefix: `${parts.slice(0, index + 1).join("/")}/` }));
}

export function SourceExplorer({
  response,
  loading,
  error,
  rootId,
  prefix,
  query,
  fileTypes,
  onRootChange,
  onPrefixChange,
  onQueryChange,
  onFileTypesChange,
  onSelect,
  onLoadMore,
}: {
  response: ProfferSourceBrowserResponse | null;
  loading: boolean;
  error: string | null;
  rootId: string;
  prefix: string;
  query: string;
  fileTypes: string[];
  onRootChange: (rootId: string) => void;
  onPrefixChange: (prefix: string) => void;
  onQueryChange: (query: string) => void;
  onFileTypesChange: (fileTypes: string[]) => void;
  onSelect: (source: ProfferSourceObject) => void;
  onLoadMore: () => void;
}) {
  const [expanded, setExpanded] = useState<ExpandedState>({});
  const rows = useMemo<SourceRow[]>(() => [...(response?.prefixes ?? []), ...(response?.objects ?? [])], [response]);
  const activeRoot = rootId || response?.active_root_id || "";
  const activeRootRecord = response?.available_roots.find((root) => root.root_id === activeRoot) ?? null;
  const availableFileTypes = response?.available_file_types ?? [];
  const parts = breadcrumbParts(prefix);

  const columns = useMemo<ColumnDef<SourceRow>[]>(() => [
    {
      id: "expand",
      header: "Details",
      cell: ({ row }) => row.original.kind === "object" ? (
        <button
          type="button"
          className="grid h-8 w-8 place-items-center border text-muted-foreground hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          aria-label={`${row.getIsExpanded() ? "Hide" : "Show"} details for ${row.original.name}`}
          aria-expanded={row.getIsExpanded()}
          onClick={row.getToggleExpandedHandler()}
        >
          {row.getIsExpanded() ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
        </button>
      ) : null,
    },
    {
      id: "name",
      header: "Name",
      cell: ({ row }) => (
        <button
          type="button"
          className="flex min-w-0 items-center gap-2 text-left font-medium hover:text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          onClick={() => row.original.kind === "prefix" ? onPrefixChange(row.original.prefix) : onSelect(row.original)}
        >
          {row.original.kind === "prefix" ? <FolderOpen className="h-4 w-4 shrink-0" /> : <FileText className="h-4 w-4 shrink-0" />}
          <span className="break-words">{row.original.name}</span>
        </button>
      ),
    },
    {
      id: "kind",
      header: "Type",
      cell: ({ row }) => row.original.kind === "prefix" ? "Folder" : row.original.file_kind || row.original.extension || "File",
    },
    {
      id: "location",
      header: "Location",
      cell: ({ row }) => row.original.kind === "prefix" ? row.original.prefix : row.original.relative_parent || "/",
    },
    {
      id: "size",
      header: "Size",
      cell: ({ row }) => row.original.kind === "object" ? bytes(row.original.byte_length) : "—",
    },
    {
      id: "modified",
      header: "Modified",
      cell: ({ row }) => row.original.kind === "object" && row.original.last_modified
        ? new Date(row.original.last_modified).toLocaleString()
        : "—",
    },
  ], [onPrefixChange, onSelect]);

  // TanStack Table intentionally owns its imperative row model; React Compiler
  // skips memoizing this component while the table remains deterministic.
  // eslint-disable-next-line react-hooks/incompatible-library
  const table = useReactTable({
    data: rows,
    columns,
    state: { expanded },
    onExpandedChange: setExpanded,
    getRowId: (row) => row.kind === "prefix" ? `prefix:${row.prefix}` : `object:${row.source_ref}`,
    getRowCanExpand: (row) => row.original.kind === "object",
    getCoreRowModel: getCoreRowModel(),
    getExpandedRowModel: getExpandedRowModel(),
    manualFiltering: true,
  });

  return (
    <section className="platform-panel mx-auto max-w-[1180px] overflow-hidden" aria-labelledby="source-explorer-title">
      <header className="border-b px-5 py-4">
        <p className="platform-kicker mb-1">Default ingestion point</p>
        <h2 id="source-explorer-title" className="text-xl font-semibold">Import source</h2>
        <p className="mt-1 text-sm text-muted-foreground">Browse approved OpenList-backed R2 locations. Search and type filters run against the selected backing root.</p>
      </header>

      <div className="grid gap-4 border-b bg-card p-4 lg:grid-cols-[minmax(15rem,0.8fr)_minmax(20rem,1.2fr)]">
        <label className="grid gap-1.5 text-xs font-semibold">
          Source location
          <select
            value={activeRoot}
            onChange={(event) => onRootChange(event.target.value)}
            className="h-10 border bg-background px-3 font-normal"
            disabled={loading || !response?.available_roots.length}
          >
            {!response?.available_roots.length && <option value="">Loading approved locations</option>}
            {response?.available_roots.map((root) => (
              <option key={root.root_id} value={root.root_id}>{root.label}{root.temporary ? " (temporary)" : ""}</option>
            ))}
          </select>
          {activeRootRecord && (
            <span className="grid gap-0.5 border bg-accent/20 p-2 font-normal text-muted-foreground">
              <span>OpenList / R2 bucket <code className="text-foreground">{activeRootRecord.bucket}</code>{activeRootRecord.temporary ? " · temporary source" : ""}</span>
              <span className="break-all font-mono text-[10px]">{activeRootRecord.root_ref}</span>
            </span>
          )}
        </label>

        <label className="grid gap-1.5 text-xs font-semibold">
          Search the full source location
          <span className="relative">
            <Search className="pointer-events-none absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
            <input
              className="h-10 w-full border bg-background pl-9 pr-10 font-normal"
              value={query}
              onChange={(event) => onQueryChange(event.target.value)}
              placeholder="Search names and paths in this R2 root"
              aria-label="Search the full source location"
            />
            {query && (
              <button type="button" className="absolute right-1 top-1 grid h-8 w-8 place-items-center text-muted-foreground hover:text-foreground" onClick={() => onQueryChange("")} aria-label="Clear source search">
                <X className="h-4 w-4" />
              </button>
            )}
          </span>
        </label>

        <fieldset className="lg:col-span-2">
          <legend className="text-xs font-semibold">File types</legend>
          <div className="mt-2 flex flex-wrap gap-2">
            {availableFileTypes.map((fileType) => {
              const checked = fileTypes.includes(fileType);
              return (
                <label key={fileType} className="flex min-h-8 cursor-pointer items-center gap-2 border bg-background px-3 text-xs">
                  <input
                    type="checkbox"
                    checked={checked}
                    onChange={() => onFileTypesChange(checked ? fileTypes.filter((value) => value !== fileType) : [...fileTypes, fileType])}
                  />
                  {fileType === "archive" ? "ZIP / archive" : fileType}
                </label>
              );
            })}
            {!availableFileTypes.length && <span className="text-xs text-muted-foreground">File-type choices load from the selected backing source.</span>}
            {(query || fileTypes.length > 0) && <Button type="button" variant="outline" size="sm" onClick={() => { onQueryChange(""); onFileTypesChange([]); }}>Clear filters</Button>}
          </div>
        </fieldset>
      </div>

      <nav className="flex min-h-12 flex-wrap items-center gap-1 border-b px-4 py-2 text-xs" aria-label="Source directory path">
        {prefix && <Button type="button" variant="outline" size="sm" onClick={() => onPrefixChange(parentPrefix(prefix))}><ChevronLeft className="h-4 w-4" /> Back</Button>}
        <button type="button" className="px-2 py-1 font-semibold hover:text-primary" onClick={() => onPrefixChange("")}>Root</button>
        {parts.map((part) => (
          <span key={part.prefix} className="flex items-center gap-1">
            <ChevronRight className="h-3 w-3 text-muted-foreground" />
            <button type="button" className="max-w-52 truncate px-1 py-1 hover:text-primary" onClick={() => onPrefixChange(part.prefix)}>{part.label}</button>
          </span>
        ))}
      </nav>

      {response && (query || fileTypes.length > 0) && (
        <div className="border-b bg-accent/30 px-4 py-2 text-xs text-muted-foreground" role="status">
          {response.search_complete
            ? `Backing-source search complete after scanning ${response.scanned_count.toLocaleString()} entries.`
            : `Search is incomplete after scanning ${response.scanned_count.toLocaleString()} entries.`}
          {response.scan_limit_reached && " The backing-source scan limit was reached; narrow the search before relying on absence."}
        </div>
      )}

      <div className="min-h-[280px] overflow-x-auto">
        {loading && !response ? (
          <div className="flex items-center gap-2 p-5 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" /> Loading approved R2 source locations</div>
        ) : error ? (
          <div className="p-5 text-sm text-destructive" role="alert">{error}</div>
        ) : rows.length === 0 ? (
          <div className="px-5 py-14 text-center text-sm text-muted-foreground">
            <strong className="block text-foreground">No sources matched this backing-source view.</strong>
            <span className="mt-1 block">Clear filters, go back a folder, or choose another approved source location.</span>
          </div>
        ) : (
          <table className="w-full min-w-[860px] border-collapse text-left text-xs" aria-label="Source directory tree and files">
            <thead className="border-b bg-muted/40 text-muted-foreground">
              {table.getHeaderGroups().map((headerGroup) => (
                <tr key={headerGroup.id}>
                  {headerGroup.headers.map((header) => <th key={header.id} scope="col" className="px-3 py-2 font-semibold">{flexRender(header.column.columnDef.header, header.getContext())}</th>)}
                </tr>
              ))}
            </thead>
            <tbody className="divide-y">
              {table.getRowModel().rows.map((row) => (
                <FragmentRow key={row.id} row={row} columnCount={columns.length} onSelect={onSelect} />
              ))}
            </tbody>
          </table>
        )}
      </div>

      <footer className="flex flex-wrap items-center justify-between gap-3 border-t bg-card px-4 py-3 text-xs text-muted-foreground">
        <span>{response ? `${response.objects.length} files and ${response.prefixes.length} folders returned` : "Waiting for source index"}</span>
        <div className="flex items-center gap-3">
          {loading && response && <span className="flex items-center gap-1"><Loader2 className="h-3.5 w-3.5 animate-spin" /> Refreshing</span>}
          {response?.is_truncated && <Button variant="outline" size="sm" onClick={onLoadMore} disabled={loading}>Load more</Button>}
        </div>
      </footer>
    </section>
  );
}

function FragmentRow({ row, columnCount, onSelect }: { row: Row<SourceRow>; columnCount: number; onSelect: (source: ProfferSourceObject) => void }) {
  const source = row.original.kind === "object" ? row.original : null;
  return (
    <>
      <tr className="align-top hover:bg-accent/30">
        {row.getVisibleCells().map((cell) => <td key={cell.id} className="max-w-[22rem] px-3 py-3 text-xs">{flexRender(cell.column.columnDef.cell, cell.getContext())}</td>)}
      </tr>
      {row.getIsExpanded() && source && (
        <tr>
          <td colSpan={columnCount} className="border-t bg-muted/20 px-5 py-4">
            <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
              <Detail label="R2 source reference" value={source.source_ref} />
              <Detail label="Bucket" value={source.bucket} />
              <Detail label="Media type" value={source.media_type || "Not reported"} />
              <Detail label="Archive format" value={source.archive_format || "Not an identified archive"} />
              <Detail label="Object key" value={source.key} />
              <Detail label="ETag" value={source.etag || "Not reported"} />
              <Detail label="Process note" value={source.intake_note || "Ready for source inspection"} />
            </div>
            <Button className="mt-4" size="sm" onClick={() => onSelect(source)}>Inspect this source</Button>
          </td>
        </tr>
      )}
    </>
  );
}

function Detail({ label, value }: { label: string; value: string }) {
  return <div><span className="text-[10px] text-muted-foreground">{label}</span><span className="mt-1 block break-all font-mono text-[11px]">{value}</span></div>;
}
