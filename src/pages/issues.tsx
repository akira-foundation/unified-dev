import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { LayoutGrid, List, Plus } from "lucide-react";
import { useMemo, useState } from "react";
import { useMutation, useQueries, useQuery, useQueryClient } from "@tanstack/react-query";

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
    mutationFn: (issue: IssueDto) => {
      const repo = allRepos.find(
        (r: OrganizationRepoWithOrg) => r.repo_name === issue.repoName && r.organization_id === issue.orgId,
      );
      return invoke("delete_issue", {
        orgId: repo?.organization_id ?? issue.orgId,
        repoName: issue.repoName,
        number: issue.number,
      });
    },
    onSuccess: (_, issue) => {
      queryClient.invalidateQueries({
        queryKey: queryKeys.issues(issue.orgId, issue.repoName),
      });
    },
  });

  async function handleOpenUrl(url: string) {
    try {
      await openUrl(url);
    } catch {
      window.open(url, "_blank");
    }
  }

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
            onDelete={(issue) => deleteIssueMutation.mutateAsync(issue).then(() => undefined)}
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
      />
    </PageLayout>
  );
}
