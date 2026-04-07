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
  Link2,
  MoreVertical,
  CircleDot,
  GitPullRequest,
  GitBranch,
  Settings,
  Trash2,
  Rocket,
  PanelLeft,
  ExternalLink,
} from "lucide-react";
import { useState } from "react";
import { cn } from "@/lib/utils";
import { useNavigationStore } from "@/stores/navigation-store";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useI18n } from "@/i18n/i18n";
import { useOrganizations } from "@/hooks/useOrganizations";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarGroup,
  SidebarGroupLabel,
  SidebarGroupContent,
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuButton,
  useSidebar,
} from "@/components/ui/sidebar";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { toast } from "sonner";
import { AddRepositoryDialog } from "@/components/repos/add-repository-dialog";
import { RemoveRepositoryDialog } from "@/components/repos/remove-repository-dialog";
import { RemoveThreadDialog } from "@/components/agents/remove-thread-dialog";
import { RepoSettingsSheet } from "@/components/agents/repo-settings-sheet";
import { repositorySelectionService } from "@/services/repositorySelectionService";
import {
  ThreadSourcePickerDialog,
  type ThreadSourceKind,
  type ThreadSourcePickerItem,
} from "@/components/agents/thread-source-picker-dialog";
import type { IssueDto } from "@/types/issue";
import type { BranchDto, PullRequestDto } from "@/types/organization";
import type { AgentRepository } from "@/types/agents";

