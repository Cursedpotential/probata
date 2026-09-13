// Byline: Claude Code · Sonnet (agent) · 2026-07-22 (C3: Records/Evidence Queue/Schemas nav entries + open-flags badge; C4: Knowledge nav entry added 2026-07-23)
// Byline: Codex · GPT-5 · 2026-08-16 (Data Explorer + Surreal projection nav)
// Byline: Codex · GPT-5 · 2026-08-28 (focused unified-surface navigation)
// Byline: Codex · GPT-5.6-Sol · 2026-08-30 (two-surface navigation registry)
"use client";

import { ShieldCheck } from "lucide-react";
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarFooter,
} from "@/components/ui/sidebar";
import { workbenchNavigation } from "@/platform-ui/navigation";
import { WORKBENCH_SURFACES } from "@/platform-ui/surfaces";
import { AppLink, useCurrentPath } from "@/lib/router-compat";

export function AppSidebar() {
  const pathname = useCurrentPath();
  return (
    <Sidebar className="border-r border-sidebar-border">
      <SidebarHeader className="border-b border-sidebar-border px-4 py-5">
        <span className="platform-kicker text-[#9ca7ad]">{WORKBENCH_SURFACES.primary.kicker}</span>
      </SidebarHeader>
      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupLabel className="sr-only">Available workspaces</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {workbenchNavigation.map((item) => (
                <SidebarMenuItem key={item.href}>
                  <SidebarMenuButton asChild isActive={pathname === item.href || pathname.startsWith(`${item.href}/`)} className="h-12 rounded-none border-l-2 border-transparent px-4 text-sm data-[active=true]:border-[#8290ed] data-[active=true]:bg-[#314050] data-[active=true]:text-white">
                    <AppLink href={item.href}>
                      <item.icon className="h-4 w-4" />
                      <span>{item.title}</span>
                    </AppLink>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>
      <SidebarFooter className="border-t border-sidebar-border px-4 py-5">
        <div className="space-y-2 text-[11px] leading-5 text-[#aeb7bc]">
          <div className="flex items-center gap-2 font-semibold uppercase tracking-wide text-[#dce1e3]">
            <ShieldCheck className="h-4 w-4" /> Focused release
          </div>
          <p>Intake and Review expose available controls, missing projections, and recovery paths in one Context workflow.</p>
        </div>
      </SidebarFooter>
    </Sidebar>
  );
}
