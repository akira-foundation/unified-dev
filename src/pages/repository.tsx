import { Plus } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { useMemo, useState } from "react";
import { useHotkey } from "@/hooks/useHotkey";
import { useQuery, useMutation, useQueries } from "@tanstack/react-query";
import { FolderGit2, GitPullRequest, Globe2, Lock } from "lucide-react";

import { RepoMetricsTable } from "../components/repos/repo-metrics-table";
import { RemoveRepositoryDialog } from "@/components/repos/remove-repository-dialog";
import { CreateRepositoryDialog } from "@/components/repos/create-repository-dialog";
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
import { StatCard } from "@/components/stat-card";
import { repositorySelectionService } from "../services/repositorySelectionService";
import { useNavigationStore } from "../stores/navigation-store";
import { queryKeys } from "../lib/query-keys";
import type { OrganizationRepoWithOrg } from "../types/organization";
import { RepositoryVisibilitySheet } from "@/components/repos/repository-visibility-sheet";
import { useOrganizations } from "@/hooks/useOrganizations";
import { useProviders } from "@/hooks/useProviders";
import { useSettingsStore } from "@/stores/settings-store";
import { resolveCurrentLogin } from "@/lib/work-visibility";
import type { PullRequestDto } from "@/types/organization";
import type { IssueDto } from "@/types/issue";
import { cache } from "@/config/cache";

export function RepositoryPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { navigateTo, setActiveOrganizationId } = useNavigationStore();
  const { organizations } = useOrganizations();
  const { providers } = useProviders();
  const { resolvePrScope, resolveIssueScope } = useSettingsStore();
  const [visibilityRepo, setVisibilityRepo] = useState<OrganizationRepoWithOrg | null>(null);
  const [repoToRemove, setRepoToRemove] = useState<OrganizationRepoWithOrg | null>(null);
  const [isRemovingRepo, setIsRemovingRepo] = useState(false);
  const [showCreateDialog, setShowCreateDialog] = useState(false);
  useHotkey("n", () => setShowCreateDialog(true));

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

  const stats = useMemo(() => {
    const total = reposWithScopedPrs.length;
    const openPrs = reposWithScopedPrs.reduce((sum, r) => sum + (r.open_prs_count ?? 0), 0);
    const privateCount = reposWithScopedPrs.filter((r) => r.visibility === "private").length;
    const publicCount = reposWithScopedPrs.filter((r) => r.visibility === "public").length;
    return { total, openPrs, privateCount, publicCount };
  }, [reposWithScopedPrs]);

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
              input: {
                provider_id: org.provider_id,
                owner: repoToRemove.owner,
                repo_name: repoToRemove.repo_name,
              },
            });
            toast.success(`GitHub: ${repoToRemove.owner}/${repoToRemove.repo_name} deleted.`);
          } catch (remoteError) {
            const msg = String(remoteError);
            const clean = msg.startsWith("provider error: ") ? msg.slice("provider error: ".length) : msg;
            toast.error(`GitHub delete failed: ${clean}`);
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
      const clean = msg.startsWith("provider error: ") ? msg.slice("provider error: ".length) : msg;
      toast.error(clean);
    } finally {
      setIsRemovingRepo(false);
    }
  };

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
          <Button onClick={() => setShowCreateDialog(true)}>
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
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <StatCard
                label={t("pages.repository.stats.total")}
                value={stats.total}
                icon={FolderGit2}
                color="text-blue-500"
                bg="bg-blue-500/10"
              />
              <StatCard
                label={t("pages.repository.stats.openPrs")}
                value={stats.openPrs}
                icon={GitPullRequest}
                color="text-purple-500"
                bg="bg-purple-500/10"
              />
              <StatCard
                label={t("pages.repository.stats.private")}
                value={stats.privateCount}
                icon={Lock}
                color="text-amber-500"
                bg="bg-amber-500/10"
              />
              <StatCard
                label={t("pages.repository.stats.public")}
                value={stats.publicCount}
                icon={Globe2}
                color="text-emerald-500"
                bg="bg-emerald-500/10"
              />
            </div>

            <RepoMetricsTable
              repos={reposWithScopedPrs}
              onSync={() => syncAllMutation.mutate()}
              isSyncing={syncAllMutation.isPending}
              onSyncRepo={(repo) => syncRepoMutation.mutate(repo)}
              onVisibilitySettings={(repo) => setVisibilityRepo(repo)}
              onRemoveRepo={(repo) => setRepoToRemove(repo)}
              syncingRepoId={syncRepoMutation.isPending ? String(syncRepoMutation.variables?.id) : undefined}
              onOrganizationClick={(repo) => {
                setActiveOrganizationId(repo.organization_id);
                navigateTo("organization");
              }}
            />

            <RepositoryVisibilitySheet
              repo={visibilityRepo}
              open={!!visibilityRepo}
              onOpenChange={(open) => !open && setVisibilityRepo(null)}
            />

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
            />
          </>
        )}
      </div>
    </PageLayout>
  );
}
