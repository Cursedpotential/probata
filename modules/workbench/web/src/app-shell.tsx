// Byline: Codex · GPT-5.6-Sol · 2026-08-30
import { Outlet } from "@tanstack/react-router";

import { AppSidebar } from "@/components/layout/app-sidebar";
import { Header } from "@/components/layout/header";
import { ThemeProvider } from "@/components/layout/theme-provider";
import { SidebarProvider } from "@/components/ui/sidebar";
import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { FixedCaseProvider } from "@/lib/fixed-case-context";
import { NewRunDialogProvider } from "@/lib/new-run-dialog-context";
import { NewRunDialog } from "@/components/runs/new-run-dialog";
import { RefreshProvider } from "@/lib/refresh-context";

export function AppShell() {
  return (
    <ThemeProvider>
      <RefreshProvider>
        <FixedCaseProvider>
          <NewRunDialogProvider>
          <SidebarProvider
            className="flex h-screen flex-col overflow-hidden"
            style={{ "--sidebar-width": "14.5rem", "--shell-header-height": "74px" } as React.CSSProperties}
          >
            <TooltipProvider>
              <Header />
              <div className="flex min-h-0 flex-1">
                <AppSidebar />
                <div className="flex min-h-0 min-w-0 flex-1 flex-col bg-background">
                  <main className="platform-workspace relative flex-1 overflow-auto">
                    <Outlet />
                  </main>
                  <footer className="hidden h-9 shrink-0 items-center justify-between border-t border-[#3c4952] bg-[#172129] px-5 text-[10px] text-[#aeb7bc] md:flex">
                    <span>PostgreSQL remains canonical authority</span>
                    <span>Surface actions require governed receipts</span>
                  </footer>
                </div>
              </div>
                <Toaster />
                <NewRunDialog />
            </TooltipProvider>
          </SidebarProvider>
          </NewRunDialogProvider>
        </FixedCaseProvider>
      </RefreshProvider>
    </ThemeProvider>
  );
}
