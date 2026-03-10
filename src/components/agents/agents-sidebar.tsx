import {
  ChevronDown,
  ChevronRight,
  CornerUpLeft,
  Plus,
  Folder,
  Search,
  Filter,
  Zap,
  Lightbulb,
  MoreVertical,
  CircleDot,
  GitPullRequest,
  GitBranch,
  Play,
  Settings,
  Trash2,
  Rocket,
  PanelLeft
} from "lucide-react";
import { useState } from "react";
import { cn } from "@/lib/utils";
import { useNavigationStore } from "@/stores/navigation-store";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useI18n } from "@/i18n/i18n";
import {
  Sidebar,
  SidebarContent,
  SidebarHeader,
  SidebarGroup,
  SidebarGroupLabel,
  SidebarGroupContent,
  useSidebar,
} from "@/components/ui/sidebar";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

export function AgentsSidebar() {
  const { t } = useI18n();
  const { toggleSidebar } = useSidebar();
  const { setIsAgentMode, navigateTo } = useNavigationStore();
  const { repositoryGroups, selectedIssueId, setSelectedIssueId } = useAgentsStore();
  const [expandedRepos, setExpandedRepos] = useState<Record<string, boolean>>({
    "repo-1": true,
    "repo-4": true,
  });

  const handleBack = () => {
    setIsAgentMode(false);
    navigateTo("dashboard");
  };

  const toggleRepo = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    setExpandedRepos((prev) => ({ ...prev, [id]: !prev[id] }));
  };

  return (
    <Sidebar className="border-r border-border/40 bg-[#121212] dark:bg-[#0c0c0c] backdrop-blur-xl">
      <SidebarHeader className="h-auto border-b border-white/[0.03] flex flex-col p-4 gap-4">
        <div className="flex items-center gap-3 w-full">
          <button
            onClick={handleBack}
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-muted-foreground hover:bg-zinc-100 dark:hover:bg-zinc-900 hover:text-foreground dark:hover:text-white transition-all group"
            title="Back to Dashboard"
          >
            <CornerUpLeft className="h-4 w-4 group-hover:-translate-x-0.5 transition-transform" />
          </button>
          <div className="flex flex-col flex-1 overflow-hidden">
            <span className="text-sm font-bold tracking-tight text-foreground dark:text-white truncate">{t("app.name")}</span>
            <span className="text-[9px] uppercase tracking-widest text-muted-foreground font-bold truncate">
              Agents
            </span>
          </div>
          <button
            type="button"
            onClick={toggleSidebar}
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-muted-foreground hover:bg-zinc-100 dark:hover:bg-zinc-900 hover:text-foreground dark:hover:text-white transition-all"
            title="Collapse Sidebar"
          >
            <PanelLeft className="h-4 w-4" />
          </button>
        </div>

        <div className="flex flex-col gap-1">
          <button className="flex items-center gap-3 px-2 py-1.5 rounded-lg hover:bg-white/5 text-xs font-medium text-foreground/80 transition-all group">
            <Plus className="h-4 w-4 text-muted-foreground group-hover:text-foreground" />
            <span>New thread</span>
          </button>
          <button className="flex items-center gap-3 px-2 py-1.5 rounded-lg hover:bg-white/5 text-xs font-medium text-foreground/80 transition-all group">
            <Zap className="h-4 w-4 text-muted-foreground group-hover:text-foreground" />
            <span>Automations</span>
          </button>
          <button className="flex items-center gap-3 px-2 py-1.5 rounded-lg hover:bg-white/5 text-xs font-medium text-foreground/80 transition-all group">
            <Lightbulb className="h-4 w-4 text-muted-foreground group-hover:text-foreground" />
            <span>Skills</span>
          </button>
        </div>
      </SidebarHeader>

      <SidebarContent className="flex-1 flex flex-col overflow-hidden">
        <div className="flex-1 overflow-y-auto custom-scrollbar py-2">
          {repositoryGroups.map((group) => (
            <SidebarGroup key={group.name} className="py-2">
              <SidebarGroupLabel className="flex items-center justify-between px-4 mb-2">
                <span className="text-[10px] font-bold uppercase tracking-[0.15em] text-muted-foreground/40">
                  {group.name}
                </span>
                <div className="flex items-center gap-2">
                  <Filter className="h-3 w-3 text-muted-foreground/40" />
                  <Search className="h-3 w-3 text-muted-foreground/40" />
                </div>
              </SidebarGroupLabel>

              <SidebarGroupContent>
                <div className="flex flex-col gap-0.5">
                  {group.repositories.map((repo) => (
                    <div key={repo.id} className="flex flex-col">
                      <div className="group/repo flex items-center gap-1 hover:bg-white/[0.03] transition-all pr-4">
                        <button
                          onClick={(e) => toggleRepo(repo.id, e)}
                          className="flex-1 flex items-center gap-3 px-4 py-2 select-none"
                        >
                          <Folder className="h-4 w-4 text-muted-foreground/60 group-hover/repo:text-foreground/80 shrink-0" />
                          <span className="flex-1 text-left text-[13px] font-medium text-foreground/70 group-hover/repo:text-foreground truncate">
                            {repo.name}
                            {repo.name === "Support refunds" && (
                              <span className="ml-2 text-muted-foreground/30 font-normal">refunds</span>
                            )}
                          </span>
                          {repo.issues.length > 0 && (
                            expandedRepos[repo.id] ? (
                              <ChevronDown className="h-3 w-3 text-muted-foreground/20" />
                            ) : (
                              <ChevronRight className="h-3 w-3 text-muted-foreground/20" />
                            )
                          )}
                        </button>

                        <div className="flex items-center gap-1 opacity-0 group-hover/repo:opacity-100 transition-opacity">
                          <button className="p-1 rounded hover:bg-white/5 text-muted-foreground/40 hover:text-foreground transition-colors">
                            <Plus className="h-3.5 w-3.5" />
                          </button>

                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <button className="p-1 rounded hover:bg-white/5 text-muted-foreground/40 hover:text-foreground transition-colors">
                                <MoreVertical className="h-3.5 w-3.5" />
                              </button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end" className="w-56 bg-[#0D0D0D] border-white/[0.05] p-1 shadow-2xl rounded-xl">
                              <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-white/5 rounded-lg cursor-pointer">
                                <CircleDot className="h-4 w-4 text-white/40" />
                                <span>From issue</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-white/5 rounded-lg cursor-pointer">
                                <GitPullRequest className="h-4 w-4 text-white/40" />
                                <span>From pull request</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-white/5 rounded-lg cursor-pointer">
                                <GitBranch className="h-4 w-4 text-white/40" />
                                <span>From branch</span>
                              </DropdownMenuItem>

                              <DropdownMenuSeparator className="bg-white/[0.03]" />

                              <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-white/5 rounded-lg cursor-pointer">
                                <Play className="h-4 w-4 text-white/40" />
                                <span>Run task</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-white/5 rounded-lg cursor-pointer">
                                <Rocket className="h-4 w-4 text-white/40" />
                                <span>Autopilot</span>
                              </DropdownMenuItem>

                              <DropdownMenuSeparator className="bg-white/[0.03]" />

                              <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-white/5 rounded-lg cursor-pointer">
                                <Settings className="h-4 w-4 text-white/40" />
                                <span>Settings</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-red-500/10 text-red-500 rounded-lg cursor-pointer">
                                <Trash2 className="h-4 w-4" />
                                <span>Remove</span>
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>
                        </div>
                      </div>

                      {expandedRepos[repo.id] && repo.issues.length > 0 && (
                        <div className="flex flex-col mt-0.5">
                          {repo.issues.map((issue) => (
                            <button
                              key={issue.id}
                              onClick={() => setSelectedIssueId(issue.id)}
                              className={cn(
                                "group relative flex flex-col gap-1 px-4 py-2.5 transition-all text-left ml-4 mr-2 rounded-xl",
                                selectedIssueId === issue.id
                                  ? "bg-white/[0.05] shadow-sm"
                                  : "hover:bg-white/[0.02]"
                              )}
                            >
                              <div className="flex items-center justify-between gap-3">
                                <div className="flex items-center gap-3 min-w-0">
                                  {issue.status === "Running" && (
                                    <div className="relative h-4 w-4 flex items-center justify-center">
                                      <div className="absolute inset-0 border-2 border-white/10 rounded-full" />
                                      <div className="absolute inset-0 border-2 border-transparent border-t-white/40 rounded-full animate-spin" />
                                    </div>
                                  )}
                                  <span className={cn(
                                    "text-[13px] font-semibold truncate transition-colors",
                                    selectedIssueId === issue.id ? "text-white" : "text-white/80 group-hover:text-white"
                                  )}>
                                    {issue.title}
                                  </span>
                                </div>
                                <span className="text-[10px] font-medium text-muted-foreground/40 tabular-nums">
                                  {issue.updatedAt}
                                </span>
                              </div>

                              {selectedIssueId === issue.id && issue.status === "Running" && (
                                <div className="flex items-center gap-2 mt-0.5">
                                  <Badge className="bg-[#1C3A27] hover:bg-[#1C3A27] text-[#4ADE80] text-[10px] font-bold px-2 py-0 border-none rounded-md h-5">
                                    Awaiting response
                                  </Badge>
                                </div>
                              )}
                            </button>
                          ))}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              </SidebarGroupContent>
            </SidebarGroup>
          ))}
        </div>


      </SidebarContent>
    </Sidebar>
  );
}
