import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { LayoutGrid, List, Plus } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { useQueries, useQuery, useQueryClient } from "@tanstack/react-query";

import { AppbarActions } from "@/components/layout/appbar-actions";
import { PageLayout } from "@/components/layout/page-layout";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { IssueTable } from "@/components/issues/issue-table";
import { IssueKanban } from "@/components/issues/issue-kanban";
import { IssueInsightsPanel } from "@/components/issues/issue-insights-panel";
import { IssueToolbar } from "@/components/issues/issue-toolbar";
import { useFilteredIssues } from "@/hooks/useFilteredIssues";
import { useHotkey } from "@/hooks/useHotkey";
import { StatusIcon } from "@/components/issues/issue-status";
import { CreateIssueDialog } from "@/components/issues/create-issue-dialog";
import { useI18n } from "@/i18n/i18n";
import { useOrganizations } from "@/hooks/useOrganizations";
import { useProviders } from "@/hooks/useProviders";
import { useNavigationStore } from "@/stores/navigation-store";
import { useSearchStore } from "@/stores/search-store";
import { useIssueViewStore } from "@/stores/issue-view-store";
import { useSettingsStore } from "@/stores/settings-store";
import { useIssueMutations } from "@/hooks/useIssueMutations";
import { repositorySelectionService } from "@/services/repositorySelectionService";
import { trackerService, trackerIssueToDto } from "@/services/trackerService";
import { projectService, buildProjectSourceMap, sourceKey } from "@/services/projectService";
import { queryKeys } from "@/lib/query-keys";
import { issueScopeLabelKey, resolveCurrentLogin } from "@/lib/work-visibility";
import { cache } from "@/config/cache";
import { issueToColumn, orderIssuesByColumn, type IssueDto } from "@/types/issue";
import type { OrganizationRepoWithOrg } from "@/types/organization";
import type { IssueScope } from "@/types/work-visibility";

