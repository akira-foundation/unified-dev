import { invoke } from "@tauri-apps/api/core";
import { useQueryClient } from "@tanstack/react-query";
import type { Editor } from "@tiptap/react";
import type { UseFormReturn } from "react-hook-form";

import { useI18n } from "@/i18n/i18n";
import { queryKeys } from "@/lib/query-keys";
import { useMutationWithToast } from "@/hooks/use-mutation-with-toast";
import type { IssueDto } from "@/types/issue";
import type { OrganizationRepoWithOrg } from "@/types/organization";

export interface CreateIssueValues {
  repoName: string;
  title: string;
  body?: string;
  labels?: string[];
  assignees?: string[];
}

function matchesIssueScope(issue: IssueDto, scope: string, currentLogin: string | null): boolean {
  switch (scope) {
    case "all":
      return true;
    case "all_open":
      return issue.status === "open";
    case "my_queue":
    default:
      if (issue.status !== "open") return false;
      if (!issue.syncWithProvider) return true;
      if (issue.assignees.length === 0) return true;
      return currentLogin ? issue.assignees.some((a) => a.toLowerCase() === currentLogin.toLowerCase()) : false;
  }
}

function incrementRepoIssueCount<T extends { organization_id: string; repo_name: string; open_issues_count?: number }>(
  repos: T[] | undefined,
  orgId: string,
  repoName: string,
): T[] | undefined {
  if (!repos) return repos;
  return repos.map((repo) =>
    repo.organization_id === orgId && repo.repo_name === repoName
      ? { ...repo, open_issues_count: (repo.open_issues_count ?? 0) + 1 }
      : repo,
  );
}

interface UseCreateIssueMutationParams {
  form: UseFormReturn<CreateIssueValues>;
  repos: OrganizationRepoWithOrg[];
  orgId?: string;
  currentUserLoginByOrg: Record<string, string>;
  syncWithProvider: boolean;
  assignToMyself: boolean;
  createMore: boolean;
  editor: Editor | null;
  onCreated?: (issue: IssueDto, repo: OrganizationRepoWithOrg | undefined) => void;
  onOpenChange: (open: boolean) => void;
}

export function useCreateIssueMutation({
  form,
  repos,
  orgId,
  currentUserLoginByOrg,
  syncWithProvider,
  assignToMyself,
  createMore,
  editor,
  onCreated,
  onOpenChange,
}: UseCreateIssueMutationParams) {
  const { t } = useI18n();
  const queryClient = useQueryClient();

  const findRepo = (repoName: string) =>
    repos.find((r) => r.repo_name === repoName && (orgId ? r.organization_id === orgId : true));

  return useMutationWithToast<IssueDto, CreateIssueValues>({
    mutationFn: (values) => {
      const repo = findRepo(values.repoName);
      const currentUserLogin = repo?.organization_id ? currentUserLoginByOrg[repo.organization_id] ?? null : null;
      const assignees = assignToMyself && currentUserLogin
        ? Array.from(new Set([...(values.assignees ?? []), currentUserLogin]))
        : (values.assignees ?? []);
      return invoke<IssueDto>("create_issue", {
        input: {
          org_id: repo?.organization_id ?? orgId ?? "",
          repo_name: values.repoName,
          title: values.title,
          body: values.body || null,
          labels: values.labels ?? [],
          assignees,
          sync_with_provider: syncWithProvider,
        },
      });
    },
    loadingMessage: t("issues.create.toast.creating"),
    successMessage: t("issues.create.toast.created"),
    onSuccess: (createdIssue, values) => {
      const repo = findRepo(values.repoName);
      if (repo) {
        const currentLogin = currentUserLoginByOrg[repo.organization_id] ?? null;
        const matches = queryClient.getQueriesData<IssueDto[]>({ queryKey: queryKeys.issues(repo.organization_id, repo.repo_name) });
        matches.forEach(([key, current]) => {
          if (!current) return;
          const scope = typeof key[3] === "string" ? key[3] : "my_queue";
          if (!matchesIssueScope(createdIssue, scope, currentLogin)) return;
          queryClient.setQueryData<IssueDto[]>(key, [createdIssue, ...current.filter((e) => e.id !== createdIssue.id)]);
        });
        queryClient.setQueryData<OrganizationRepoWithOrg[]>(queryKeys.selectedRepositories(repo.organization_id), (current) =>
          incrementRepoIssueCount(current, repo.organization_id, repo.repo_name),
        );
        queryClient.setQueryData<OrganizationRepoWithOrg[]>(queryKeys.allRepositories(), (current) =>
          incrementRepoIssueCount(current, repo.organization_id, repo.repo_name),
        );
        queryClient.invalidateQueries({ queryKey: queryKeys.issues(repo.organization_id, repo.repo_name) });
        queryClient.invalidateQueries({ queryKey: queryKeys.selectedRepositories(repo.organization_id) });
        queryClient.invalidateQueries({ queryKey: queryKeys.allRepositories() });
        onCreated?.(createdIssue, repo);
      }
      if (createMore) {
        form.reset({ repoName: values.repoName, title: "", body: "", labels: [], assignees: [] });
        editor?.commands.clearContent();
        return;
      }
      onOpenChange(false);
    },
    onError: (err) => {
      form.setError("root", { message: err instanceof Error ? err.message : String(err) });
    },
  });
}
