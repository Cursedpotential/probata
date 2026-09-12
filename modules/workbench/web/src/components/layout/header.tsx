// Byline: Claude Code · Sonnet (agent) · 2026-07-22 (C3: Records/Evidence Queue/Schemas page titles)
// Byline: Codex · GPT-5 · 2026-08-16 (Knowledge + Surreal projection page titles)
// Byline: Codex · GPT-5 · 2026-08-28 (unified product header)
// Byline: Codex · GPT-5 · 2026-08-29 (remove legacy dependency strip)
// Byline: Codex · GPT-5 · 2026-08-29 (fixed single-case scope)
// Byline: Codex · GPT-5 · 2026-08-29 (approved full-width case-context header)
// Byline: Codex · GPT-5.6-Sol · 2026-08-30 (surface navigation title registry)
"use client";

import { AlertTriangle, Loader2, Moon, ShieldCheck, Sun } from "lucide-react";
import { Button } from "@/components/ui/button";
import { SidebarTrigger } from "@/components/ui/sidebar";
import { useFixedCase } from "@/lib/fixed-case-context";
import { navigationTitle } from "@/platform-ui/navigation";
import { useCurrentPath } from "@/lib/router-compat";
import { useTheme } from "@/components/layout/theme-provider";
import { MatterModeSelector } from "@/components/intake/matter-mode-selector";

export function Header() {
  const pathname = useCurrentPath();
  const { theme, setTheme } = useTheme();
  const { matter, primaryCourtCase, loading, error } = useFixedCase();
  const pageTitle = navigationTitle(pathname) || "Evidence & legal operations";

  return (
    <header className="relative z-20 grid h-[74px] shrink-0 grid-cols-[14.5rem_minmax(0,1fr)_auto] items-stretch bg-nav text-nav-foreground">
      <div className="flex items-center gap-3 border-r border-white/15 px-4">
        <SidebarTrigger className="text-nav-foreground/70 hover:bg-white/10 hover:text-nav-foreground" />
        <div className="grid h-9 w-9 place-items-center border border-[#6d7982] bg-[#1f2a33] font-mono text-lg font-semibold">P</div>
        <div className="min-w-0">
          <strong className="block truncate text-sm">The Platform</strong>
          <span className="block truncate text-[10px] text-[#aeb6bc]">Evidence & legal operations</span>
        </div>
      </div>
      <div className="flex min-w-0 flex-col justify-center border-r border-white/10 px-5">
        {loading ? (
          <span className="flex items-center gap-2 text-xs text-[#b9c0c5]"><Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading fixed case</span>
        ) : matter ? (
          <>
            <strong className="truncate text-sm">{matter.title}</strong>
            <span className="truncate text-[11px] text-[#b9c0c5]">
              {primaryCourtCase?.court_name || primaryCourtCase?.caption || "Primary proceeding unavailable"}
              {primaryCourtCase?.case_type ? ` · ${primaryCourtCase.case_type.replaceAll("_", " ")}` : ""}
            </span>
          </>
        ) : (
          <span className="flex items-center gap-2 text-xs text-[#f0b1aa]" title={error ?? undefined}><AlertTriangle className="h-3.5 w-3.5" /> Fixed case unavailable</span>
        )}
      </div>
      <div className="flex items-center gap-4 px-5">
        <MatterModeSelector compact />
        <div className="hidden min-w-0 text-right lg:block">
          <strong className="block truncate text-xs">{pageTitle}</strong>
          <span className="flex items-center justify-end gap-1 text-[10px] text-[#9fe0b9]"><ShieldCheck className="h-3 w-3" /> Fixed scope</span>
        </div>
        <Button
          variant="ghost"
          size="icon"
          aria-label="Toggle color theme"
          title="Toggle color theme"
          className="h-9 w-9 rounded-full border border-white/20 text-nav-foreground/70 hover:bg-white/10 hover:text-nav-foreground"
          onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
        >
          <Sun className="h-4 w-4 rotate-0 scale-100 transition-all dark:-rotate-90 dark:scale-0" />
          <Moon className="absolute h-4 w-4 rotate-90 scale-0 transition-all dark:rotate-0 dark:scale-100" />
        </Button>
      </div>
    </header>
  );
}