export function IssuesPage() {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const { setActiveIssue, setIssueList, setActiveRepo, setTargetPrNumber, navigateTo } = useNavigationStore();
  const { organizations } = useOrganizations();
  const { providers } = useProviders();
  const { resolveIssueScope, assignIssuesToSelfByDefault } = useSettingsStore();

  const [createOpen, setCreateOpen] = useState(false);
  const viewMode = useIssueViewStore((s) => s.viewMode);
  const setViewMode = useIssueViewStore((s) => s.setViewMode);
  const insightsOpen = useIssueViewStore((s) => s.insightsOpen);
  const toggleInsights = useIssueViewStore((s) => s.toggleInsights);

  const { data: allRepos = [], isLoading: reposLoading } = useQuery({
    queryKey: queryKeys.allRepositories(),
    queryFn: () => repositorySelectionService.listAllSelectedRepositories(),
    staleTime: cache.staleTime.long,
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
      staleTime: cache.staleTime.long,
    })),
  });

  const trackerIssuesQuery = useQuery({
    queryKey: ["tracker-issues", "linear"],
    queryFn: () => trackerService.listIssues("linear"),
    staleTime: cache.staleTime.long,
  });

  const { data: projectList = [] } = useQuery({
    queryKey: ["projects"],
    queryFn: () => projectService.list(),
    staleTime: cache.staleTime.long,
  });
  const { data: projectRepos = [] } = useQuery({
    queryKey: ["project-repos"],
    queryFn: () => projectService.listRepos(),
    staleTime: cache.staleTime.long,
  });
  const { data: repoSources = [] } = useQuery({
    queryKey: ["repo-sources"],
    queryFn: () => projectService.listSources(),
    staleTime: cache.staleTime.long,
  });
  const projectMap = useMemo(
    () => buildProjectSourceMap(projectList, projectRepos, repoSources),
    [projectList, projectRepos, repoSources],
  );

  const isLoading = reposLoading || issueQueries.some((q) => q.isLoading);
  const githubIssues: IssueDto[] = issueQueries.flatMap((q) => q.data ?? []).map((issue) => {
    const project = projectMap.get(sourceKey("github", "repo", `${issue.orgId}/${issue.repoName}`));
    return project ? { ...issue, projectId: project.id, projectName: project.name } : issue;
  });
  const trackerIssues: IssueDto[] = (trackerIssuesQuery.data ?? []).map((issue) =>
    trackerIssueToDto(issue, "linear", projectMap),
  );
  const allIssues: IssueDto[] = [...githubIssues, ...trackerIssues];
  const filteredIssues = useFilteredIssues(allIssues, "issues");

  const registerSearch = useSearchStore((s) => s.registerProvider);
  useEffect(() => {
    registerSearch({
      placeholder: t("issues.table.search"),
      items: allIssues.map((i) => ({
        id: i.id,
        title: i.title,
        subtitle: `#${i.number}`,
        icon: <StatusIcon column={issueToColumn(i)} />,
        onSelect: () => handleSelectIssue(i),
      })),
    });
    return () => registerSearch(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [allIssues]);

  useHotkey("f", toggleInsights);
  useHotkey("n", () => setCreateOpen(true));

  const { syncMutation, deleteIssueMutation, assignToMeMutation, removeIssueFromCaches } = useIssueMutations({
    allRepos,
    organizations,
    providers,
    resolveIssueScope,
  });

  const syncOptions: IssueScope[] = ["my_queue", "all_open", "all"];

  function handleSelectIssue(issue: IssueDto) {
    setActiveIssue(issue);
    setIssueList(orderIssuesByColumn(allIssues));
    navigateTo("issue-detail");
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

  async function handleOpenUrl(url: string) {
    try {
      await openUrl(url);
    } catch {
      window.open(url, "_blank");
    }
  }

  return (
    <PageLayout className="!p-0 !space-y-0 h-[calc(100vh-4rem)] overflow-hidden">
      <AppbarActions>
        <Button onClick={handleCreateClick} disabled={allRepos.length === 0} title={t("issues.page.new")}>
          <Plus size={18} />
          <span className="hidden xl:inline">{t("issues.page.new")}</span>
        </Button>
        <div className="flex items-center overflow-hidden rounded-md border border-zinc-200 dark:border-zinc-800">
          <button
            className={`px-2.5 py-1.5 transition-colors ${viewMode === "list" ? "bg-zinc-200 text-zinc-900 dark:bg-zinc-700 dark:text-white" : "text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"}`}
            onClick={() => setViewMode("list")}
            title={t("issues.page.listView")}
          >
            <List className="h-4 w-4" />
          </button>
          <button
            className={`px-2.5 py-1.5 transition-colors ${viewMode === "kanban" ? "bg-zinc-200 text-zinc-900 dark:bg-zinc-700 dark:text-white" : "text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"}`}
            onClick={() => setViewMode("kanban")}
            title={t("issues.page.kanbanView")}
          >
            <LayoutGrid className="h-4 w-4" />
          </button>
        </div>
        <IssueToolbar
          filterNamespace="issues"
          onSync={() => syncMutation.mutate("my_queue")}
          syncOptions={syncOptions.map((scope) => ({
            label: t(issueScopeLabelKey(scope)),
            onSelect: () => syncMutation.mutate(scope),
          }))}
          isSyncing={syncMutation.isPending}
          disableSync={allRepos.length === 0}
        />
      </AppbarActions>

      <div className="flex h-full min-h-0">
        <div className="min-w-0 flex-1 overflow-y-auto custom-scrollbar px-4 pb-4 md:px-6 md:pb-6">
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
              showToolbar={false}
              onSelect={handleSelectIssue}
              onNavigateToPrs={handleNavigateToPrs}
              onNavigateToRepo={handleNavigateToRepo}
              onOpenUrl={handleOpenUrl}
              onDelete={async (issue) => {
                removeIssueFromCaches(issue);
                await deleteIssueMutation.mutateAsync(issue);
              }}
              onAssignToMe={(issue) => assignToMeMutation.mutateAsync(issue).then(() => undefined)}
            />
          ) : (
            <IssueKanban issues={filteredIssues} onSelect={handleSelectIssue} onNewIssue={handleCreateClick} />
          )}
        </div>

        {insightsOpen && (
          <IssueInsightsPanel issues={allIssues} className="w-72 shrink-0" />
        )}
      </div>

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
