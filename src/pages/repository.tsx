import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { useEffect, useMemo, useState } from "react";
import { useQuery, useMutation, useQueries } from "@tanstack/react-query";
import { FolderGit2, GitPullRequest, Globe2, Lock, Plus } from "lucide-react";

import { RepoList } from "@/components/repos/repo-list";
import { RepoToolbar } from "@/components/repos/repo-toolbar";
import { RepoInsightsPanel } from "@/components/repos/repo-insights-panel";
import { RemoveRepositoryDialog } from "@/components/repos/remove-repository-dialog";
import { CreateRepositoryDialog } from "@/components/repos/create-repository-dialog";
import { RepositoryVisibilitySheet } from "@/components/repos/repository-visibility-sheet";
import { EmptyState } from "@/components/ui/empty-state";
import { AppbarActions } from "@/components/layout/appbar-actions";
import { PageLayout } from "@/components/layout/page-layout";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton";
import { StatCard } from "@/components/stat-card";
import { useI18n } from "@/i18n/i18n";
import { useHotkey } from "@/hooks/useHotkey";
import { useFilteredRepos } from "@/hooks/useFilteredRepos";
import { useRepoActions } from "@/hooks/useRepoActions";
import { repositorySelectionService } from "@/services/repositorySelectionService";
import { useNavigationStore } from "@/stores/navigation-store";
import { useSearchStore } from "@/stores/search-store";
import { useRepoViewStore } from "@/stores/repo-view-store";
import { useOrganizations } from "@/hooks/useOrganizations";
import { useProviders } from "@/hooks/useProviders";
import { useSettingsStore } from "@/stores/settings-store";
import { resolveCurrentLogin } from "@/lib/work-visibility";
import { queryKeys } from "@/lib/query-keys";
import { cache } from "@/config/cache";
import type { OrganizationRepoWithOrg, PullRequestDto } from "@/types/organization";
import type { IssueDto } from "@/types/issue";

