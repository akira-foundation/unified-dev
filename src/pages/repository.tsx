import { Plus } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { useMemo } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { FolderGit2, GitPullRequest, Globe2, Lock } from "lucide-react";

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
import { Card, CardContent, CardDescription, CardHeader } from "../components/ui/card";
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

  const stats = useMemo(() => {
    const total = repos.length;
    const openPrs = repos.reduce((sum, r) => sum + (r.open_prs_count ?? 0), 0);
    const privateCount = repos.filter((r) => r.visibility === "private").length;
    const publicCount = repos.filter((r) => r.visibility === "public").length;
    return { total, openPrs, privateCount, publicCount };
  }, [repos]);

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
            <Skeleton className="h-16 w-full" />
          </div>
        ) : repos.length === 0 ? (
          <EmptyState
            title={t("pages.repository.empty.title")}
            description={t("pages.repository.empty.description")}
          />
        ) : (
          <>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <Card>
                <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
                  <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
                    {t("pages.repository.stats.total")}
                  </CardDescription>
                  <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-blue-500/10 text-blue-500">
                    <FolderGit2 size={16} />
                  </div>
                </CardHeader>
                <CardContent className="p-4 pt-4">
                  <div className="text-2xl font-black tracking-tight text-zinc-900 dark:text-white leading-none">
                    {stats.total}
                  </div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
                  <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
                    {t("pages.repository.stats.openPrs")}
                  </CardDescription>
                  <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-purple-500/10 text-purple-500">
                    <GitPullRequest size={16} />
                  </div>
                </CardHeader>
                <CardContent className="p-4 pt-4">
                  <div className="text-2xl font-black tracking-tight text-zinc-900 dark:text-white leading-none">
                    {stats.openPrs}
                  </div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
                  <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
                    {t("pages.repository.stats.private")}
                  </CardDescription>
                  <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-amber-500/10 text-amber-500">
                    <Lock size={16} />
                  </div>
                </CardHeader>
                <CardContent className="p-4 pt-4">
                  <div className="text-2xl font-black tracking-tight text-zinc-900 dark:text-white leading-none">
                    {stats.privateCount}
                  </div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
                  <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
                    {t("pages.repository.stats.public")}
                  </CardDescription>
                  <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-emerald-500/10 text-emerald-500">
                    <Globe2 size={16} />
                  </div>
                </CardHeader>
                <CardContent className="p-4 pt-4">
                  <div className="text-2xl font-black tracking-tight text-zinc-900 dark:text-white leading-none">
                    {stats.publicCount}
                  </div>
                </CardContent>
              </Card>
            </div>

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
          </>
        )}
      </div>
    </PageLayout>
  );
}
