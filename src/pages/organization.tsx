import { PageHeader, PageHeaderMeta, PageHeaderTitle } from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { Button } from "../components/ui/button";
import { Card, CardContent, CardDescription, CardHeader } from "../components/ui/card";
import { RepoMetricsTable } from "../components/repos/repo-metrics-table";
import { RemoveRepositoryDialog } from "@/components/repos/remove-repository-dialog";
import { useDateLabel } from "../hooks/use-date-label";
import { useOrganizations } from "../hooks/useOrganizations";
import { useNavigationStore } from "../stores/navigation-store";
import { useI18n } from "../i18n/i18n";
import { repositorySelectionService } from "../services/repositorySelectionService";
import { useMemo, useState } from "react";
import { useQuery, useMutation, useQueryClient, useQueries } from "@tanstack/react-query";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { Activity, Download, Globe2, Lock, Settings2 } from "lucide-react";
import type { OrganizationRepoWithOrg } from "../types/organization";
import { EmptyState } from "../components/ui/empty-state";
import { queryKeys } from "../lib/query-keys";
import { OrgSyncSheet } from "@/components/organizations/org-sync-sheet";
import { useProviders } from "@/hooks/useProviders";
import { useSettingsStore } from "@/stores/settings-store";
import { resolveCurrentLogin } from "@/lib/work-visibility";
import type { PullRequestDto } from "@/types/organization";
import type { IssueDto } from "@/types/issue";
import { cache } from "@/config/cache";