export function AgentsSidebar() {
  const { t } = useI18n();
  const { toggleSidebar } = useSidebar();
  const { setIsAgentMode, navigateTo, goBack, canGoBack, setActiveOrganizationId, setActiveRepo } = useNavigationStore();
  const { organizations, isLoading: isLoadingOrganizations } = useOrganizations();
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
    streamingThreadIds,
    prUrlByThread,
    sendMessage,
    selectedModelId,
    setThreadPrInfo,
    loadRepositories,
  } = useAgentsStore();
  const [isAddingRepo, setIsAddingRepo] = useState(false);
  const [repoToRemove, setRepoToRemove] = useState<{ id: string; name: string } | null>(null);
  const [isRemovingRepo, setIsRemovingRepo] = useState(false);
  const [repoSettingsTarget, setRepoSettingsTarget] = useState<string | null>(null);
  const [addingThreadForRepo, setAddingThreadForRepo] = useState<string | null>(null);
  const [removingThreadId, setRemovingThreadId] = useState<string | null>(null);
  const [threadToRemove, setThreadToRemove] = useState<{ id: string; title: string; repoId: string } | null>(null);
  const [sourcePicker, setSourcePicker] = useState<{ kind: ThreadSourceKind; repoId: string; repoName: string } | null>(null);
  const [sourcePickerItems, setSourcePickerItems] = useState<ThreadSourcePickerItem[]>([]);
  const [sourcePickerLoading, setSourcePickerLoading] = useState(false);
  const [creatingSourceThread, setCreatingSourceThread] = useState(false);
  const [linkRepoDialog, setLinkRepoDialog] = useState<{
    repoId: string;
    repoName: string;
    kind: ThreadSourceKind;
    requiresRemote: boolean;
  } | null>(null);
  const [linkOrganizationId, setLinkOrganizationId] = useState<string>("");
  const [manualRemoteUrl, setManualRemoteUrl] = useState("");

  const isRepoLinkRequiredError = (error: unknown) => {
    const message = String(error).toLowerCase();
    return message.includes("must be linked to an organization before using issue, pull request, or branch pickers");
  };

  const isUnsupportedRemoteError = (error: unknown) => {
    const message = String(error).toLowerCase();
    return message.includes("repository is not linked to a supported github remote");
  };

  const handleBack = () => {
    setIsAgentMode(false);
    if (canGoBack) {
      goBack();
    } else {
      navigateTo("dashboard");
    }
  };

  const toggleRepo = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    setExpandedRepos((prev) => ({ ...prev, [id]: !prev[id] }));
  };

  const handleAddRepo = async (value: string, mode: "local" | "clone") => {
    let loadingToast;
    try {
      setIsAddingRepo(true);
      loadingToast = toast.loading(t("agents.sidebar.toast.addingRepo"));

      const response = await invoke<any>(
        mode === "clone" ? "add_remote_repository" : "add_local_repository",
        mode === "clone" ? { url: value } : { localPath: value },
      );

      if (response && response.repository && response.thread) {
        toast.success(t("agents.sidebar.toast.repoAdded").replace("{name}", response.repository.name), { id: loadingToast });
        addRepository(response.repository, response.thread);
        setShowAddRepositoryDialog(false);
      } else {
        toast.error(t("agents.sidebar.toast.invalidResponse"), { id: loadingToast });
      }
    } catch (error) {
      toast.error(`Error: ${error}`, { id: loadingToast });
    } finally {
      setIsAddingRepo(false);
    }
  };

  const handleViewRepo = async (repo: AgentRepository) => {
    if (!repo.remoteUrl) {
      toast.error("This repository is not linked to a workspace.");
      return;
    }
    try {
      const match = repo.remoteUrl.replace(/\.git$/, "").match(/github\.com[:/]([^/]+)\/([^/]+)/);
      if (!match) {
        toast.error("This repository is not linked to a workspace.");
        return;
      }
      const repoName = match[2];
      const allRepos = await repositorySelectionService.listAllSelectedRepositories();
      const linked = allRepos.find((r) => r.repo_name === repoName);
      if (!linked) {
        toast.error("This repository is not linked to a workspace.");
        return;
      }
      setActiveRepo({ name: linked.repo_name, owner: linked.owner, organizationId: linked.organization_id });
      navigateTo("repository-detail");
    } catch {
      toast.error("Failed to navigate to repository.");
    }
  };

  const handleRemoveRepo = async () => {
    if (!repoToRemove) return;

    try {
      setIsRemovingRepo(true);
      await invoke("delete_local_repository", { repoId: repoToRemove.id });
      removeRepository(repoToRemove.id);
      toast.success(t("agents.sidebar.toast.repoRemoved").replace("{name}", repoToRemove.name));
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
      toast.success(t("agents.sidebar.toast.threadRemoved"));
      setThreadToRemove(null);
    } catch (error) {
      toast.error(`Failed to remove thread: ${error}`);
    } finally {
      setRemovingThreadId(null);
    }
  };

  const handleOpenSourcePicker = async (
    kind: ThreadSourceKind,
    repo: { id: string; name: string },
  ) => {
    setSourcePicker({ kind, repoId: repo.id, repoName: repo.name });
    setSourcePickerItems([]);
    setSourcePickerLoading(true);

    try {
      if (kind === "issue") {
        const issues = await invoke<IssueDto[]>("list_thread_source_issues", { repoId: repo.id });
        setSourcePickerItems(
          issues.map((issue) => ({
            id: issue.id,
            title: issue.title,
            subtitle: `#${issue.number}${issue.author ? ` - ${issue.author}` : ""}`,
            meta: issue.status,
          })),
        );
        return;
      }

      if (kind === "pr") {
        const prs = await invoke<PullRequestDto[]>("list_thread_source_pull_requests", { repoId: repo.id });
        setSourcePickerItems(
          prs.map((pr) => ({
            id: pr.head_sha,
            title: pr.title,
            subtitle: `#${pr.number} - ${pr.head} -> ${pr.base}`,
            meta: pr.is_draft ? "draft" : pr.state,
          })),
        );
        return;
      }

      const branches = await invoke<BranchDto[]>("list_thread_source_branches", { repoId: repo.id });
      setSourcePickerItems(
        branches.map((branch) => ({
          id: branch.sha,
          title: branch.name,
          subtitle: branch.sha.slice(0, 7),
          meta: branch.is_default ? "default" : branch.is_protected ? "protected" : undefined,
        })),
      );
    } catch (error) {
      if (isRepoLinkRequiredError(error)) {
        setSourcePicker(null);
        setLinkRepoDialog({ repoId: repo.id, repoName: repo.name, kind, requiresRemote: false });
        setLinkOrganizationId("");
        setManualRemoteUrl("");
        return;
      }

      if (isUnsupportedRemoteError(error)) {
        setSourcePicker(null);
        setLinkRepoDialog({ repoId: repo.id, repoName: repo.name, kind, requiresRemote: true });
        setLinkOrganizationId("");
        setManualRemoteUrl("");
        return;
      }

      toast.error(`${error}`);
    } finally {
      setSourcePickerLoading(false);
    }
  };

  const handleSelectSourceItem = async (item: ThreadSourcePickerItem) => {
    if (!sourcePicker) return;

    try {
      setCreatingSourceThread(true);

      if (sourcePicker.kind === "issue") {
        const issues = await invoke<IssueDto[]>("list_thread_source_issues", { repoId: sourcePicker.repoId });
        const issue = issues.find((entry) => entry.id === item.id);
        if (!issue) {
          throw new Error(t("agents.sourcePicker.issue.notFound"));
        }

        const thread = await invoke<{ id: string; title: string; workspace_path: string }>(
          "create_thread_with_title",
          { repoId: sourcePicker.repoId, title: issue.title },
        );

        addThread(sourcePicker.repoId, thread);
        setExpandedRepos((prev) => ({ ...prev, [sourcePicker.repoId]: true }));
        setSourcePicker(null);

        if (selectedModelId) {
          const message = `Implement the following issue:\n\n**${issue.title}**\n\n${issue.body ?? ""}`;
          await sendMessage(thread.id, message, selectedModelId, false);
        }

        return;
      }

      if (sourcePicker.kind === "pr") {
        const prs = await invoke<PullRequestDto[]>("list_thread_source_pull_requests", { repoId: sourcePicker.repoId });
        const pr = prs.find((entry) => entry.head_sha === item.id);
        if (!pr) {
          throw new Error(t("agents.sourcePicker.pr.notFound"));
        }

        const thread = await invoke<{ id: string; title: string; workspace_path: string }>(
          "create_thread_from_pull_request",
          { repoId: sourcePicker.repoId, title: pr.title, headSha: pr.head_sha },
        );

        await invoke("set_thread_pr_url", {
          threadId: thread.id,
          prUrl: pr.url,
          prIsDraft: pr.is_draft,
        });

        setThreadPrInfo(thread.id, {
          url: pr.url,
          isDraft: pr.is_draft,
        });

        addThread(sourcePicker.repoId, thread);
        await loadRepositories();
        setExpandedRepos((prev) => ({ ...prev, [sourcePicker.repoId]: true }));
        setSourcePicker(null);
        return;
      }

      const thread = await invoke<{ id: string; title: string; workspace_path: string }>(
        "create_thread_from_branch",
        { repoId: sourcePicker.repoId, title: item.title, sourceCommit: item.id },
      );

      addThread(sourcePicker.repoId, thread);
      setExpandedRepos((prev) => ({ ...prev, [sourcePicker.repoId]: true }));
      setSourcePicker(null);
    } catch (error) {
      toast.error(`${error}`);
    } finally {
      setCreatingSourceThread(false);
    }
  };

  return (
    <Sidebar className="border-r-0 bg-sidebar backdrop-blur-xl">
      <SidebarHeader className="h-auto border-b border-white/[0.03] flex flex-col p-4 gap-4">
        <div className="flex items-center gap-3 w-full">
          <button
            onClick={handleBack}
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md text-muted-foreground hover:bg-zinc-100 dark:hover:bg-zinc-900 hover:text-foreground dark:hover:text-white transition-all group"
            title={t("agents.sidebar.backToDashboard")}
          >
            <CornerUpLeft className="h-4 w-4 group-hover:-translate-x-0.5 transition-transform" />
          </button>
          <div className="flex flex-col flex-1 overflow-hidden">
            <span className="text-sm font-bold tracking-tight text-foreground dark:text-white truncate">{t("app.name")}</span>
            <span className="text-[9px] uppercase tracking-widest text-muted-foreground font-bold truncate">
              {t("agents.sidebar.agents")}
            </span>
          </div>
          <button
            type="button"
            onClick={toggleSidebar}
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md text-muted-foreground hover:bg-zinc-100 dark:hover:bg-zinc-900 hover:text-foreground dark:hover:text-white transition-all"
            title={t("sidebar.collapseSidebar")}
          >
            <PanelLeft className="h-4 w-4" />
          </button>
        </div>

        <div className="flex flex-col gap-1">
          <button
            onClick={() => setShowAddRepositoryDialog(true)}
            className="flex items-center gap-3 px-2 py-1.5 rounded-md dark:hover:bg-white/5 hover:bg-black/5 text-xs font-medium text-foreground/80 transition-all group"
          >
            <Plus className="h-4 w-4 text-muted-foreground group-hover:text-foreground" />
            <span>{t("agents.sidebar.addRepository")}</span>
          </button>
          <button
            onClick={() => setActiveTab('automations')}
            className={cn(
              "flex items-center gap-3 px-2 py-1.5 rounded-md text-xs font-medium transition-all group",
              activeTab === 'automations'
                ? "dark:bg-white/10 bg-black/10 text-foreground"
                : "dark:hover:bg-white/5 hover:bg-black/5 text-foreground/80"
            )}
          >
            <Zap className={cn(
              "h-4 w-4 transition-colors",
              activeTab === 'automations' ? "text-foreground" : "text-muted-foreground group-hover:text-foreground"
            )} />
            <span>{t("agents.sidebar.automations")}</span>
          </button>
          <button
            onClick={() => setActiveTab('skills')}
            className={cn(
              "flex items-center gap-3 px-2 py-1.5 rounded-md text-xs font-medium transition-all group",
              activeTab === 'skills'
                ? "dark:bg-white/10 bg-black/10 text-foreground"
                : "dark:hover:bg-white/5 hover:bg-black/5 text-foreground/80"
            )}
          >
            <Lightbulb className={cn(
              "h-4 w-4 transition-colors",
              activeTab === 'skills' ? "text-foreground" : "text-muted-foreground group-hover:text-foreground"
            )} />
            <span>{t("agents.sidebar.skills")}</span>
          </button>
          <button
            onClick={() => setActiveTab('mcp')}
            className={cn(
              "flex items-center gap-3 px-2 py-1.5 rounded-md text-xs font-medium transition-all group",
              activeTab === 'mcp'
                ? "dark:bg-white/10 bg-black/10 text-foreground"
                : "dark:hover:bg-white/5 hover:bg-black/5 text-foreground/80"
            )}
          >
            <Link2 className={cn(
              "h-4 w-4 transition-colors",
              activeTab === 'mcp' ? "text-foreground" : "text-muted-foreground group-hover:text-foreground"
            )} />
            <span>{t("agents.sidebar.mcp")}</span>
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
                          className="flex-1 min-w-0 flex items-center gap-2 px-2 py-2 select-none cursor-pointer"
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
                          {repo.issues.some((i) => !!streamingThreadIds[i.id]) && (
                            <div className="h-3 w-3 shrink-0 rounded-full border border-t-foreground/60 border-foreground/20 animate-spin" />
                          )}
                        </button>

                        <div className="flex items-center gap-1 opacity-0 group-hover/workspace:opacity-100 transition-opacity">
                          <TooltipProvider>
                            <Tooltip>
                              <TooltipTrigger asChild>
                                <button
                                  onClick={() => handleAddThread(repo.id)}
                                  disabled={addingThreadForRepo === repo.id}
                                  className="p-1 rounded dark:hover:bg-white/5 hover:bg-black/5 text-muted-foreground/40 hover:text-foreground transition-colors disabled:opacity-50 cursor-pointer"
                                >
                                  {addingThreadForRepo === repo.id ? (
                                    <div className="h-3.5 w-3.5 border border-white/30 border-t-white/80 rounded-full animate-spin" />
                                  ) : (
                                    <Plus className="h-3.5 w-3.5" />
                                  )}
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
                            <DropdownMenuContent align="end" className="w-56 dark:bg-[#0D0D0D] bg-popover dark:border-white/[0.05] border-border p-1 shadow-2xl rounded-md">
                              <DropdownMenuLabel className="px-3 py-2 text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">
                                {t("common.open")}
                              </DropdownMenuLabel>
                              <DropdownMenuItem
                                onClick={() => handleOpenSourcePicker("issue", repo)}
                                className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 dark:focus:bg-white/5 focus:bg-black/5 rounded-md cursor-pointer"
                              >
                                <CircleDot className="h-4 w-4 text-foreground/40" />
                                <span>{t("agents.sidebar.fromIssue")}</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem
                                onClick={() => handleOpenSourcePicker("pr", repo)}
                                className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 dark:focus:bg-white/5 focus:bg-black/5 rounded-md cursor-pointer"
                              >
                                <GitPullRequest className="h-4 w-4 text-foreground/40" />
                                <span>{t("agents.sidebar.fromPr")}</span>
                              </DropdownMenuItem>
                              <DropdownMenuItem
                                onClick={() => handleOpenSourcePicker("branch", repo)}
                                className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 dark:focus:bg-white/5 focus:bg-black/5 rounded-md cursor-pointer"
                              >
                                <GitBranch className="h-4 w-4 text-foreground/40" />
                                <span>{t("agents.sidebar.fromBranch")}</span>
                              </DropdownMenuItem>

                              <DropdownMenuSeparator className="dark:bg-white/[0.03] bg-black/[0.05]" />

                              <DropdownMenuLabel className="px-3 py-2 text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">
                                {t("common.manage")}
                              </DropdownMenuLabel>

                              <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 dark:focus:bg-white/5 focus:bg-black/5 rounded-md cursor-pointer">
                                <Rocket className="h-4 w-4 text-foreground/40" />
                                <span>{t("agents.sidebar.autopilot")}</span>
                              </DropdownMenuItem>

                              <DropdownMenuItem
                                onClick={() => handleViewRepo(repo)}
                                className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 dark:focus:bg-white/5 focus:bg-black/5 rounded-md cursor-pointer"
                              >
                                <ExternalLink className="h-4 w-4 text-foreground/40" />
                                <span>View Repo</span>
                              </DropdownMenuItem>

                              <DropdownMenuItem
                                onClick={() => setRepoSettingsTarget(repo.id)}
                                className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 dark:focus:bg-white/5 focus:bg-black/5 rounded-md cursor-pointer"
                              >
                                <Settings className="h-4 w-4 text-foreground/40" />
                                <span>{t("agents.sidebar.settings")}</span>
                              </DropdownMenuItem>

                              <DropdownMenuSeparator className="dark:bg-white/[0.03] bg-black/[0.05]" />

                              <DropdownMenuLabel className="px-3 py-2 text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">
                                {t("common.dangerZone")}
                              </DropdownMenuLabel>

                              <DropdownMenuItem
                                onClick={() => setRepoToRemove({ id: repo.id, name: repo.name })}
                                className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-red-500/10 text-red-500 rounded-md cursor-pointer"
                              >
                                <Trash2 className="h-4 w-4" />
                                <span>{t("common.remove")}</span>
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
                                      ? "text-foreground font-semibold"
                                      : "text-foreground/80 font-medium"
                                  )}>
                                    {issue.title}
                                  </span>
                                  {!!streamingThreadIds[issue.id] && (
                                    <span className="flex items-center gap-[3px] shrink-0">
                                      <span className="h-[3px] w-[3px] rounded-full dark:bg-white/50 bg-foreground/50 animate-bounce [animation-delay:0ms]" />
                                      <span className="h-[3px] w-[3px] rounded-full dark:bg-white/50 bg-foreground/50 animate-bounce [animation-delay:150ms]" />
                                      <span className="h-[3px] w-[3px] rounded-full dark:bg-white/50 bg-foreground/50 animate-bounce [animation-delay:300ms]" />
                                    </span>
                                  )}
                                  {prUrlByThread[issue.id] && (
                                    <button
                                      type="button"
                                      onClick={(event) => {
                                        event.stopPropagation();
                                        void openUrl(prUrlByThread[issue.id]!.url);
                                      }}
                                      className="shrink-0 cursor-pointer"
                                      title={t("agents.header.viewPr")}
                                    >
                                      <GitPullRequest
                                        className={cn(
                                          "h-3 w-3 shrink-0 transition-opacity hover:opacity-80",
                                          prUrlByThread[issue.id]?.isDraft
                                            ? "text-zinc-500"
                                            : "text-[#A855F7]"
                                        )}
                                      />
                                    </button>
                                  )}
                                </div>
                                <div className="hidden group-hover/thread:flex items-center gap-2 shrink-0 ml-auto">
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

      <SidebarFooter className="p-3 border-t border-border/10">
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              onClick={() => navigateTo("settings")}
              tooltip={t("nav.settings")}
              className="transition-all duration-200 rounded-md h-10 px-3 text-zinc-500 hover:bg-zinc-100/50 dark:hover:bg-zinc-900/50 hover:text-foreground dark:hover:text-zinc-300 group-data-[collapsible=icon]:size-10 group-data-[collapsible=icon]:p-0"
            >
              <div className="flex items-center justify-center shrink-0 text-zinc-500">
                <Settings className="h-4 w-4" />
              </div>
              <span className="ml-3 text-[13px] font-medium group-data-[collapsible=icon]:hidden">
                {t("nav.settings")}
              </span>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>

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

      {sourcePicker ? (
        <ThreadSourcePickerDialog
          open={!!sourcePicker}
          onOpenChange={(open) => {
            if (!open) {
              setSourcePicker(null);
            }
          }}
          kind={sourcePicker.kind}
          repoName={sourcePicker.repoName}
          items={sourcePickerItems}
          isLoading={sourcePickerLoading}
          isCreating={creatingSourceThread}
          onSelect={handleSelectSourceItem}
        />
      ) : null}

      <Dialog open={!!linkRepoDialog} onOpenChange={(open) => !open && setLinkRepoDialog(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>{t("agents.linkRepoDialog.title")}</DialogTitle>
            <DialogDescription>
              {t("agents.linkRepoDialog.description").replace("{repo}", linkRepoDialog?.repoName ?? "")}
            </DialogDescription>
          </DialogHeader>

          <div className="mt-4 space-y-2">
            {isLoadingOrganizations ? (
              <div className="rounded-lg border border-border px-3 py-4 text-sm text-muted-foreground">
                {t("agents.linkRepoDialog.loading")}
              </div>
            ) : organizations.length === 0 ? (
              <div className="rounded-lg border border-border px-3 py-4 text-sm text-muted-foreground">
                {t("agents.linkRepoDialog.empty")}
              </div>
            ) : (
              <div className="space-y-3">
                <Select value={linkOrganizationId} onValueChange={setLinkOrganizationId}>
                  <SelectTrigger className="h-10 w-full rounded-md border-zinc-200 bg-zinc-100 px-3 text-sm text-zinc-700 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-200">
                    <SelectValue placeholder={t("agents.linkRepoDialog.placeholder")} />
                  </SelectTrigger>
                  <SelectContent>
                    {organizations.map((organization) => (
                      <SelectItem key={organization.id} value={organization.id}>
                        {organization.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>

                {linkRepoDialog?.requiresRemote ? (
                  <Input
                    value={manualRemoteUrl}
                    onChange={(event) => setManualRemoteUrl(event.target.value)}
                    placeholder={t("agents.linkRepoDialog.remotePlaceholder")}
                    className="h-10"
                  />
                ) : null}
              </div>
            )}
          </div>

          <DialogFooter className="mt-6">
            <Button variant="ghost" onClick={() => setLinkRepoDialog(null)}>
              {t("common.cancel")}
            </Button>
            <Button
              onClick={async () => {
                if (!linkOrganizationId || !linkRepoDialog) return;

                try {
                  if (linkRepoDialog.requiresRemote) {
                    await invoke("set_local_repository_remote", {
                      repoId: linkRepoDialog.repoId,
                      remoteUrl: manualRemoteUrl.trim(),
                    });
                  }

                  await invoke("link_local_repository_to_organization", {
                    repoId: linkRepoDialog.repoId,
                    organizationId: linkOrganizationId,
                  });

                  const nextPicker = {
                    kind: linkRepoDialog.kind,
                    repoId: linkRepoDialog.repoId,
                    repoName: linkRepoDialog.repoName,
                  };

                  setActiveOrganizationId(linkOrganizationId);
                  setLinkRepoDialog(null);
                  setManualRemoteUrl("");
                  setLinkOrganizationId("");
                  await handleOpenSourcePicker(nextPicker.kind, {
                    id: nextPicker.repoId,
                    name: nextPicker.repoName,
                  });
                } catch (error) {
                  toast.error(`${error}`);
                }
              }}
              disabled={!linkOrganizationId || (linkRepoDialog?.requiresRemote && !manualRemoteUrl.trim())}
            >
              {t("agents.linkRepoDialog.cta")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <RepoSettingsSheet
        repoId={repoSettingsTarget}
        onClose={() => setRepoSettingsTarget(null)}
      />
    </Sidebar>
  );
}
