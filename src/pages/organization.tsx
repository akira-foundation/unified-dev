import { AppbarActions } from "../components/layout/appbar-actions";
import { PageLayout } from "../components/layout/page-layout";
import { Button } from "../components/ui/button";
import { StatCard } from "@/components/stat-card";
import { RepoList } from "@/components/repos/repo-list";
import { RepoToolbar } from "@/components/repos/repo-toolbar";
import { RepoInsightsPanel } from "@/components/repos/repo-insights-panel";
import { RemoveRepositoryDialog } from "@/components/repos/remove-repository-dialog";
import { CreateRepositoryDialog } from "@/components/repos/create-repository-dialog";
import { useOrganizations } from "../hooks/useOrganizations";
import { useFilteredRepos } from "@/hooks/useFilteredRepos";
import { useRepoActions } from "@/hooks/useRepoActions";
import { useHotkey } from "@/hooks/useHotkey";
import { useNavigationStore } from "../stores/navigation-store";
import { useSearchStore } from "../stores/search-store";
import { useRepoViewStore } from "@/stores/repo-view-store";
import { useI18n } from "../i18n/i18n";
import { repositorySelectionService } from "../services/repositorySelectionService";
import { useEffect, useMemo, useState } from "react";
import { useQuery, useMutation, useQueryClient, useQueries } from "@tanstack/react-query";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { Activity, Download, FolderGit2, Globe2, Lock, Plus, Settings2 } from "lucide-react";
import type { OrganizationRepoWithOrg, PullRequestDto } from "../types/organization";
import { EmptyState } from "../components/ui/empty-state";
import { queryKeys } from "../lib/query-keys";
import { OrgSyncSheet } from "@/components/organizations/org-sync-sheet";
import { useProviders } from "@/hooks/useProviders";
import { useSettingsStore } from "@/stores/settings-store";
import { resolveCurrentLogin } from "@/lib/work-visibility";
import type { IssueDto } from "@/types/issue";
import { cache } from "@/config/cache";

const ORG_REPO_NS = "org-repos";

