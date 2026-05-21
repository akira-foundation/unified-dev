import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";

import { useI18n } from "@/i18n/i18n";
import { queryKeys } from "@/lib/query-keys";
import { cache } from "@/config/cache";
import { useIssueMutations } from "@/hooks/useIssueMutations";
import type { ActiveRepo } from "@/stores/navigation-store";
import type { IssueDto } from "@/types/issue";
import type { BranchDto, OrganizationRepoWithOrg, OrganizationSummary, PullRequestDto } from "@/types/organization";
import type { ProviderSummary } from "@/types/provider";
import type { IssueScope, PullRequestScope } from "@/types/work-visibility";

interface UseRepositoryDetailParams {
  activeRepo: ActiveRepo | null;
  currentLogin: string | null;
  issueScope: IssueScope;
  prScope: PullRequestScope;
  allRepos: OrganizationRepoWithOrg[];
  organizations: OrganizationSummary[];
  providers: ProviderSummary[];
  resolveIssueScope: (orgId: string, repoName?: string) => IssueScope;
}

export function useRepositoryDetail({
  activeRepo,
  currentLogin,
  issueScope,
  prScope,
  allRepos,
  organizations,
  providers,
  resolveIssueScope,
}: UseRepositoryDetailParams) {
  const { t } = useI18n();
  const queryClient = useQueryClient();

  const prsQuery = useQuery({
    queryKey: queryKeys.pullRequests(activeRepo?.organizationId ?? "", activeRepo?.name ?? "", prScope),
    queryFn: () =>
      invoke<PullRequestDto[]>("list_repo_pull_requests", {
        organizationId: activeRepo!.organizationId,
        repoName: activeRepo!.name,
        scope: prScope,
        currentLogin,
      }),
    enabled: !!activeRepo,
    staleTime: cache.staleTime.live,
  });

  const syncPrsMutation = useMutation({
    mutationFn: async (scope: PullRequestScope) => {
      const id = toast.loading(t("pages.repositoryDetail.toast.syncingPrs"));
      try {
        await invoke("sync_pull_requests", {
          organizationId: activeRepo!.organizationId,
          repoName: activeRepo!.name,
          scope,
          currentLogin,
        });
        toast.success(t("pages.repositoryDetail.toast.syncedPrs"), { id });
      } catch (error) {
        toast.error(error instanceof Error ? error.message : String(error), { id });
        throw error;
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["pull-requests", activeRepo!.organizationId, activeRepo!.name] });
    },
  });

  const issuesQuery = useQuery({
    queryKey: queryKeys.issues(activeRepo?.organizationId ?? "", activeRepo?.name ?? "", issueScope),
    queryFn: () =>
      invoke<IssueDto[]>("list_issues", {
        orgId: activeRepo!.organizationId,
        repoName: activeRepo!.name,
        scope: issueScope,
        currentLogin,
      }),
    enabled: !!activeRepo,
    staleTime: cache.staleTime.live,
  });

  const syncIssuesMutation = useMutation({
    mutationFn: async (scope: IssueScope) => {
      const id = toast.loading(t("pages.repositoryIssues.toast.syncingIssues"));
      try {
        await invoke("sync_issues", {
          orgId: activeRepo!.organizationId,
          owner: activeRepo!.owner,
          repoName: activeRepo!.name,
          scope,
          currentLogin,
        });
        toast.success(t("pages.repositoryIssues.toast.syncedIssues"), { id });
      } catch (error) {
        toast.error(error instanceof Error ? error.message : String(error), { id });
        throw error;
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["issues", activeRepo!.organizationId, activeRepo!.name] });
    },
  });

  const issueMutations = useIssueMutations({ allRepos, organizations, providers, resolveIssueScope });

  const branchesQuery = useQuery({
    queryKey: queryKeys.branches(activeRepo?.organizationId ?? "", activeRepo?.name ?? ""),
    queryFn: () =>
      invoke<BranchDto[]>("list_repo_branches", {
        organizationId: activeRepo!.organizationId,
        repoName: activeRepo!.name,
      }),
    enabled: !!activeRepo,
    staleTime: cache.staleTime.short,
  });

  const syncBranchesMutation = useMutation({
    mutationFn: async () => {
      const id = toast.loading(t("pages.repositoryBranches.toast.syncing"));
      try {
        await invoke<void>("list_repo_branches", {
          organizationId: activeRepo!.organizationId,
          repoName: activeRepo!.name,
        });
        toast.success(t("pages.repositoryBranches.toast.synced"), { id });
      } catch (error) {
        toast.error(error instanceof Error ? error.message : String(error), { id });
        throw error;
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.branches(activeRepo!.organizationId, activeRepo!.name) });
    },
  });

  const deleteBranchMutation = useMutation({
    mutationFn: async (branchName: string) => {
      const id = toast.loading(t("pages.repositoryBranches.toast.deleting"));
      try {
        await invoke("delete_repo_branch", {
          organizationId: activeRepo!.organizationId,
          repoName: activeRepo!.name,
          branchName,
        });
        toast.success(t("pages.repositoryBranches.toast.deleted").replace("{name}", branchName), { id });
      } catch (error) {
        toast.error(error instanceof Error ? error.message : String(error), { id });
        throw error;
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.branches(activeRepo!.organizationId, activeRepo!.name) });
    },
  });

  const syncRepoMutation = useMutation({
    mutationFn: async () => {
      await Promise.all([
        invoke("sync_issues", {
          orgId: activeRepo!.organizationId,
          owner: activeRepo!.owner,
          repoName: activeRepo!.name,
          scope: issueScope,
          currentLogin,
        }),
        invoke("sync_pull_requests", {
          organizationId: activeRepo!.organizationId,
          repoName: activeRepo!.name,
          scope: prScope,
          currentLogin,
        }),
      ]);
      await invoke("sync_single_repo_stats", {
        organizationId: activeRepo!.organizationId,
        repoName: activeRepo!.name,
      });
    },
    onMutate: () => toast.loading(t("agents.sidebar.toast.syncingRepo").replace("{name}", activeRepo!.name)),
    onSuccess: (_data, _vars, loadingToast) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.allRepositories() });
      queryClient.invalidateQueries({ queryKey: ["issues", activeRepo!.organizationId, activeRepo!.name] });
      queryClient.invalidateQueries({ queryKey: ["pull-requests", activeRepo!.organizationId, activeRepo!.name] });
      toast.success(t("agents.sidebar.toast.repoSynced").replace("{name}", activeRepo!.name), { id: loadingToast as string });
    },
    onError: (err, _vars, loadingToast) => {
      toast.error(err instanceof Error ? err.message : String(err), { id: loadingToast as string });
    },
  });

  const createBranch = async (branchName: string, fromSha: string) => {
    const loadingId = toast.loading(t("pages.repositoryBranches.dialog.creating"));
    try {
      await invoke("create_repo_branch", {
        organizationId: activeRepo!.organizationId,
        repoName: activeRepo!.name,
        branchName,
        fromSha,
      });
      await queryClient.invalidateQueries({ queryKey: queryKeys.branches(activeRepo!.organizationId, activeRepo!.name) });
      toast.success(t("pages.repositoryBranches.dialog.created").replace("{name}", branchName), { id: loadingId });
    } catch (error) {
      toast.error(error instanceof Error ? error.message : String(error), { id: loadingId });
      throw error;
    }
  };

  const handleMerged = () => {
    queryClient.invalidateQueries({ queryKey: ["pull-requests", activeRepo?.organizationId ?? "", activeRepo?.name ?? ""] });
    queryClient.invalidateQueries({ queryKey: queryKeys.allRepositories() });
  };

  const handleOpenUrl = async (url: string) => {
    try {
      await openUrl(url);
    } catch {
      window.open(url, "_blank");
    }
  };

  return {
    prs: prsQuery.data ?? [],
    prsLoading: prsQuery.isLoading,
    issues: issuesQuery.data ?? [],
    issuesLoading: issuesQuery.isLoading,
    branches: branchesQuery.data ?? [],
    branchesLoading: branchesQuery.isLoading,
    syncPrsMutation,
    syncIssuesMutation,
    syncBranchesMutation,
    deleteBranchMutation,
    syncRepoMutation,
    ...issueMutations,
    createBranch,
    handleMerged,
    handleOpenUrl,
  };
}
