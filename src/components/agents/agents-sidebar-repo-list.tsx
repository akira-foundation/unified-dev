import {
  ChevronDown,
  ChevronRight,
  CircleDot,
  ExternalLink,
  Folder,
  GitBranch,
  GitPullRequest,
  MoreVertical,
  Plus,
  Rocket,
  Search,
  Settings,
  Trash2,
  X,
} from "lucide-react";

import { cn } from "@/lib/utils";
import { SidebarGroup, SidebarGroupContent, SidebarGroupLabel } from "@/components/ui/sidebar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { openUpgradeModal } from "@/stores/upgrade-modal-store";
import {
  RepoStreamingIndicator,
  ThreadPrCiBadge,
  ThreadPrIcon,
  ThreadStreamingDots,
} from "@/components/agents/agents-sidebar-badges";
import type { AgentsSidebarVm } from "@/hooks/useAgentsSidebar";

export function AgentsSidebarRepoList({ vm }: { vm: AgentsSidebarVm }) {
  const { t, searchOpen, setSearchOpen, searchQuery, setSearchQuery, searchInputRef } = vm;

  if (!vm.repositoriesLoaded) {
    return (
      <div className="px-4 py-3 flex flex-col gap-3">
        {[1, 2, 3].map((i) => (
          <div key={i} className="flex flex-col gap-1.5 animate-pulse">
            <div className="flex items-center gap-2 px-2 py-1.5">
              <div className="h-3 w-3 rounded bg-muted-foreground/10" />
              <div className="h-4 w-4 rounded bg-muted-foreground/10" />
              <div className="h-3 rounded bg-muted-foreground/10" style={{ width: `${[120, 96, 140][i - 1]}px` }} />
            </div>
            {i < 3 && (
              <div className="ml-8 flex flex-col gap-1">
                {[0, 1].map((j) => (
                  <div key={j} className="flex items-center gap-2 px-2 py-1.5 rounded-md">
                    <div className="h-3 rounded bg-muted-foreground/10" style={{ width: `${[160, 110][j]}px` }} />
                  </div>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    );
  }

  return (
    <>
      {vm.repositoryGroups.map((group) => (
        <SidebarGroup key={group.name} className="py-2">
          <SidebarGroupLabel className="flex items-center justify-between px-4 pt-2 pb-1 text-[10px] font-bold uppercase tracking-widest text-zinc-500">
            {searchOpen ? (
              <div className="flex-1 relative group min-w-0">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-zinc-600 group-focus-within:text-purple-500/50 transition-colors" />
                <input
                  ref={searchInputRef}
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Escape") {
                      setSearchQuery("");
                      setSearchOpen(false);
                    }
                  }}
                  placeholder={t("agents.sidebar.searchThreads")}
                  className="w-full bg-white/[0.03] border border-white/[0.05] rounded-md py-1.5 pl-9 pr-8 text-[11px] text-zinc-200 focus:outline-none focus:border-purple-500/30 focus:bg-white/[0.05] transition-all placeholder:text-zinc-600 font-medium"
                />
                <button
                  onClick={() => { setSearchQuery(""); setSearchOpen(false); }}
                  className="absolute right-2 top-1/2 -translate-y-1/2 text-zinc-600 hover:text-zinc-300 transition-colors cursor-pointer"
                >
                  <X className="h-3 w-3" />
                </button>
              </div>
            ) : (
              <span className="text-[10px] font-bold uppercase tracking-[0.15em] text-muted-foreground/40">{group.name}</span>
            )}
            {!searchOpen && (
              <button
                onClick={() => {
                  setSearchOpen(true);
                  setTimeout(() => searchInputRef.current?.focus(), 0);
                }}
                className="text-muted-foreground/40 hover:text-foreground transition-colors cursor-pointer"
              >
                <Search className="h-3 w-3" />
              </button>
            )}
          </SidebarGroupLabel>

          <SidebarGroupContent>
            <div className="flex flex-col gap-0.5">
              {group.repositories
                .filter((repo) => {
                  if (searchQuery.trim() === "") return true;
                  const repoLabel = (repo.displayName ?? repo.name).toLowerCase();
                  const q = searchQuery.toLowerCase().trim();
                  if (repoLabel.includes(q)) return true;
                  return repo.issues.some((issue) => issue.title.toLowerCase().includes(q));
                })
                .map((repo) => {
                  const isExpanded = searchQuery.trim() !== "" ? true : !!vm.expandedRepos[repo.id];
                  const hasActiveJob = Object.values(vm.jobs).some((j) => j.repoId === repo.id && (j.status === "running" || j.status === "waiting"));
                  return (
                    <div key={repo.id} className="group/workspace flex flex-col mx-2 rounded-md">
                      <div className="group/repo flex items-center gap-1 pr-2 rounded-md">
                        <button onClick={(e) => vm.toggleRepo(repo.id, e)} className="flex-1 min-w-0 flex items-center gap-2 px-2 py-2 select-none cursor-pointer">
                          <span className="w-4 flex items-center justify-center shrink-0">
                            {repo.issues.length > 0 && (isExpanded ? <ChevronDown className="h-3 w-3 text-muted-foreground/30" /> : <ChevronRight className="h-3 w-3 text-muted-foreground/30" />)}
                          </span>
                          <Folder className="h-4 w-4 text-muted-foreground/60 group-hover/repo:text-foreground/80 shrink-0" />
                          <span className="flex-1 text-left text-[13px] font-medium text-foreground/70 group-hover/repo:text-foreground truncate">{repo.displayName ?? repo.name}</span>
                          <RepoStreamingIndicator repoIssueIds={repo.issues.map((i) => i.id)} />
                        </button>

                        <div className="flex items-center gap-1 opacity-0 group-hover/workspace:opacity-100 transition-opacity">
                          <TooltipProvider>
                            <Tooltip>
                              <TooltipTrigger asChild>
                                <button
                                  onClick={() => vm.handleAddThread(repo.id)}
                                  disabled={vm.addingThreadForRepo === repo.id}
                                  className="p-1 rounded dark:hover:bg-white/5 hover:bg-black/5 text-muted-foreground/40 hover:text-foreground transition-colors disabled:opacity-50 cursor-pointer"
                                >
                                  {vm.addingThreadForRepo === repo.id ? <div className="h-3.5 w-3.5 border border-white/30 border-t-white/80 rounded-full animate-spin" /> : <Plus className="h-3.5 w-3.5" />}
                                </button>
                              </TooltipTrigger>
                              <TooltipContent className="bg-purple-500 text-white border-none font-bold">
                                <span className="text-xs">{t("agents.sidebar.addThread")}</span>
                              </TooltipContent>
                            </Tooltip>
                          </TooltipProvider>

                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <button className="p-1 rounded dark:hover:bg-white/5 hover:bg-black/5 text-muted-foreground/40 hover:text-foreground transition-colors cursor-pointer">
                                <MoreVertical className="h-3.5 w-3.5" />
                              </button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end" className="w-56 bg-popover dark:border-white/[0.05] border-border p-1 shadow-2xl rounded-md">
                              <DropdownMenuLabel className="px-3 py-2 text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">{t("common.open")}</DropdownMenuLabel>
                              <DropdownMenuItem onClick={() => vm.handleOpenSourcePicker("issue", repo)} className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 rounded-md cursor-pointer">
                                <CircleDot className="h-4 w-4 text-foreground/40" />
                                <span>{t("agents.sidebar.fromIssue")}</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem onClick={() => vm.handleOpenSourcePicker("pr", repo)} className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 rounded-md cursor-pointer">
                                <GitPullRequest className="h-4 w-4 text-foreground/40" />
                                <span>{t("agents.sidebar.fromPr")}</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem onClick={() => vm.handleOpenSourcePicker("branch", repo)} className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 rounded-md cursor-pointer">
                                <GitBranch className="h-4 w-4 text-foreground/40" />
                                <span>{t("agents.sidebar.fromBranch")}</span>
                              </DropdownMenuItem>
                              <DropdownMenuSeparator className="dark:bg-white/[0.03] bg-black/[0.05]" />
                              <DropdownMenuLabel className="px-3 py-2 text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">{t("common.manage")}</DropdownMenuLabel>
                              <DropdownMenuItem
                                onClick={() => {
                                  if (vm.isFree) { openUpgradeModal("autopilot_requires_pro"); return; }
                                  const activeJob = Object.values(vm.jobs).find((j) => j.repoId === repo.id && (j.status === "running" || j.status === "waiting"));
                                  if (activeJob) vm.selectJob(activeJob.id);
                                  else vm.setAutopilotTarget({ repoId: repo.id, repoName: repo.name });
                                }}
                                className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 rounded-md cursor-pointer"
                              >
                                <Rocket className={cn("h-4 w-4", hasActiveJob ? "text-purple-500" : "text-foreground/40")} />
                                <span>{t("agents.sidebar.autopilot")}</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem onClick={() => vm.handleViewRepo(repo)} className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 rounded-md cursor-pointer">
                                <ExternalLink className="h-4 w-4 text-foreground/40" />
                                <span>{t("agents.sidebar.viewRepo")}</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem onClick={() => vm.setRepoSettingsTarget(repo.id)} className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 rounded-md cursor-pointer">
                                <Settings className="h-4 w-4 text-foreground/40" />
                                <span>{t("agents.sidebar.settings")}</span>
                              </DropdownMenuItem>
                              <DropdownMenuSeparator className="dark:bg-white/[0.03] bg-black/[0.05]" />
                              <DropdownMenuLabel className="px-3 py-2 text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">{t("common.dangerZone")}</DropdownMenuLabel>
                              <DropdownMenuItem onClick={() => vm.setRepoClearThreads({ id: repo.id, name: repo.name })} className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-red-500/10 text-red-500 rounded-md cursor-pointer">
                                <Trash2 className="h-4 w-4" />
                                <span>{t("agents.sidebar.clearThreads")}</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem onClick={() => vm.setRepoToRemove({ id: repo.id, name: repo.name })} className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-red-500/10 text-red-500 rounded-md cursor-pointer">
                                <Trash2 className="h-4 w-4" />
                                <span>{t("common.remove")}</span>
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>
                        </div>
                      </div>

                      {isExpanded && repo.issues.length > 0 && (
                        <div className="flex flex-col pb-1">
                          {repo.issues
                            .filter((issue) => {
                              const q = searchQuery.toLowerCase().trim();
                              if (q === "") return true;
                              const repoLabel = (repo.displayName ?? repo.name).toLowerCase();
                              return repoLabel.includes(q) || issue.title.toLowerCase().includes(q);
                            })
                            .map((issue) => {
                              const active = vm.selectedIssueId === issue.id && vm.activeTab === "workspace";
                              return (
                                <button
                                  key={issue.id}
                                  onClick={() => vm.setSelectedIssueId(issue.id)}
                                  className={cn(
                                    "group/thread relative flex flex-col gap-1 pl-10 pr-3 py-1.5 text-left rounded-md transition-opacity cursor-pointer",
                                    active ? "opacity-100" : "opacity-40 hover:opacity-70",
                                  )}
                                >
                                  <div className="flex items-center justify-between gap-2 min-w-0 w-full">
                                    <div className="flex items-center gap-3 min-w-0 flex-1">
                                      <span className={cn("text-[13px] truncate transition-colors flex-1", active ? "text-foreground font-semibold" : "text-foreground/80 font-medium")}>
                                        {issue.title}
                                      </span>
                                      <ThreadStreamingDots threadId={issue.id} />
                                      <ThreadPrCiBadge threadId={issue.id} />
                                      <ThreadPrIcon threadId={issue.id} />
                                    </div>
                                    <div className="hidden group-hover/thread:flex items-center gap-2 shrink-0 ml-auto">
                                      <div
                                        role="button"
                                        tabIndex={0}
                                        onClick={(e) => { e.stopPropagation(); vm.setThreadToRemove({ id: issue.id, title: issue.title, repoId: repo.id }); }}
                                        onKeyDown={(e) => {
                                          if (e.key === "Enter" || e.key === " ") { e.stopPropagation(); vm.setThreadToRemove({ id: issue.id, title: issue.title, repoId: repo.id }); }
                                        }}
                                        aria-disabled={vm.removingThreadId === issue.id}
                                        className="p-1 rounded hover:bg-red-500/10 text-muted-foreground/40 hover:text-red-500 transition-colors aria-disabled:opacity-50 cursor-pointer"
                                      >
                                        {vm.removingThreadId === issue.id ? <div className="h-3 w-3 border border-red-500/30 border-t-red-500 rounded-full animate-spin" /> : <Trash2 className="h-3 w-3" />}
                                      </div>
                                    </div>
                                  </div>
                                </button>
                              );
                            })}
                        </div>
                      )}
                    </div>
                  );
                })}
            </div>
          </SidebarGroupContent>
        </SidebarGroup>
      ))}
    </>
  );
}
