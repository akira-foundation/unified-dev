import { invoke } from "@tauri-apps/api/core";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";

import { useI18n } from "@/i18n/i18n";
import { queryKeys } from "@/lib/query-keys";
import { resolveCurrentLogin } from "@/lib/work-visibility";
import type { IssueDto } from "@/types/issue";
import type { OrganizationRepoWithOrg, OrganizationSummary } from "@/types/organization";
import type { ProviderSummary } from "@/types/provider";
import type { IssueScope } from "@/types/work-visibility";

interface UseIssueMutationsParams {
  allRepos: OrganizationRepoWithOrg[];
  organizations: OrganizationSummary[];
  providers: ProviderSummary[];
  resolveIssueScope: (orgId: string, repoName?: string) => IssueScope;
}

export function useIssueMutations({ allRepos, organizations, providers, resolveIssueScope }: UseIssueMutationsParams) {
  const { t } = useI18n();
  const queryClient = useQueryClient();

  const findRepo = (issue: IssueDto) =>
    allRepos.find((r) => r.repo_name === issue.repoName && r.organization_id === issue.orgId);

  const syncMutation = useMutation({
    mutationFn: async (scope: IssueScope) => {
      await Promise.allSettled(
        allRepos.map((repo) =>
          invoke("sync_issues", {
            orgId: repo.organization_id,
            owner: repo.owner,
            repoName: repo.repo_name,
            scope,
            currentLogin: resolveCurrentLogin(repo.organization_id, organizations, providers),
          }),
        ),
      );
    },
    onSuccess: () => {
      allRepos.forEach((repo) => {
        queryClient.invalidateQueries({ queryKey: queryKeys.issues(repo.organization_id, repo.repo_name) });
      });
    },
  });

  const deleteIssueMutation = useMutation({
    mutationFn: async (issue: IssueDto) => {
      const repo = findRepo(issue);
      try {
        return await invoke("delete_issue", {
          orgId: repo?.organization_id ?? issue.orgId,
          repoName: issue.repoName,
          number: issue.number,
          issueId: issue.id,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        if (message.includes("Issue not found")) return;
        throw error;
      }
    },
    onMutate: async (issue) => {
      const issueQueryKey = queryKeys.issues(issue.orgId, issue.repoName);
      const issueSnapshots = queryClient.getQueriesData<IssueDto[]>({ queryKey: issueQueryKey });
      issueSnapshots.forEach(([key, data]) => {
        queryClient.setQueryData<IssueDto[]>(key, (data ?? []).filter((entry) => entry.id !== issue.id));
      });

      const repoSnapshots = [
        [queryKeys.selectedRepositories(issue.orgId), queryClient.getQueryData<OrganizationRepoWithOrg[]>(queryKeys.selectedRepositories(issue.orgId))] as const,
        [queryKeys.allRepositories(), queryClient.getQueryData<OrganizationRepoWithOrg[]>(queryKeys.allRepositories())] as const,
      ];

      repoSnapshots.forEach(([key]) => {
        queryClient.setQueryData<OrganizationRepoWithOrg[]>(key, (current) =>
          current?.map((repo) => (
            repo.organization_id === issue.orgId && repo.repo_name === issue.repoName
              ? { ...repo, open_issues_count: Math.max((repo.open_issues_count ?? 1) - 1, 0) }
              : repo
          )),
        );
      });

      return { issueSnapshots, repoSnapshots };
    },
    onError: (error, _issue, context) => {
      context?.issueSnapshots.forEach(([key, data]) => queryClient.setQueryData(key, data));
      context?.repoSnapshots.forEach(([key, data]) => queryClient.setQueryData(key, data));
      toast.error(error instanceof Error ? error.message : String(error));
    },
    onSuccess: (_, issue) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.issues(issue.orgId, issue.repoName) });
      queryClient.invalidateQueries({ queryKey: queryKeys.selectedRepositories(issue.orgId) });
      queryClient.invalidateQueries({ queryKey: queryKeys.allRepositories() });
    },
  });

  const assignToMeMutation = useMutation({
    mutationFn: async (issue: IssueDto) => {
      const repo = findRepo(issue);
      const currentLogin = repo ? resolveCurrentLogin(repo.organization_id, organizations, providers) : null;
      if (!currentLogin) throw new Error(t("issues.table.toast.noCurrentUser"));

      return invoke<IssueDto>("update_issue", {
        orgId: issue.orgId,
        repoName: issue.repoName,
        number: issue.number,
        issueId: issue.id,
        input: { assignees: Array.from(new Set([...(issue.assignees ?? []), currentLogin])) },
      });
    },
    onMutate: async (issue) => {
      const repo = findRepo(issue);
      const currentLogin = repo ? resolveCurrentLogin(repo.organization_id, organizations, providers) : null;
      const scope = repo ? resolveIssueScope(repo.organization_id, repo.repo_name) : undefined;
      if (!currentLogin) return { snapshots: [] as Array<[readonly unknown[], IssueDto[] | undefined]> };

      const queryKey = queryKeys.issues(issue.orgId, issue.repoName, scope);
      const snapshots = queryClient.getQueriesData<IssueDto[]>({ queryKey });
      queryClient.setQueriesData<IssueDto[]>({ queryKey }, (current) =>
        current?.map((entry) => (
          entry.id === issue.id
            ? { ...entry, assignees: Array.from(new Set([...(entry.assignees ?? []), currentLogin])) }
            : entry
        )),
      );
      return { snapshots };
    },
    onError: (error, _issue, context) => {
      context?.snapshots.forEach(([key, data]) => queryClient.setQueryData(key, data));
      toast.error(error instanceof Error ? error.message : String(error));
    },
    onSuccess: (updatedIssue, issue) => {
      const repo = findRepo(issue);
      const scope = repo ? resolveIssueScope(repo.organization_id, repo.repo_name) : undefined;
      queryClient.setQueriesData<IssueDto[]>({ queryKey: queryKeys.issues(issue.orgId, issue.repoName, scope) }, (current) =>
        current?.map((entry) => (entry.id === updatedIssue.id ? updatedIssue : entry)),
      );
      queryClient.invalidateQueries({ queryKey: queryKeys.issues(issue.orgId, issue.repoName, scope) });
      toast.success(t("issues.table.toast.assignedToMe"));
    },
  });

  const removeIssueFromCaches = (issue: IssueDto) => {
    const repo = findRepo(issue);
    if (!repo) return;
    const scope = resolveIssueScope(repo.organization_id, repo.repo_name);

    queryClient.setQueryData<IssueDto[]>(
      queryKeys.issues(repo.organization_id, repo.repo_name, scope),
      (current) => (current ?? []).filter((entry) => entry.id !== issue.id),
    );

    for (const key of [queryKeys.selectedRepositories(issue.orgId), queryKeys.allRepositories()]) {
      queryClient.setQueryData<OrganizationRepoWithOrg[]>(key, (current) =>
        current?.map((entry) => (
          entry.organization_id === issue.orgId && entry.repo_name === issue.repoName
            ? { ...entry, open_issues_count: Math.max((entry.open_issues_count ?? 1) - 1, 0) }
            : entry
        )),
      );
    }
  };

  return { syncMutation, deleteIssueMutation, assignToMeMutation, removeIssueFromCaches };
}
