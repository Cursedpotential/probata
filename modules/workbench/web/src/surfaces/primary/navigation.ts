// Byline: Codex · GPT-5.6-Sol · 2026-08-30
import { FileSearch, Inbox, LayoutDashboard } from "lucide-react";
import type { WorkbenchNavigationItem } from "@/platform-ui/navigation";

export const primaryNavigationItems = [
  {
    title: "Desk",
    pageTitle: "Context Intake Desk",
    href: "/",
    icon: LayoutDashboard,
    surface: "primary",
  },
  {
    title: "Intake",
    pageTitle: "Intake new source material",
    href: "/intake",
    icon: Inbox,
    surface: "primary",
  },
  {
    title: "Review",
    pageTitle: "Review extracted context",
    href: "/review",
    icon: FileSearch,
    surface: "primary",
  },
] as const satisfies readonly WorkbenchNavigationItem[];