export function OrganizationPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { organizations } = useOrganizations();
  const { providers } = useProviders();
  const { resolvePrScope, resolveIssueScope } = useSettingsStore();
  const { activeOrganizationId, navigateTo } = useNavigationStore();
  const queryClient = useQueryClient();
  const [orgConfigOpen, setOrgConfigOpen] = useState(false);
  const [repoToRemove, setRepoToRemove] = useState<OrganizationRepoWithOrg | null>(null);
  const [isRemovingRepo, setIsRemovingRepo] = useState(false);

  const organization = useMemo(
    () => organizations.find((item) => item.id === activeOrganizationId) ?? null,
    [organizations, activeOrganizationId],
  );

  const { data: repos = [], isLoading: isLoadingRepos } = useQuery({
    queryKey: queryKeys.selectedRepositories(organization?.id ?? ""),
    queryFn: () => repositorySelectionService.listSelectedRepositories(organization!.id),
    enabled: !!organization,
  });

  const reposWithOrg: OrganizationRepoWithOrg[] = useMemo(
    () => repos.map((r) => ({ ...r, organization_name: organization?.name ?? "" })),
    [repos, organization],
  );

  const prQueries = useQueries({
    queries: reposWithOrg.map((repo: OrganizationRepoWithOrg) => {
      const scope = resolvePrScope(repo.organization_id, repo.repo_name);
      return {
        queryKey: queryKeys.pullRequests(repo.organization_id, repo.repo_name, scope),
        queryFn: () => invoke<PullRequestDto[]>("list_repo_pull_requests", {
          organizationId: repo.organization_id,
          repoName: repo.repo_name,
          scope,
          currentLogin: resolveCurrentLogin(repo.organization_id, organizations, providers),
        }),
        staleTime: cache.staleTime.realtime,
      };
    }),
  });

  const issueQueries = useQueries({
    queries: reposWithOrg.map((repo: OrganizationRepoWithOrg) => {
      const scope = resolveIssueScope(repo.organization_id, repo.repo_name);
      return {
        queryKey: queryKeys.issues(repo.organization_id, repo.repo_name, scope),
        queryFn: () => invoke<IssueDto[]>("list_issues", {
          orgId: repo.organization_id,
          repoName: repo.repo_name,
          scope,
          currentLogin: resolveCurrentLogin(repo.organization_id, organizations, providers),
        }),
        staleTime: cache.staleTime.realtime,
      };
    }),
  });

  const reposWithScopedPrs: OrganizationRepoWithOrg[] = useMemo(
    () => reposWithOrg.map((repo, index) => ({
      ...repo,
      open_prs_count: prQueries[index]?.data?.length ?? 0,
      open_issues_count: issueQueries[index]?.data?.length ?? 0,
    })),
    [reposWithOrg, prQueries, issueQueries],
  );

  const stats = useMemo(() => {
    const total = reposWithScopedPrs.length;
    const publicCount = reposWithScopedPrs.filter((repo) => repo.visibility === "public").length;
    const privateCount = reposWithScopedPrs.filter((repo) => repo.visibility === "private").length;
    const lastImported = reposWithScopedPrs[0]?.created_at ?? null;
    return { total, publicCount, privateCount, lastImported };
  }, [reposWithScopedPrs]);

  const syncAll = useMutation({
    mutationFn: () => invoke("sync_repository_stats", { organizationId: organization!.id }),
    onMutate: () => toast.loading(t("agents.sidebar.toast.syncingAll")),
    onSuccess: (_, __, toastId) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.selectedRepositories(organization!.id) });
      toast.success(t("agents.sidebar.toast.syncAllDone"), { id: toastId as string });
    },
    onError: (_, __, toastId) => {
      toast.error(t("agents.sidebar.toast.syncAllFailed"), { id: toastId as string });
    },
  });

  const syncRepo = useMutation({
    mutationFn: (repo: OrganizationRepoWithOrg) =>
      invoke("sync_single_repo_stats", {
        organizationId: repo.organization_id,
        repoName: repo.repo_name,
      }),
    onMutate: (repo) => toast.loading(t("agents.sidebar.toast.syncingRepo").replace("{name}", repo.repo_name)),
    onSuccess: (_, repo, toastId) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.selectedRepositories(organization!.id) });
      toast.success(t("agents.sidebar.toast.repoSynced").replace("{name}", repo.repo_name), { id: toastId as string });
    },
    onError: (_, repo, toastId) => {
      toast.error(t("agents.sidebar.toast.syncFailed").replace("{name}", repo.repo_name), { id: toastId as string });
    },
  });

  const handleRemoveRepo = async () => {
    if (!repoToRemove) return;
    try {
      setIsRemovingRepo(true);
      await invoke("save_selected_repositories", {
        organizationId: repoToRemove.organization_id,
        repoList: [{
          owner: repoToRemove.owner,
          repo_name: repoToRemove.repo_name,
          visibility: repoToRemove.visibility,
          is_selected: false,
          auto_sync: repoToRemove.auto_sync,
          default_branch: repoToRemove.default_branch,
          is_fork: repoToRemove.is_fork,
          fork_owner: repoToRemove.fork_owner,
          fork_repo: repoToRemove.fork_repo,
        }],
      });
      queryClient.invalidateQueries({ queryKey: queryKeys.selectedRepositories(organization!.id) });
      toast.success(t("agents.sidebar.toast.repoRemoved").replace("{name}", repoToRemove.repo_name));
      setRepoToRemove(null);
    } catch (error) {
      toast.error(`Failed to remove repository: ${error}`);
    } finally {
      setIsRemovingRepo(false);
    }
  };

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>
            {t("pages.organization.title")}
            {organization && (
              <span className="ml-3 text-sm font-medium text-gray-500 dark:text-gray-400">
                / {organization.name} / <span className="font-mono text-xs">{organization.id}</span>
              </span>
            )}
          </PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
            <button
              type="button"
              onClick={() => setOrgConfigOpen(true)}
              className="ml-1 inline-flex h-7 w-7 items-center justify-center rounded-md text-zinc-400 transition-colors hover:bg-zinc-100 hover:text-zinc-700 dark:hover:bg-zinc-900 dark:hover:text-zinc-200"
              title={t("common.configureSync")}
            >
              <Settings2 className="h-4 w-4" />
            </button>
          </PageHeaderMeta>
        </div>
        {organization && (
          <Button onClick={() => navigateTo("import-repositories")}>
            <Download size={18} />
            {t("pages.organization.importRepositories")}
          </Button>
        )}
      </PageHeader>
      <div className="flex flex-col gap-6">
        {!organization && (
          <EmptyState
            title={t("pages.organization.empty.title")}
            description={t("pages.organization.empty.description")}
          />
        )}
        {organization && (
          <div className="flex flex-col gap-6">
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <Card>
                <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
                  <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
                    {t("pages.organization.stats.imported")}
                  </CardDescription>
                  <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-blue-500/10 text-blue-500">
                    <Activity size={16} />
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
                    {t("pages.organization.stats.public")}
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
              <Card>
                <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
                  <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
                    {t("pages.organization.stats.private")}
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
                    {t("pages.organization.stats.lastImport")}
                  </CardDescription>
                  <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-purple-500/10 text-purple-500">
                    <Activity size={16} />
                  </div>
                </CardHeader>
                <CardContent className="p-4 pt-4">
                  <div className="text-md font-semibold text-zinc-900 dark:text-white">
                    {stats.lastImported ? new Date(stats.lastImported).toLocaleString() : "—"}
                  </div>
                </CardContent>
              </Card>
            </div>
            {!isLoadingRepos && reposWithOrg.length > 0 && (
              <RepoMetricsTable
                repos={reposWithScopedPrs}
                filterNamespace="org-repos"
                onSync={() => syncAll.mutate()}
                isSyncing={syncAll.isPending}
                onSyncRepo={(repo) => syncRepo.mutate(repo)}
                onRemoveRepo={(repo) => setRepoToRemove(repo)}
                syncingRepoId={syncRepo.isPending ? String(syncRepo.variables?.id) : undefined}
                hideOrganization
              />
            )}
          </div>
        )}
      </div>

      <OrgSyncSheet
        organization={organization}
        open={orgConfigOpen}
        onOpenChange={setOrgConfigOpen}
      />

      <RemoveRepositoryDialog
        open={!!repoToRemove}
        onOpenChange={(open) => !open && setRepoToRemove(null)}
        onRemove={() => void handleRemoveRepo()}
        repoName={repoToRemove?.repo_name ?? ""}
        isRemoving={isRemovingRepo}
      />
    </PageLayout>
  );
}
