import { useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";

import { useNavigationStore } from "@/stores/navigation-store";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useI18n } from "@/i18n/i18n";
import { useOrganizations } from "@/hooks/useOrganizations";
import { useSidebar } from "@/components/ui/sidebar";
import { useUsage } from "@/hooks/useUsage";
import { useAutopilotStore } from "@/stores/useAutopilotStore";
import { useThreadSourceActions } from "@/hooks/useThreadSourceActions";
import { repositorySelectionService } from "@/services/repositorySelectionService";
import { openUpgradeModal } from "@/stores/upgrade-modal-store";
import type { AgentRepository } from "@/types/agents";

export function useAgentsSidebar() {
  const { t } = useI18n();
  const { toggleSidebar, state: sidebarState } = useSidebar();
  const { navigateTo, setActiveRepo } = useNavigationStore();
  const { organizations, isLoading: isLoadingOrganizations } = useOrganizations();
  const {
    repositoryGroups,
    repositoriesLoaded,
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
    loadRepositories,
  } = useAgentsStore();
  const { isFree } = useUsage();
  const { selectedJobId, jobs, selectJob, removeJobsForRepo, removeThreadReference } = useAutopilotStore();

  const [isAddingRepo, setIsAddingRepo] = useState(false);
  const [repoToRemove, setRepoToRemove] = useState<{ id: string; name: string } | null>(null);
  const [isRemovingRepo, setIsRemovingRepo] = useState(false);
  const [repoSettingsTarget, setRepoSettingsTarget] = useState<string | null>(null);
  const [addingThreadForRepo, setAddingThreadForRepo] = useState<string | null>(null);
  const [removingThreadId, setRemovingThreadId] = useState<string | null>(null);
  const [threadToRemove, setThreadToRemove] = useState<{ id: string; title: string; repoId: string } | null>(null);
  const [repoClearThreads, setRepoClearThreads] = useState<{ id: string; name: string } | null>(null);
  const [autopilotTarget, setAutopilotTarget] = useState<{ repoId: string; repoName: string } | null>(null);
  const [autopilotPanelOpen, setAutopilotPanelOpen] = useState(false);
  const [ghCliError, setGhCliError] = useState<"gh_not_installed" | "gh_not_authenticated" | null>(null);
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const searchInputRef = useRef<HTMLInputElement>(null);

  const source = useThreadSourceActions();

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
      if (String(error) === "repo_limit_reached") {
        openUpgradeModal("repo_limit_reached");
        toast.dismiss(loadingToast);
      } else if (String(error) === "gh_not_installed" || String(error) === "gh_not_authenticated") {
        toast.dismiss(loadingToast);
        setGhCliError(error as "gh_not_installed" | "gh_not_authenticated");
      } else {
        toast.error(`Error: ${error}`, { id: loadingToast });
      }
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
      const allRepos = await repositorySelectionService.listAllSelectedRepositories();
      const linked = allRepos.find((r) => r.repo_name === match[2]);
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
      if (String(error) === "thread_limit_reached") openUpgradeModal("thread_limit_reached");
      else toast.error(`Failed to create thread: ${error}`);
    } finally {
      setAddingThreadForRepo(null);
    }
  };

  const handleRemoveThread = async () => {
    if (!threadToRemove) return;
    const toastId = toast.loading(t("agents.sidebar.toast.removingThread"));
    try {
      setRemovingThreadId(threadToRemove.id);
      await invoke("delete_thread", { threadId: threadToRemove.id });
      removeThread(threadToRemove.repoId, threadToRemove.id);
      removeThreadReference(threadToRemove.id);
      await loadRepositories();
      toast.success(t("agents.sidebar.toast.threadRemoved"), { id: toastId });
      setThreadToRemove(null);
    } catch (error) {
      toast.error(String(error), { id: toastId });
    } finally {
      setRemovingThreadId(null);
    }
  };

  const handleClearThreads = async () => {
    if (!repoClearThreads) return;
    const toastId = toast.loading(t("agents.sidebar.toast.clearingThreads"));
    const repo = useAgentsStore.getState().repositoryGroups.flatMap((g) => g.repositories).find((r) => r.id === repoClearThreads.id);
    if (repo) {
      await removeJobsForRepo(repoClearThreads.id);
      const results = await Promise.allSettled(repo.issues.map((thread) => invoke("delete_thread", { threadId: thread.id })));
      for (const thread of repo.issues) removeThread(repoClearThreads.id, thread.id);
      await loadRepositories();
      if (results.some((result) => result.status === "rejected")) toast.error(t("agents.sidebar.toast.clearThreadsFailed"), { id: toastId });
      else toast.success(t("agents.sidebar.toast.threadsCleared"), { id: toastId });
    } else {
      toast.success(t("agents.sidebar.toast.threadsCleared"), { id: toastId });
    }
    setRepoClearThreads(null);
  };

  return {
    t,
    toggleSidebar,
    sidebarState,
    organizations,
    isLoadingOrganizations,
    repositoryGroups,
    repositoriesLoaded,
    selectedIssueId,
    setSelectedIssueId,
    activeTab,
    setActiveTab,
    showAddRepositoryDialog,
    setShowAddRepositoryDialog,
    expandedRepos,
    isFree,
    selectedJobId,
    jobs,
    selectJob,
    isAddingRepo,
    repoToRemove,
    setRepoToRemove,
    isRemovingRepo,
    repoSettingsTarget,
    setRepoSettingsTarget,
    addingThreadForRepo,
    removingThreadId,
    threadToRemove,
    setThreadToRemove,
    repoClearThreads,
    setRepoClearThreads,
    autopilotTarget,
    setAutopilotTarget,
    autopilotPanelOpen,
    setAutopilotPanelOpen,
    ghCliError,
    setGhCliError,
    searchOpen,
    setSearchOpen,
    searchQuery,
    setSearchQuery,
    searchInputRef,
    toggleRepo,
    handleAddRepo,
    handleViewRepo,
    handleRemoveRepo,
    handleAddThread,
    handleRemoveThread,
    handleClearThreads,
    ...source,
  };
}

export type AgentsSidebarVm = ReturnType<typeof useAgentsSidebar>;
