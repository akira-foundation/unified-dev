import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { useAgentsStore } from "../stores/useAgentsStore";
import { useNavigationStore } from "../stores/navigation-store";
import { useI18n } from "../i18n/i18n";
import type { OrganizationRepoWithOrg } from "../types/organization";

interface AddRemoteRepositoryResponse {
  repository: { id: string; name: string };
  thread: { id: string; title: string; workspace_path: string };
}

export function useRepoActions() {
  const { t } = useI18n();
  const { repositoryGroups, addThread, addRepository, setSelectedIssueId } = useAgentsStore();
  const { navigateTo, setActiveRepo } = useNavigationStore();

  const handleViewPrs = (repo: OrganizationRepoWithOrg) => {
    setActiveRepo({ name: repo.repo_name, owner: repo.owner, organizationId: repo.organization_id });
    navigateTo("repository-prs");
  };

  const handleNewTask = async (repo: OrganizationRepoWithOrg) => {
    const allRepos = repositoryGroups.flatMap((g) => g.repositories);
    const existing = allRepos.find((r) => r.name === repo.repo_name);

    if (existing) {
      const loadingToast = toast.loading(t("agents.sidebar.toast.addingRepo"));
      try {
        const thread = await invoke<{ id: string; title: string; workspace_path: string }>(
          "create_thread",
          { repoId: existing.id },
        );
        addThread(existing.id, thread);
        setSelectedIssueId(thread.id);
        navigateTo("agents");
        toast.success(t("agents.sidebar.toast.repoAdded").replace("{name}", existing.name), { id: loadingToast });
      } catch (error) {
        toast.error(`Failed to create task: ${error}`, { id: loadingToast });
      }
    } else {
      const url = `https://github.com/${repo.owner}/${repo.repo_name}`;
      const loadingToast = toast.loading(t("agents.sidebar.toast.addingRepo"));
      try {
        const response = await invoke<AddRemoteRepositoryResponse>("add_remote_repository", { url });
        if (response?.repository && response?.thread) {
          addRepository(response.repository, response.thread);
          setSelectedIssueId(response.thread.id);
          navigateTo("agents");
          toast.success(t("agents.sidebar.toast.repoAdded").replace("{name}", response.repository.name), { id: loadingToast });
        } else {
          toast.error(t("agents.sidebar.toast.invalidResponse"), { id: loadingToast });
        }
      } catch (error) {
        toast.error(`Error: ${error}`, { id: loadingToast });
      }
    }
  };

  return { handleViewPrs, handleNewTask };
}
