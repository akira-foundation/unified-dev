import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { LayoutGrid, List, Plus } from "lucide-react";
import { useMemo, useState } from "react";
import { useMutation, useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";

import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "@/components/layout/page-header";
import { PageLayout } from "@/components/layout/page-layout";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { IssueTable } from "@/components/issues/issue-table";
import { IssueKanban } from "@/components/issues/issue-kanban";
import { IssueDetailSheet } from "@/components/issues/issue-detail-sheet";
import { CreateIssueDialog } from "@/components/issues/create-issue-dialog";
import { useI18n } from "@/i18n/i18n";
import { useDateLabel } from "@/hooks/use-date-label";
import { useOrganizations } from "@/hooks/useOrganizations";
import { useProviders } from "@/hooks/useProviders";
import { useNavigationStore } from "@/stores/navigation-store";
import { useSettingsStore } from "@/stores/settings-store";
import { repositorySelectionService } from "@/services/repositorySelectionService";
import { queryKeys } from "@/lib/query-keys";
import { issueScopeLabelKey, resolveCurrentLogin } from "@/lib/work-visibility";
import { cache } from "@/config/cache";
import type { IssueDto } from "@/types/issue";
import type { OrganizationRepoWithOrg } from "@/types/organization";
import type { IssueScope } from "@/types/work-visibility";

type ViewMode = "list" | "kanban";

export function IssuesPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const queryClient = useQueryClient();
  const { activeIssue, setActiveIssue, setActiveRepo, setTargetPrNumber, navigateTo } = useNavigationStore();
  const { organizations } = useOrganizations();
  const { providers } = useProviders();
  const { resolveIssueScope, assignIssuesToSelfByDefault } = useSettingsStore();

  const [viewMode, setViewMode] = useState<ViewMode>("list");
  const [sheetOpen, setSheetOpen] = useState(false);
  const [createOpen, setCreateOpen] = useState(false);

  const { data: allRepos = [], isLoading: reposLoading } = useQuery({
    queryKey: queryKeys.allRepositories(),
    queryFn: () => repositorySelectionService.listAllSelectedRepositories(),
    staleTime: cache.staleTime.short,
  });

  const currentUserLoginByOrg = useMemo(
    () => Object.fromEntries(
      allRepos
        .map((repo) => [repo.organization_id, resolveCurrentLogin(repo.organization_id, organizations, providers)])
        .filter((entry): entry is [string, string] => Boolean(entry[1])),
    ),
    [allRepos, organizations, providers],
  );

  const issueQueries = useQueries({
    queries: allRepos.map((repo: OrganizationRepoWithOrg) => ({
      queryKey: queryKeys.issues(repo.organization_id, repo.repo_name, resolveIssueScope(repo.organization_id, repo.repo_name)),
      queryFn: () =>
        invoke<IssueDto[]>("list_issues", {
          orgId: repo.organization_id,
          repoName: repo.repo_name,
          scope: resolveIssueScope(repo.organization_id, repo.repo_name),
          currentLogin: resolveCurrentLogin(repo.organization_id, organizations, providers),
        }),
      staleTime: cache.staleTime.short,
    })),
  });

  const isLoading = reposLoading || issueQueries.some((q) => q.isLoading);
  const allIssues: IssueDto[] = issueQueries.flatMap((q) => q.data ?? []);

  const syncMutation = useMutation({
    mutationFn: async (scope: IssueScope) => {
      await Promise.allSettled(
        allRepos.map((repo: OrganizationRepoWithOrg) =>
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
      allRepos.forEach((repo: OrganizationRepoWithOrg) => {
        queryClient.invalidateQueries({
          queryKey: queryKeys.issues(repo.organization_id, repo.repo_name),
        });
      });
    },
  });

  const syncOptions: IssueScope[] = ["my_queue", "all_open", "all"];

  function handleSelectIssue(issue: IssueDto) {
    setActiveIssue(issue);
    setSheetOpen(true);
  }

  function handleNavigateToPrs(repoName: string, orgId: string, prNumber?: number) {
    const repo = allRepos.find(
      (r: OrganizationRepoWithOrg) => r.repo_name === repoName && r.organization_id === orgId,
    );
    if (repo) {
      setActiveRepo({ name: repo.repo_name, owner: repo.owner, organizationId: repo.organization_id });
      if (prNumber !== undefined) {
        setTargetPrNumber(prNumber);
      }
      navigateTo("repository-detail");
    }
  }

  function handleNavigateToRepo(repoName: string, orgId: string) {
    const repo = allRepos.find(
      (r: OrganizationRepoWithOrg) => r.repo_name === repoName && r.organization_id === orgId,
    );
    if (repo) {
      setActiveRepo({ name: repo.repo_name, owner: repo.owner, organizationId: repo.organization_id });
      navigateTo("repository-detail");
    }
  }

  function handleCreateClick() {
    setCreateOpen(true);
  }

  const deleteIssueMutation = useMutation({
    mutationFn: async (issue: IssueDto) => {
      const repo = allRepos.find(
        (r: OrganizationRepoWithOrg) => r.repo_name === issue.repoName && r.organization_id === issue.orgId,
      );
      try {
        return await invoke("delete_issue", {
          orgId: repo?.organization_id ?? issue.orgId,
          repoName: issue.repoName,
          number: issue.number,
          issueId: issue.id,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        if (message.includes("Issue not found")) {
          return;
        }
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
      const message = error instanceof Error ? error.message : String(error);
      context?.issueSnapshots.forEach(([key, data]) => queryClient.setQueryData(key, data));
      context?.repoSnapshots.forEach(([key, data]) => queryClient.setQueryData(key, data));
      toast.error(message);
    },
    onSuccess: (_, issue) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.issues(issue.orgId, issue.repoName) });
      queryClient.invalidateQueries({ queryKey: queryKeys.selectedRepositories(issue.orgId) });
      queryClient.invalidateQueries({ queryKey: queryKeys.allRepositories() });
    },
  });

  const assignToMeMutation = useMutation({
    mutationFn: async (issue: IssueDto) => {
      const repo = allRepos.find(
        (r: OrganizationRepoWithOrg) => r.repo_name === issue.repoName && r.organization_id === issue.orgId,
      );
      const currentLogin = repo ? resolveCurrentLogin(repo.organization_id, organizations, providers) : null;
      if (!currentLogin) {
        throw new Error(t("issues.table.toast.noCurrentUser"));
      }

      return invoke<IssueDto>("update_issue", {
        orgId: issue.orgId,
        repoName: issue.repoName,
        number: issue.number,
        issueId: issue.id,
        input: {
          assignees: Array.from(new Set([...(issue.assignees ?? []), currentLogin])),
        },
      });
    },
    onMutate: async (issue) => {
      const repo = allRepos.find(
        (r: OrganizationRepoWithOrg) => r.repo_name === issue.repoName && r.organization_id === issue.orgId,
      );
      const currentLogin = repo ? resolveCurrentLogin(repo.organization_id, organizations, providers) : null;
      if (!currentLogin) {
        return { snapshots: [] as Array<[readonly unknown[], IssueDto[] | undefined]> };
      }

      const queryKey = queryKeys.issues(issue.orgId, issue.repoName);
      const snapshots = queryClient.getQueriesData<IssueDto[]>({ queryKey });
      queryClient.setQueriesData<IssueDto[]>({ queryKey }, (current) => {
        if (!current) return current;
        return current.map((entry) => (
          entry.id === issue.id
            ? { ...entry, assignees: Array.from(new Set([...(entry.assignees ?? []), currentLogin])) }
            : entry
        ));
      });
      return { snapshots };
    },
    onError: (error, _issue, context) => {
      context?.snapshots.forEach(([key, data]) => {
        queryClient.setQueryData(key, data);
      });
      toast.error(error instanceof Error ? error.message : String(error));
    },
    onSuccess: (updatedIssue, issue) => {
      queryClient.setQueriesData<IssueDto[]>({ queryKey: queryKeys.issues(issue.orgId, issue.repoName) }, (current) => {
        if (!current) return current;
        return current.map((entry) => (entry.id === updatedIssue.id ? updatedIssue : entry));
      });
      queryClient.invalidateQueries({ queryKey: queryKeys.issues(issue.orgId, issue.repoName) });
      toast.success(t("issues.table.toast.assignedToMe"));
    },
  });

  async function handleOpenUrl(url: string) {
    try {
      await openUrl(url);
    } catch {
      window.open(url, "_blank");
    }
  }

  const removeIssueFromCaches = (issue: IssueDto) => {
    const repo = allRepos.find(
      (r: OrganizationRepoWithOrg) => r.repo_name === issue.repoName && r.organization_id === issue.orgId,
    );
    if (!repo) return;

    const scope = resolveIssueScope(repo.organization_id, repo.repo_name);

    queryClient.setQueryData<IssueDto[]>(
      queryKeys.issues(repo.organization_id, repo.repo_name, scope),
      (current) => (current ?? []).filter((entry) => entry.id !== issue.id),
    );

    queryClient.setQueryData<OrganizationRepoWithOrg[]>(
      queryKeys.selectedRepositories(issue.orgId),
      (current) => current?.map((entry) => (
        entry.organization_id === issue.orgId && entry.repo_name === issue.repoName
          ? { ...entry, open_issues_count: Math.max((entry.open_issues_count ?? 1) - 1, 0) }
          : entry
      )),
    );

    queryClient.setQueryData<OrganizationRepoWithOrg[]>(
      queryKeys.allRepositories(),
      (current) => current?.map((entry) => (
        entry.organization_id === issue.orgId && entry.repo_name === issue.repoName
          ? { ...entry, open_issues_count: Math.max((entry.open_issues_count ?? 1) - 1, 0) }
          : entry
      )),
    );
  };

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>{t("issues.page.title")}</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        <PageHeaderActions>
          <div className="flex items-center rounded-md border border-zinc-200 dark:border-zinc-800 overflow-hidden">
            <button
              className={`px-2.5 py-1.5 transition-colors ${viewMode === "list" ? "bg-zinc-100 dark:bg-zinc-800 text-zinc-900 dark:text-white" : "text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"}`}
              onClick={() => setViewMode("list")}
              title={t("issues.page.listView")}
            >
              <List className="h-4 w-4" />
            </button>
            <button
              className={`px-2.5 py-1.5 transition-colors ${viewMode === "kanban" ? "bg-zinc-100 dark:bg-zinc-800 text-zinc-900 dark:text-white" : "text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"}`}
              onClick={() => setViewMode("kanban")}
              title={t("issues.page.kanbanView")}
            >
              <LayoutGrid className="h-4 w-4" />
            </button>
          </div>
          <Button onClick={handleCreateClick} disabled={allRepos.length === 0}>
            <Plus size={18} />
            {t("issues.page.new")}
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
        ) : viewMode === "list" ? (
          <IssueTable
            issues={allIssues}
            onSelect={handleSelectIssue}
            onNavigateToPrs={handleNavigateToPrs}
            onNavigateToRepo={handleNavigateToRepo}
            onSync={() => syncMutation.mutate("my_queue")}
            syncOptions={syncOptions.map((scope) => ({
              label: t(issueScopeLabelKey(scope)),
              onSelect: () => syncMutation.mutate(scope),
            }))}
            isSyncing={syncMutation.isPending}
            disableSync={allRepos.length === 0}
            onOpenUrl={handleOpenUrl}
            onDelete={async (issue) => {
              removeIssueFromCaches(issue);
              await deleteIssueMutation.mutateAsync(issue);
            }}
            onAssignToMe={(issue) => assignToMeMutation.mutateAsync(issue).then(() => undefined)}
          />
        ) : (
          <IssueKanban issues={allIssues} onSelect={handleSelectIssue} />
        )}
      </div>

      <IssueDetailSheet
        issue={activeIssue}
        open={sheetOpen}
        onOpenChange={setSheetOpen}
      />

      <CreateIssueDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
        repos={allRepos}
        issues={allIssues}
        currentUserLoginByOrg={currentUserLoginByOrg}
        assignToSelfByDefault={assignIssuesToSelfByDefault}
        onCreated={(createdIssue, repo) => {
          if (!repo) return;
          const scope = resolveIssueScope(repo.organization_id, repo.repo_name);
          queryClient.setQueryData<IssueDto[]>(
            queryKeys.issues(repo.organization_id, repo.repo_name, scope),
            (current) => {
              if (!current) return [createdIssue];
              return [createdIssue, ...current.filter((entry) => entry.id !== createdIssue.id)];
            },
          );
        }}
      />
    </PageLayout>
  );
}
