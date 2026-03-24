import { Plus } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { useQuery, useMutation } from "@tanstack/react-query";

import { RepoMetricsTable } from "../components/repos/repo-metrics-table";
import { EmptyState } from "../components/ui/empty-state";
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
import { useNavigationStore } from "../stores/navigation-store";
import { queryKeys } from "../lib/query-keys";
import type { OrganizationRepoWithOrg } from "../types/organization";

export function RepositoryPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { navigateTo, setActiveOrganizationId } = useNavigationStore();

  const { data: repos = [], isLoading, refetch } = useQuery({
    queryKey: queryKeys.allRepositories(),
    queryFn: () => repositorySelectionService.listAllSelectedRepositories(),
  });

  const syncAllMutation = useMutation({
    mutationFn: async () => {
      const orgIds = [...new Set(repos.map((r) => r.organization_id))];
      await Promise.allSettled(
        orgIds.map((id) => invoke("sync_repository_stats", { organizationId: id })),
      );
    },
    onMutate: () => toast.loading(t("agents.sidebar.toast.syncingAll")),
    onSuccess: (_data, _vars, loadingToast) => {
      void refetch();
      toast.success(t("agents.sidebar.toast.syncAllDone"), { id: loadingToast as string });
    },
    onError: (_err, _vars, loadingToast) => {
      toast.error(t("agents.sidebar.toast.syncAllFailed"), { id: loadingToast as string });
    },
  });

  const syncRepoMutation = useMutation({
    mutationFn: (repo: OrganizationRepoWithOrg) =>
      invoke("sync_single_repo_stats", {
        organizationId: repo.organization_id,
        repoName: repo.repo_name,
      }),
    onMutate: (repo) =>
      toast.loading(t("agents.sidebar.toast.syncingRepo").replace("{name}", repo.repo_name)),
    onSuccess: (_data, repo, loadingToast) => {
      void refetch();
      toast.success(t("agents.sidebar.toast.repoSynced").replace("{name}", repo.repo_name), {
        id: loadingToast as string,
      });
    },
    onError: (_err, repo, loadingToast) => {
      toast.error(t("agents.sidebar.toast.syncFailed").replace("{name}", repo.repo_name), {
        id: loadingToast as string,
      });
    },
  });

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
            onSync={() => syncAllMutation.mutate()}
            isSyncing={syncAllMutation.isPending}
            onSyncRepo={(repo) => syncRepoMutation.mutate(repo)}
            syncingRepoId={syncRepoMutation.isPending ? String(syncRepoMutation.variables?.id) : undefined}
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
