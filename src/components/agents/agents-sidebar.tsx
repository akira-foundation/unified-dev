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

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { AddRepositoryDialog } from "@/components/repos/add-repository-dialog";
import { RemoveRepositoryDialog } from "@/components/repos/remove-repository-dialog";
import { RemoveThreadDialog } from "@/components/agents/remove-thread-dialog";

export function AgentsSidebar() {
  const { t } = useI18n();
  const { toggleSidebar } = useSidebar();
  const { setIsAgentMode, navigateTo } = useNavigationStore();
  const {
    repositoryGroups,
    selectedIssueId,
    setSelectedIssueId,
    activeTab,
    setActiveTab,
    addRepository,
    addThread,
    removeThread,
    removeRepository,
    showAddRepositoryDialog,
    setShowAddRepositoryDialog,
    expandedRepos,
    setExpandedRepos,
    streamingThreadId,
  } = useAgentsStore();
  const [isAddingRepo, setIsAddingRepo] = useState(false);
  const [repoToRemove, setRepoToRemove] = useState<{ id: string; name: string } | null>(null);
  const [isRemovingRepo, setIsRemovingRepo] = useState(false);
  const [addingThreadForRepo, setAddingThreadForRepo] = useState<string | null>(null);
  const [removingThreadId, setRemovingThreadId] = useState<string | null>(null);
  const [threadToRemove, setThreadToRemove] = useState<{ id: string; title: string; repoId: string } | null>(null);

  const handleBack = () => {
    setIsAgentMode(false);
    navigateTo("dashboard");
  };

  const toggleRepo = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    setExpandedRepos((prev) => ({ ...prev, [id]: !prev[id] }));
  };

  const handleAddRepo = async (path: string) => {
    let loadingToast;
    try {
      setIsAddingRepo(true);
      loadingToast = toast.loading("Adding repository...");

      const response = await invoke<any>("add_local_repository", { localPath: path });

      if (response && response.repository && response.thread) {
        toast.success(`Repository ${response.repository.name} added`, { id: loadingToast });
        addRepository(response.repository, response.thread);
        setShowAddRepositoryDialog(false);
      } else {
        toast.error("Invalid response from server", { id: loadingToast });
      }
    } catch (error) {
      toast.error(`Error: ${error}`, { id: loadingToast });
    } finally {
      setIsAddingRepo(false);
    }
  };

  const handleRemoveRepo = async () => {
    if (!repoToRemove) return;

    try {
      setIsRemovingRepo(true);
      await invoke("delete_local_repository", { repoId: repoToRemove.id });
      removeRepository(repoToRemove.id);
      toast.success(`Repository ${repoToRemove.name} removed`);
      setRepoToRemove(null);
    } catch (error) {
      toast.error(`Failed to remove repository: ${error}`);
    } finally {
      setIsRemovingRepo(false);
    }
  };

  const handleAddThread = async (repoId: string) => {
    try {
      setAddingThreadForRepo(repoId);
      const thread = await invoke<{ id: string; title: string; workspace_path: string }>("create_thread", { repoId });
      addThread(repoId, thread);
      setExpandedRepos((prev) => ({ ...prev, [repoId]: true }));
    } catch (error) {
      toast.error(`Failed to create thread: ${error}`);
    } finally {
      setAddingThreadForRepo(null);
    }
  };

  const handleRemoveThread = async () => {
    if (!threadToRemove) return;

    try {
      setRemovingThreadId(threadToRemove.id);
      await invoke("delete_thread", { threadId: threadToRemove.id });
      removeThread(threadToRemove.repoId, threadToRemove.id);
      toast.success("Thread removed");
      setThreadToRemove(null);
    } catch (error) {
      toast.error(`Failed to remove thread: ${error}`);
    } finally {
      setRemovingThreadId(null);
    }
  };

  return (
    <Sidebar className="border-r-0 bg-[#121212] dark:bg-[#0c0c0c] backdrop-blur-xl">
      <SidebarHeader className="h-auto border-b border-white/[0.03] flex flex-col p-4 gap-4">
        <div className="flex items-center gap-3 w-full">
          <button
            onClick={handleBack}
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md text-muted-foreground hover:bg-zinc-100 dark:hover:bg-zinc-900 hover:text-foreground dark:hover:text-white transition-all group"
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
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md text-muted-foreground hover:bg-zinc-100 dark:hover:bg-zinc-900 hover:text-foreground dark:hover:text-white transition-all"
            title="Collapse Sidebar"
          >
            <PanelLeft className="h-4 w-4" />
          </button>
        </div>

        <div className="flex flex-col gap-1">
          <button
            onClick={() => setShowAddRepositoryDialog(true)}
            className="flex items-center gap-3 px-2 py-1.5 rounded-md hover:bg-white/5 text-xs font-medium text-foreground/80 transition-all group"
          >
            <Plus className="h-4 w-4 text-muted-foreground group-hover:text-foreground" />
            <span>Add Repository</span>
          </button>
          <button
            onClick={() => setActiveTab('automations')}
            className={cn(
              "flex items-center gap-3 px-2 py-1.5 rounded-md text-xs font-medium transition-all group",
              activeTab === 'automations'
                ? "bg-white/10 text-foreground"
                : "hover:bg-white/5 text-foreground/80"
            )}
          >
            <Zap className={cn(
              "h-4 w-4 transition-colors",
              activeTab === 'automations' ? "text-foreground" : "text-muted-foreground group-hover:text-foreground"
            )} />
            <span>Automations</span>
          </button>
          <button
            onClick={() => setActiveTab('skills')}
            className={cn(
              "flex items-center gap-3 px-2 py-1.5 rounded-md text-xs font-medium transition-all group",
              activeTab === 'skills'
                ? "bg-white/10 text-foreground"
                : "hover:bg-white/5 text-foreground/80"
            )}
          >
            <Lightbulb className={cn(
              "h-4 w-4 transition-colors",
              activeTab === 'skills' ? "text-foreground" : "text-muted-foreground group-hover:text-foreground"
            )} />
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
                    <div key={repo.id} className="group/workspace flex flex-col mx-2 rounded-md">
                      <div className="group/repo flex items-center gap-1 pr-2 rounded-md">
                        <button
                          onClick={(e) => toggleRepo(repo.id, e)}
                          className="flex-1 flex items-center gap-2 px-2 py-2 select-none cursor-pointer"
                        >
                          <span className="w-4 flex items-center justify-center shrink-0">
                            {repo.issues.length > 0 && (
                              expandedRepos[repo.id] ? (
                                <ChevronDown className="h-3 w-3 text-muted-foreground/30" />
                              ) : (
                                <ChevronRight className="h-3 w-3 text-muted-foreground/30" />
                              )
                            )}
                          </span>
                          <Folder className="h-4 w-4 text-muted-foreground/60 group-hover/repo:text-foreground/80 shrink-0" />
                          <span className="flex-1 text-left text-[13px] font-medium text-foreground/70 group-hover/repo:text-foreground truncate">
                            {repo.name}
                          </span>
                          {repo.issues.some((i) => streamingThreadId === i.id) && (
                            <span className="flex items-center gap-[3px] shrink-0">
                              <span className="h-[3px] w-[3px] rounded-full bg-white/50 animate-bounce [animation-delay:0ms]" />
                              <span className="h-[3px] w-[3px] rounded-full bg-white/50 animate-bounce [animation-delay:150ms]" />
                              <span className="h-[3px] w-[3px] rounded-full bg-white/50 animate-bounce [animation-delay:300ms]" />
                            </span>
                          )}
                        </button>

                        <div className="flex items-center gap-1 opacity-0 group-hover/workspace:opacity-100 transition-opacity">
                          <TooltipProvider>
                            <Tooltip>
                              <TooltipTrigger asChild>
                                <button
                                  onClick={() => handleAddThread(repo.id)}
                                  disabled={addingThreadForRepo === repo.id}
                                  className="p-1 rounded hover:bg-white/5 text-muted-foreground/40 hover:text-foreground transition-colors disabled:opacity-50 cursor-pointer"
                                >
                                  {addingThreadForRepo === repo.id ? (
                                    <div className="h-3.5 w-3.5 border border-white/30 border-t-white/80 rounded-full animate-spin" />
                                  ) : (
                                    <Plus className="h-3.5 w-3.5" />
                                  )}
                                </button>
                              </TooltipTrigger>
                              <TooltipContent className="bg-purple-500 text-white border-none font-bold">
                                <span className="text-xs">Add new thread</span>
                              </TooltipContent>
                            </Tooltip>
                          </TooltipProvider>

                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <button className="p-1 rounded hover:bg-white/5 text-muted-foreground/40 hover:text-foreground transition-colors cursor-pointer">
                                <MoreVertical className="h-3.5 w-3.5" />
                              </button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end" className="w-56 bg-[#0D0D0D] border-white/[0.05] p-1 shadow-2xl rounded-md">
                              <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-white/5 rounded-md cursor-pointer">
                                <CircleDot className="h-4 w-4 text-white/40" />
                                <span>From issue</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-white/5 rounded-md cursor-pointer">
                                <GitPullRequest className="h-4 w-4 text-white/40" />
                                <span>From pull request</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-white/5 rounded-md cursor-pointer">
                                <GitBranch className="h-4 w-4 text-white/40" />
                                <span>From branch</span>
                              </DropdownMenuItem>

                              <DropdownMenuSeparator className="bg-white/[0.03]" />

                              <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-white/5 rounded-md cursor-pointer">
                                <Play className="h-4 w-4 text-white/40" />
                                <span>Run task</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-white/5 rounded-md cursor-pointer">
                                <Rocket className="h-4 w-4 text-white/40" />
                                <span>Autopilot</span>
                              </DropdownMenuItem>

                              <DropdownMenuSeparator className="bg-white/[0.03]" />

                              <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-white/5 rounded-md cursor-pointer">
                                <Settings className="h-4 w-4 text-white/40" />
                                <span>Settings</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem
                                onClick={() => setRepoToRemove({ id: repo.id, name: repo.name })}
                                className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-red-500/10 text-red-500 rounded-md cursor-pointer"
                              >
                                <Trash2 className="h-4 w-4" />
                                <span>Remove</span>
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>
                        </div>
                      </div>

                      {expandedRepos[repo.id] && repo.issues.length > 0 && (
                        <div className="flex flex-col pb-1">
                          {repo.issues.map((issue) => (
                            <button
                              key={issue.id}
                              onClick={() => {
                                setSelectedIssueId(issue.id);
                              }}
                              className={cn(
                                "group/thread relative flex flex-col gap-1 pl-10 pr-3 py-1.5 text-left rounded-md transition-opacity cursor-pointer",
                                selectedIssueId === issue.id && activeTab === "workspace"
                                  ? "opacity-100"
                                  : "opacity-40 hover:opacity-70"
                              )}
                            >
                              <div className="flex items-center justify-between gap-2 min-w-0 w-full">
                                <div className="flex items-center gap-3 min-w-0 flex-1">
                                  <span className={cn(
                                    "text-[13px] truncate transition-colors flex-1",
                                    selectedIssueId === issue.id && activeTab === "workspace"
                                      ? "text-white font-semibold"
                                      : "text-white/90 font-medium"
                                  )}>
                                    {issue.title}
                                  </span>
                                  {streamingThreadId === issue.id && (
                                    <span className="flex items-center gap-[3px] shrink-0">
                                      <span className="h-[3px] w-[3px] rounded-full bg-white/50 animate-bounce [animation-delay:0ms]" />
                                      <span className="h-[3px] w-[3px] rounded-full bg-white/50 animate-bounce [animation-delay:150ms]" />
                                      <span className="h-[3px] w-[3px] rounded-full bg-white/50 animate-bounce [animation-delay:300ms]" />
                                    </span>
                                  )}
                                  {issue.prUrl && (
                                    <GitBranch className="h-3 w-3 text-blue-500 shrink-0" />
                                  )}
                                </div>
                                <div className="hidden group-hover/thread:flex items-center gap-2 shrink-0 ml-auto">
                                  <span className="text-[10px] font-medium text-muted-foreground/40 tabular-nums whitespace-nowrap">
                                    {issue.status === "Running" ? "just now" : issue.updatedAt}
                                  </span>
                                  <button
                                    onClick={(e) => {
                                      e.stopPropagation();
                                      setThreadToRemove({ id: issue.id, title: issue.title, repoId: repo.id });
                                    }}
                                    disabled={removingThreadId === issue.id}
                                    className="p-1 rounded hover:bg-red-500/10 text-muted-foreground/40 hover:text-red-500 transition-colors disabled:opacity-50"
                                  >
                                    {removingThreadId === issue.id ? (
                                      <div className="h-3 w-3 border border-red-500/30 border-t-red-500 rounded-full animate-spin" />
                                    ) : (
                                      <Trash2 className="h-3 w-3" />
                                    )}
                                  </button>
                                </div>
                              </div>
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

      <AddRepositoryDialog
        open={showAddRepositoryDialog}
        onOpenChange={setShowAddRepositoryDialog}
        onAdd={handleAddRepo}
        isLoading={isAddingRepo}
      />

      <RemoveRepositoryDialog
        open={!!repoToRemove}
        onOpenChange={(open) => !open && setRepoToRemove(null)}
        onRemove={handleRemoveRepo}
        repoName={repoToRemove?.name || ""}
        isRemoving={isRemovingRepo}
      />

      <RemoveThreadDialog
        open={!!threadToRemove}
        onOpenChange={(open) => !open && setThreadToRemove(null)}
        onRemove={handleRemoveThread}
        threadTitle={threadToRemove?.title || ""}
        isRemoving={!!removingThreadId}
      />
    </Sidebar>
  );
}