export function RepositoryPage() {
  const { t } = useI18n();
  const { navigateTo, setActiveOrganizationId } = useNavigationStore();
  const { organizations } = useOrganizations();
  const { providers } = useProviders();
  const { resolvePrScope, resolveIssueScope } = useSettingsStore();
  const { handleViewRepo } = useRepoActions();
  const [visibilityRepo, setVisibilityRepo] = useState<OrganizationRepoWithOrg | null>(null);
  const [repoToRemove, setRepoToRemove] = useState<OrganizationRepoWithOrg | null>(null);
  const [isRemovingRepo, setIsRemovingRepo] = useState(false);
  const [showCreateDialog, setShowCreateDialog] = useState(false);

  const insightsOpen = useRepoViewStore((s) => s.insightsOpen);
  const toggleInsights = useRepoViewStore((s) => s.toggleInsights);
  useHotkey("n", () => setShowCreateDialog(true));
  useHotkey("f", toggleInsights);

  const { data: repos = [], isLoading, refetch } = useQuery({
    queryKey: queryKeys.allRepositories(),
    queryFn: () => repositorySelectionService.listAllSelectedRepositories(),
  });

  const prQueries = useQueries({
    queries: repos.map((repo: OrganizationRepoWithOrg) => {
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
    queries: repos.map((repo: OrganizationRepoWithOrg) => {
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

  const reposWithScopedPrs = useMemo(
    () => repos.map((repo, index) => ({
      ...repo,
      open_prs_count: prQueries[index]?.data?.length ?? 0,
      open_issues_count: issueQueries[index]?.data?.length ?? 0,
    })),
    [repos, prQueries, issueQueries],
  );

  const filteredRepos = useFilteredRepos(reposWithScopedPrs, "repos");

  const stats = useMemo(() => ({
    total: reposWithScopedPrs.length,
    openPrs: reposWithScopedPrs.reduce((sum, r) => sum + (r.open_prs_count ?? 0), 0),
    privateCount: reposWithScopedPrs.filter((r) => r.visibility === "private").length,
    publicCount: reposWithScopedPrs.filter((r) => r.visibility === "public").length,
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

  const syncAllMutation = useMutation({
    mutationFn: async () => {
      const orgIds = [...new Set(repos.map((r) => r.organization_id))];
      await Promise.allSettled(orgIds.map((id) => invoke("sync_repository_stats", { organizationId: id })));
    },
    onMutate: () => toast.loading(t("agents.sidebar.toast.syncingAll")),
    onSuccess: (_d, _v, loadingToast) => {
      void refetch();
      toast.success(t("agents.sidebar.toast.syncAllDone"), { id: loadingToast as string });
    },
    onError: (_e, _v, loadingToast) => toast.error(t("agents.sidebar.toast.syncAllFailed"), { id: loadingToast as string }),
  });

  const syncRepoMutation = useMutation({
    mutationFn: (repo: OrganizationRepoWithOrg) =>
      invoke("sync_single_repo_stats", { organizationId: repo.organization_id, repoName: repo.repo_name }),
    onMutate: (repo) => toast.loading(t("agents.sidebar.toast.syncingRepo").replace("{name}", repo.repo_name)),
    onSuccess: (_d, repo, loadingToast) => {
      void refetch();
      toast.success(t("agents.sidebar.toast.repoSynced").replace("{name}", repo.repo_name), { id: loadingToast as string });
    },
    onError: (_e, repo, loadingToast) =>
      toast.error(t("agents.sidebar.toast.syncFailed").replace("{name}", repo.repo_name), { id: loadingToast as string }),
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
      void refetch();
      toast.success(`Workspace: ${repoToRemove.repo_name} removed.`);
      setRepoToRemove(null);
    } catch (error) {
      const msg = String(error);
      toast.error(msg.startsWith("provider error: ") ? msg.slice(16) : msg);
    } finally {
      setIsRemovingRepo(false);
    }
  };

  return (
    <PageLayout className="!p-0 !space-y-0 h-[calc(100vh-4rem)] overflow-hidden">
      <AppbarActions>
        <RepoToolbar onSync={() => syncAllMutation.mutate()} isSyncing={syncAllMutation.isPending} />
        <Button onClick={() => setShowCreateDialog(true)}>
          <Plus size={18} />
          {t("dashboard.quick.newRepo")}
        </Button>
      </AppbarActions>

      <div className="flex h-full min-h-0">
        <div className="min-w-0 flex-1 overflow-y-auto custom-scrollbar p-4 md:p-6">
          {isLoading ? (
            <div className="space-y-3">
              <Skeleton className="h-24 w-full" />
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
            </div>
          ) : repos.length === 0 ? (
            <EmptyState title={t("pages.repository.empty.title")} description={t("pages.repository.empty.description")} />
          ) : (
            <div className="flex flex-col gap-5">
              <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
                <StatCard label={t("pages.repository.stats.total")} value={stats.total} icon={FolderGit2} color="text-blue-500" bg="bg-blue-500/10" />
                <StatCard label={t("pages.repository.stats.openPrs")} value={stats.openPrs} icon={GitPullRequest} color="text-purple-500" bg="bg-purple-500/10" />
                <StatCard label={t("pages.repository.stats.private")} value={stats.privateCount} icon={Lock} color="text-amber-500" bg="bg-amber-500/10" />
                <StatCard label={t("pages.repository.stats.public")} value={stats.publicCount} icon={Globe2} color="text-emerald-500" bg="bg-emerald-500/10" />
              </div>

              <RepoList
                repos={filteredRepos}
                onSyncRepo={(repo) => syncRepoMutation.mutate(repo)}
                onVisibilitySettings={(repo) => setVisibilityRepo(repo)}
                onRemoveRepo={(repo) => setRepoToRemove(repo)}
                syncingRepoId={syncRepoMutation.isPending ? String(syncRepoMutation.variables?.id) : undefined}
                onOrganizationClick={(repo) => {
                  setActiveOrganizationId(repo.organization_id);
                  navigateTo("organization");
                }}
              />
            </div>
          )}
        </div>

        {insightsOpen && <RepoInsightsPanel repos={reposWithScopedPrs} className="w-72 shrink-0" />}
      </div>

      <RepositoryVisibilitySheet repo={visibilityRepo} open={!!visibilityRepo} onOpenChange={(open) => !open && setVisibilityRepo(null)} />
      <RemoveRepositoryDialog
        open={!!repoToRemove}
        onOpenChange={(open) => !open && setRepoToRemove(null)}
        onRemove={(deleteRemote) => void handleRemoveRepo(deleteRemote)}
        repoName={repoToRemove?.repo_name ?? ""}
        isRemoving={isRemovingRepo}
      />
      <CreateRepositoryDialog open={showCreateDialog} onOpenChange={setShowCreateDialog} providers={providers} organizations={organizations} />
    </PageLayout>
  );
}
