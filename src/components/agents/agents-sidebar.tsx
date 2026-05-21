import { Folder, Lightbulb, Link2, Plus, Zap } from "lucide-react";

import { cn } from "@/lib/utils";
import { SidebarMenu, SidebarMenuButton, SidebarMenuItem } from "@/components/ui/sidebar";
import { BaseSidebar } from "@/components/layout/base-sidebar";
import { AutopilotIndicator } from "@/components/agents/autopilot-indicator";
import { AgentsSidebarRepoList } from "@/components/agents/agents-sidebar-repo-list";
import { AgentsSidebarDialogs } from "@/components/agents/agents-sidebar-dialogs";
import { useAgentsSidebar } from "@/hooks/useAgentsSidebar";

const NAV_BTN =
  "flex items-center gap-3 h-10 px-3 rounded-xl text-[13px] font-medium transition-colors duration-150 group group-data-[collapsible=icon]:size-10 group-data-[collapsible=icon]:p-0 group-data-[collapsible=icon]:justify-center";
const NAV_IDLE = "text-zinc-600 hover:bg-zinc-200/40 dark:text-zinc-400 dark:hover:bg-white/[0.06]";
const NAV_ACTIVE = "bg-white/70 text-zinc-900 shadow-sm shadow-black/5 dark:bg-white/[0.1] dark:text-white";

export function AgentsSidebar() {
  const vm = useAgentsSidebar();
  const { t } = vm;

  const footerExtra = (
    <SidebarMenu>
      <SidebarMenuItem>
        <AutopilotIndicator onOpen={() => vm.setAutopilotPanelOpen(true)} collapsed={vm.sidebarState === "collapsed"} />
      </SidebarMenuItem>
    </SidebarMenu>
  );

  return (
    <>
      <BaseSidebar
        subtitleKey="agents.sidebar.agents"
        contentClassName="flex-1 flex flex-col overflow-hidden gap-1 pt-4 pb-2"
        footerExtra={footerExtra}
      >
        <div className="flex flex-col gap-1 px-2 group-data-[collapsible=icon]:px-0">
          <SidebarMenu className="gap-1 group-data-[collapsible=icon]:items-center">
            <SidebarMenuItem className="group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:justify-center">
              <SidebarMenuButton onClick={() => vm.setShowAddRepositoryDialog(true)} tooltip={t("agents.sidebar.addRepository")} className={cn(NAV_BTN, NAV_IDLE)}>
                <Plus className="h-4 w-4 text-muted-foreground group-hover:text-foreground shrink-0" />
                <span className="group-data-[collapsible=icon]:hidden">{t("agents.sidebar.addRepository")}</span>
              </SidebarMenuButton>
            </SidebarMenuItem>
            <SidebarMenuItem className="group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:justify-center">
              <SidebarMenuButton tooltip={t("agents.sidebar.automations")} className={cn(NAV_BTN, "text-zinc-600 dark:text-zinc-400 opacity-40 cursor-not-allowed h-auto")}>
                <Zap className="h-4 w-4 text-muted-foreground shrink-0" />
                <span className="group-data-[collapsible=icon]:hidden">{t("agents.sidebar.automations")}</span>
                <span className="ml-auto group-data-[collapsible=icon]:hidden text-[9px] font-semibold uppercase tracking-wider text-muted-foreground/60 border border-muted-foreground/20 rounded px-1 py-0.5">Soon</span>
              </SidebarMenuButton>
            </SidebarMenuItem>
            <SidebarMenuItem className="group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:justify-center">
              <SidebarMenuButton onClick={() => vm.setActiveTab("skills")} isActive={vm.activeTab === "skills"} tooltip={t("agents.sidebar.skills")} className={cn(NAV_BTN, vm.activeTab === "skills" ? NAV_ACTIVE : NAV_IDLE)}>
                <Lightbulb className={cn("h-4 w-4 transition-colors shrink-0", vm.activeTab === "skills" ? "text-foreground" : "text-muted-foreground group-hover:text-foreground")} />
                <span className="group-data-[collapsible=icon]:hidden">{t("agents.sidebar.skills")}</span>
              </SidebarMenuButton>
            </SidebarMenuItem>
            <SidebarMenuItem className="group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:justify-center">
              <SidebarMenuButton onClick={() => vm.setActiveTab("mcp")} isActive={vm.activeTab === "mcp"} tooltip={t("agents.sidebar.mcp")} className={cn(NAV_BTN, vm.activeTab === "mcp" ? NAV_ACTIVE : NAV_IDLE)}>
                <Link2 className={cn("h-4 w-4 transition-colors shrink-0", vm.activeTab === "mcp" ? "text-foreground" : "text-muted-foreground group-hover:text-foreground")} />
                <span className="group-data-[collapsible=icon]:hidden">{t("agents.sidebar.mcp")}</span>
              </SidebarMenuButton>
            </SidebarMenuItem>
          </SidebarMenu>
        </div>

        {vm.sidebarState === "collapsed" ? (
          <div className="flex flex-col items-center pt-2">
            <SidebarMenu className="gap-1 items-center">
              <SidebarMenuItem className="flex justify-center">
                <SidebarMenuButton onClick={vm.toggleSidebar} isActive={vm.activeTab === "workspace"} tooltip={t("agents.sidebar.threads")} className="size-10 p-0 justify-center">
                  <Folder className="h-5 w-5" />
                </SidebarMenuButton>
              </SidebarMenuItem>
            </SidebarMenu>
          </div>
        ) : (
          <div className="flex-1 overflow-y-auto custom-scrollbar py-2">
            <AgentsSidebarRepoList vm={vm} />
          </div>
        )}
      </BaseSidebar>

      <AgentsSidebarDialogs vm={vm} />
    </>
  );
}