export function OrganizationPage() {
  const { t } = useI18n();
  const { organizations } = useOrganizations();
  const { providers } = useProviders();
  const { resolvePrScope, resolveIssueScope } = useSettingsStore();
  const { activeOrganizationId, navigateTo } = useNavigationStore();
  const { handleViewRepo } = useRepoActions();
  const queryClient = useQueryClient();
  const [orgConfigOpen, setOrgConfigOpen] = useState(false);
  const [repoToRemove, setRepoToRemove] = useState<OrganizationRepoWithOrg | null>(null);
  const [isRemovingRepo, setIsRemovingRepo] = useState(false);
  const [showCreateDialog, setShowCreateDialog] = useState(false);
  const insightsOpen = useRepoViewStore((s) => s.insightsOpen);
  const toggleInsights = useRepoViewStore((s) => s.toggleInsights);
  useHotkey("f", toggleInsights);
  useHotkey("n", () => setShowCreateDialog(true));

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

  const filteredRepos = useFilteredRepos(reposWithScopedPrs, ORG_REPO_NS);

  const stats = useMemo(() => ({
    total: reposWithScopedPrs.length,
    publicCount: reposWithScopedPrs.filter((repo) => repo.visibility === "public").length,
    privateCount: reposWithScopedPrs.filter((repo) => repo.visibility === "private").length,
    lastImported: reposWithScopedPrs[0]?.created_at ?? null,
  }), [reposWithScopedPrs]);

  const registerSearch = useSearchStore((s) => s.registerProvider);
  useEffect(() => {
    registerSearch({
      placeholder: t("filters.search.placeholder"),
      items: reposWithScopedPrs.map((repo) => ({
        id: String(repo.id),
        title: repo.repo_name,
        subtitle: repo.owner,
        icon: <FolderGit2 className="h-3.5 w-3.5 text-zinc-400" />,
        onSelect: () => handleViewRepo(repo),
      })),
    });
    return () => registerSearch(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [reposWithScopedPrs]);

  const syncAll = useMutation({
    mutationFn: () => invoke("sync_repository_stats", { organizationId: organization!.id }),
    onMutate: () => toast.loading(t("agents.sidebar.toast.syncingAll")),
    onSuccess: (_, __, toastId) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.selectedRepositories(organization!.id) });
      toast.success(t("agents.sidebar.toast.syncAllDone"), { id: toastId as string });
    },
    onError: (_, __, toastId) => toast.error(t("agents.sidebar.toast.syncAllFailed"), { id: toastId as string }),
  });

  const syncRepo = useMutation({
    mutationFn: (repo: OrganizationRepoWithOrg) =>
      invoke("sync_single_repo_stats", { organizationId: repo.organization_id, repoName: repo.repo_name }),
    onMutate: (repo) => toast.loading(t("agents.sidebar.toast.syncingRepo").replace("{name}", repo.repo_name)),
    onSuccess: (_, repo, toastId) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.selectedRepositories(organization!.id) });
      toast.success(t("agents.sidebar.toast.repoSynced").replace("{name}", repo.repo_name), { id: toastId as string });
    },
    onError: (_, repo, toastId) => toast.error(t("agents.sidebar.toast.syncFailed").replace("{name}", repo.repo_name), { id: toastId as string }),
  });

  const handleRemoveRepo = async (deleteRemote: boolean) => {
    if (!repoToRemove) return;
    try {
      setIsRemovingRepo(true);
      if (deleteRemote) {
        const org = organizations.find((o) => o.id === repoToRemove.organization_id);
        if (!org?.provider_id) {
          toast.error("This organization has no linked provider. Cannot delete repository on GitHub.");
        } else {
          try {
            await invoke("delete_provider_repository", {
              input: { provider_id: org.provider_id, owner: repoToRemove.owner, repo_name: repoToRemove.repo_name },
            });
            toast.success(`GitHub: ${repoToRemove.owner}/${repoToRemove.repo_name} deleted.`);
          } catch (remoteError) {
            const msg = String(remoteError);
            toast.error(`GitHub delete failed: ${msg.startsWith("provider error: ") ? msg.slice(16) : msg}`);
          }
        }
      }
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
      toast.success(`Workspace: ${repoToRemove.repo_name} removed.`);
      setRepoToRemove(null);
    } catch (error) {
      toast.error(`Failed to remove repository: ${error}`);
    } finally {
      setIsRemovingRepo(false);
    }
  };

  return (
    <PageLayout className="!p-0 !space-y-0 h-[calc(100vh-4rem)] overflow-hidden">
      {organization && (
        <AppbarActions>
          <Button variant="outline" onClick={() => setShowCreateDialog(true)} title={t("dashboard.quick.newRepo")}>
            <Plus size={18} />
            <span className="hidden xl:inline">{t("dashboard.quick.newRepo")}</span>
          </Button>
          <Button onClick={() => navigateTo("import-repositories")} title={t("pages.organization.importRepositories")}>
            <Download size={18} />
            <span className="hidden xl:inline">{t("pages.organization.importRepositories")}</span>
          </Button>
          <RepoToolbar onSync={() => syncAll.mutate()} isSyncing={syncAll.isPending} filterNamespace={ORG_REPO_NS} />
          <Button variant="outline" size="icon-sm" onClick={() => setOrgConfigOpen(true)} title={t("common.configureSync")}>
            <Settings2 className="h-4 w-4" />
          </Button>
        </AppbarActions>
      )}

      <div className="flex h-full min-h-0">
        <div className="min-w-0 flex-1 overflow-y-auto custom-scrollbar p-4 md:p-6">
          {!organization ? (
            <EmptyState title={t("pages.organization.empty.title")} description={t("pages.organization.empty.description")} />
          ) : (
            <div className="flex flex-col gap-5">
              <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
                <StatCard label={t("pages.organization.stats.imported")} value={stats.total} icon={Activity} color="text-blue-500" bg="bg-blue-500/10" />
                <StatCard label={t("pages.organization.stats.public")} value={stats.publicCount} icon={Globe2} color="text-emerald-500" bg="bg-emerald-500/10" />
                <StatCard label={t("pages.organization.stats.private")} value={stats.privateCount} icon={Lock} color="text-amber-500" bg="bg-amber-500/10" />
                <div className="flex items-center gap-3 rounded-xl border border-zinc-200 p-3 dark:border-zinc-800">
                  <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md border border-zinc-100 bg-purple-500/10 text-purple-500 dark:border-zinc-800">
                    <Activity size={15} />
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-[13px] font-semibold leading-none text-zinc-900 dark:text-white">
                      {stats.lastImported ? new Date(stats.lastImported).toLocaleDateString() : "—"}
                    </div>
                    <div className="mt-1 truncate text-[10px] font-semibold uppercase tracking-widest text-zinc-400 dark:text-zinc-500">
                      {t("pages.organization.stats.lastImport")}
                    </div>
                  </div>
                </div>
              </div>

              {isLoadingRepos ? (
                <div className="space-y-3">
                  <div className="h-10 w-full animate-pulse rounded-md bg-zinc-100 dark:bg-white/[0.03]" />
                  <div className="h-10 w-full animate-pulse rounded-md bg-zinc-100 dark:bg-white/[0.03]" />
                </div>
              ) : reposWithOrg.length === 0 ? (
                <EmptyState title={t("pages.repository.empty.title")} description={t("pages.repository.empty.description")} />
              ) : (
                <RepoList
                  repos={filteredRepos}
                  onSyncRepo={(repo) => syncRepo.mutate(repo)}
                  onRemoveRepo={(repo) => setRepoToRemove(repo)}
                  syncingRepoId={syncRepo.isPending ? String(syncRepo.variables?.id) : undefined}
                />
              )}
            </div>
          )}
        </div>

        {organization && insightsOpen && (
          <RepoInsightsPanel repos={reposWithScopedPrs} filterNamespace={ORG_REPO_NS} className="w-72 shrink-0" />
        )}
      </div>

      <OrgSyncSheet organization={organization} open={orgConfigOpen} onOpenChange={setOrgConfigOpen} />
      <RemoveRepositoryDialog
        open={!!repoToRemove}
        onOpenChange={(open) => !open && setRepoToRemove(null)}
        onRemove={(deleteRemote) => void handleRemoveRepo(deleteRemote)}
        repoName={repoToRemove?.repo_name ?? ""}
        isRemoving={isRemovingRepo}
      />
      <CreateRepositoryDialog
        open={showCreateDialog}
        onOpenChange={setShowCreateDialog}
        providers={providers}
        organizations={organizations}
        defaultOrganizationId={activeOrganizationId ?? undefined}
      />
    </PageLayout>
  );
}
