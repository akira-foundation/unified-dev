import { Plus } from "lucide-react";
import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";

import { RepoMetricsTable } from "../components/repos/repo-metrics-table";
import { EmptyState } from "../components/ui/empty-state";
import type { OrganizationRepoWithOrg } from "../types/organization";
import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { useI18n } from "../i18n/i18n";
import { useDateLabel } from "../hooks/use-date-label";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "../components/ui/skeleton";
import { repositorySelectionService } from "../services/repositorySelectionService";
import { useAgentsStore } from "../stores/useAgentsStore";
import { useNavigationStore } from "../stores/navigation-store";

export function RepositoryPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const [repos, setRepos] = useState<OrganizationRepoWithOrg[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isSyncing, setIsSyncing] = useState(false);
  const [syncingRepoId, setSyncingRepoId] = useState<string | undefined>();
  const { repositoryGroups, addThread, addRepository, setSelectedIssueId } = useAgentsStore();
  const { navigateTo, setActiveOrganizationId } = useNavigationStore();

  const handleNewTask = async (repo: OrganizationRepoWithOrg) => {
    const allRepos = repositoryGroups.flatMap((g) => g.repositories);
    const existing = allRepos.find((r) => r.name === repo.repo_name);

    if (existing) {
      const loadingToast = toast.loading(t("agents.sidebar.toast.addingRepo"));
      try {
        const thread = await invoke<{ id: string; title: string; workspace_path: string }>(
          "create_thread", { repoId: existing.id }
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
        const response = await invoke<any>("add_remote_repository", { url });
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

  const handleSyncRepo = async (repo: OrganizationRepoWithOrg) => {
    setSyncingRepoId(String(repo.id));
    const loadingToast = toast.loading(t("agents.sidebar.toast.syncingRepo").replace("{name}", repo.repo_name));
    try {
      await invoke("sync_single_repo_stats", { organizationId: repo.organization_id, repoName: repo.repo_name });
      const data = await repositorySelectionService.listAllSelectedRepositories();
      setRepos(data);
      toast.success(t("agents.sidebar.toast.repoSynced").replace("{name}", repo.repo_name), { id: loadingToast });
    } catch (error) {
      toast.error(t("agents.sidebar.toast.syncFailed").replace("{name}", repo.repo_name), { id: loadingToast });
    } finally {
      setSyncingRepoId(undefined);
    }
  };

  const handleSync = async () => {
    const orgIds = [...new Set(repos.map((r) => r.organization_id))];
    setIsSyncing(true);
    const loadingToast = toast.loading(t("agents.sidebar.toast.syncingAll"));
    try {
      await Promise.allSettled(
        orgIds.map((id) => invoke("sync_repository_stats", { organizationId: id }))
      );
      const data = await repositorySelectionService.listAllSelectedRepositories();
      setRepos(data);
      toast.success(t("agents.sidebar.toast.syncAllDone"), { id: loadingToast });
    } catch (error) {
      toast.error(t("agents.sidebar.toast.syncAllFailed"), { id: loadingToast });
    } finally {
      setIsSyncing(false);
    }
  };

  useEffect(() => {
    let isMounted = true;
    setIsLoading(true);
    repositorySelectionService
      .listAllSelectedRepositories()
      .then((data) => {
        if (isMounted) {
          setRepos(data);
        }
      })
      .finally(() => {
        if (isMounted) {
          setIsLoading(false);
        }
      });

    return () => {
      isMounted = false;
    };
  }, []);

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>{t("nav.repositories")}</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        <PageHeaderActions>
          <Button>
            <Plus size={18} />
            {t("dashboard.quick.newRepo")}
          </Button>
        </PageHeaderActions>
      </PageHeader>
      <div className="flex flex-col gap-6">
        {isLoading ? (
          <div className="space-y-3">
            <Skeleton className="h-24 w-full" />
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
          </div>
        ) : repos.length === 0 ? (
          <EmptyState
            title={t("pages.repository.empty.title")}
            description={t("pages.repository.empty.description")}
          />
        ) : (
          <RepoMetricsTable
            repos={repos}
            onNewTask={handleNewTask}
            onSync={handleSync}
            isSyncing={isSyncing}
            onSyncRepo={handleSyncRepo}
            syncingRepoId={syncingRepoId}
            onOrganizationClick={(repo) => {
              setActiveOrganizationId(repo.organization_id);
              navigateTo("organization");
            }}
          />
        )}
      </div>
    </PageLayout>
  );
}
