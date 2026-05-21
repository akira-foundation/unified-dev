import { useState, useEffect, useMemo } from "react";
import { CircleDot, GitBranch, GitPullRequest } from "lucide-react";
import { useRepositoryDetail } from "@/hooks/useRepositoryDetail";
import { RepoDetailTabs } from "@/components/repos/repo-detail-tabs";
import { RepoDetailHeader } from "@/components/repos/repo-detail-header";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import { PageLayout } from "../components/layout/page-layout";
import { IssueInsightsPanel } from "@/components/issues/issue-insights-panel";
import { PrInsightsPanel } from "@/components/prs/pr-insights-panel";
import { useIssueViewStore } from "@/stores/issue-view-store";
import { usePrViewStore } from "@/stores/pr-view-store";
import { useSearchStore } from "@/stores/search-store";
import { PrDetailSheet } from "../components/repos/pr-detail-sheet";
import { PrNewTaskDialog } from "../components/repos/pr-new-task-dialog";
import { CreateIssueDialog } from "../components/issues/create-issue-dialog";
import { CreateBranchDialog } from "../components/repos/create-branch-dialog";
import { RepositoryVisibilitySheet } from "@/components/repos/repository-visibility-sheet";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "../components/ui/alert-dialog";
import { useI18n } from "../i18n/i18n";
import { useDateLabel } from "../hooks/use-date-label";
import { useOrganizations } from "@/hooks/useOrganizations";
import { useProviders } from "@/hooks/useProviders";
import { useNavigationStore } from "../stores/navigation-store";
import { useSettingsStore } from "@/stores/settings-store";
import { repositorySelectionService } from "../services/repositorySelectionService";
import { queryKeys } from "../lib/query-keys";
import { cache } from "../config/cache";
import { resolveCurrentLogin } from "@/lib/work-visibility";
import type { PullRequestDto } from "../types/organization";
import { orderIssuesByColumn, type IssueDto } from "../types/issue";

export function RepositoryDetailPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const {
    activeRepo,
    setActiveIssue,
    setIssueList,
    setActivePr,
    setActiveRepo,
    targetPrNumber,
    setTargetPrNumber,
    targetRepoTab,
    setTargetRepoTab,
    navigateTo,
  } = useNavigationStore();
  const registerSearch = useSearchStore((s) => s.registerProvider);
  const { organizations } = useOrganizations();
  const { providers } = useProviders();
  const {
    resolveIssueScope,
    resolvePrScope,
    assignIssuesToSelfByDefault,
    setRepositoryPrScope,
    setRepositoryIssueScope,
  } = useSettingsStore();
  const queryClient = useQueryClient();

  const { data: allRepos = [] } = useQuery({
    queryKey: queryKeys.allRepositories(),
    queryFn: () => repositorySelectionService.listAllSelectedRepositories(),
    staleTime: cache.staleTime.short,
  });

  const currentRepo = useMemo(
    () =>
      allRepos.find(
        (r) =>
          r.repo_name === activeRepo?.name &&
          r.organization_id === activeRepo?.organizationId,
      ) ?? null,
    [allRepos, activeRepo],
  );

  const [tab, setTab] = useState<"prs" | "issues" | "branches">("prs");
  const [selectedPr, setSelectedPr] = useState<PullRequestDto | null>(null);
  const [prSheetOpen, setPrSheetOpen] = useState(false);
  const [newTaskPr, setNewTaskPr] = useState<PullRequestDto | null>(null);
  const [newTaskOpen, setNewTaskOpen] = useState(false);

  const [createOpen, setCreateOpen] = useState(false);
  const [createBranchOpen, setCreateBranchOpen] = useState(false);
  const [branchToDelete, setBranchToDelete] = useState<string | null>(null);
  const [repoConfigOpen, setRepoConfigOpen] = useState(false);

  useEffect(() => {
    if (targetRepoTab) {
      setTab(targetRepoTab);
      setTargetRepoTab(null);
    }
  }, [targetRepoTab, setTargetRepoTab]);
  const currentLogin = activeRepo ? resolveCurrentLogin(activeRepo.organizationId, organizations, providers) : null;
  const issueScope = activeRepo ? resolveIssueScope(activeRepo.organizationId, activeRepo.name) : "my_queue";
  const prScope = activeRepo ? resolvePrScope(activeRepo.organizationId, activeRepo.name) : "mine_or_review_requested";

  const data = useRepositoryDetail({ activeRepo, currentLogin, issueScope, prScope, allRepos, organizations, providers, resolveIssueScope });
  const { prs, prsLoading, issues, issuesLoading, branches, deleteBranchMutation, createBranch, handleMerged, handleOpenUrl } = data;
  const issuesInsightsOpen = useIssueViewStore((s) => s.insightsOpen);
  const prsInsightsOpen = usePrViewStore((s) => s.insightsOpen);

  useEffect(() => {
    if (!activeRepo) return;
    const repo = { name: activeRepo.name, owner: activeRepo.owner, organizationId: activeRepo.organizationId };
    if (tab === "prs") {
      registerSearch({
        placeholder: t("prs.table.search"),
        items: prs.map((pr) => ({
          id: String(pr.id),
          title: pr.title,
          subtitle: `#${pr.number}`,
          icon: <GitPullRequest className="h-3.5 w-3.5 text-zinc-400" />,
          onSelect: () => { setActiveRepo(repo); setActivePr(pr); navigateTo("pr-review"); },
        })),
      });
    } else if (tab === "issues") {
      registerSearch({
        placeholder: t("issues.table.search"),
        items: issues.map((issue) => ({
          id: issue.id,
          title: issue.title,
          subtitle: `#${issue.number}`,
          icon: <CircleDot className="h-3.5 w-3.5 text-zinc-400" />,
          onSelect: () => { setActiveIssue(issue); setIssueList(orderIssuesByColumn(issues)); navigateTo("issue-detail"); },
        })),
      });
    } else {
      registerSearch({
        placeholder: t("filters.search.placeholder"),
        items: branches.map((branch) => ({
          id: branch.name,
          title: branch.name,
          icon: <GitBranch className="h-3.5 w-3.5 text-zinc-400" />,
          onSelect: () => handleOpenUrl(`https://github.com/${repo.owner}/${repo.name}/tree/${branch.name}`),
        })),
      });
    }
    return () => registerSearch(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab, prs, issues, branches, activeRepo]);

  useEffect(() => {
    if (!targetPrNumber || prs.length === 0) return;
    const match = prs.find((pr) => pr.number === targetPrNumber);
    if (match) {
      setTab("prs");
      setSelectedPr(match);
      setPrSheetOpen(true);
      setTargetPrNumber(null);
    }
  }, [targetPrNumber, prs, setTargetPrNumber]);

  if (!activeRepo) return null;

  const openPrsCount = prs.length;
  const draftPrsCount = prs.filter((p) => p.is_draft).length;
  const openIssuesCount = issues.filter((i) => i.status === "open").length;
  const defaultBranch = currentRepo?.default_branch ?? "—";
  const visibility = currentRepo?.visibility ?? null;

  return (
    <PageLayout className="!p-0 !space-y-0 h-[calc(100vh-4rem)] overflow-hidden">
      <div className="flex h-full min-h-0">
        <div className="min-w-0 flex-1 space-y-5 overflow-y-auto custom-scrollbar p-4 md:p-6">
          <RepoDetailHeader
            activeRepo={activeRepo}
            currentRepo={currentRepo}
            defaultBranch={defaultBranch}
            visibility={visibility}
            dateLabel={dateLabel}
            tab={tab}
            openPrsCount={openPrsCount}
            draftPrsCount={draftPrsCount}
            openIssuesCount={openIssuesCount}
            prsLoading={prsLoading}
            issuesLoading={issuesLoading}
            onOpenUrl={handleOpenUrl}
            onConfigOpen={() => setRepoConfigOpen(true)}
            onCreateIssue={() => setCreateOpen(true)}
            onCreateBranch={() => setCreateBranchOpen(true)}
          />

          <RepoDetailTabs
            tab={tab}
            onTabChange={setTab}
            activeRepo={activeRepo}
            prScope={prScope}
            issueScope={issueScope}
            setRepositoryPrScope={setRepositoryPrScope}
            setRepositoryIssueScope={setRepositoryIssueScope}
            data={data}
            onNewTask={(pr) => { setNewTaskPr(pr); setNewTaskOpen(true); }}
            onSelectIssue={(issue) => { setActiveIssue(issue); setIssueList(orderIssuesByColumn(issues)); navigateTo("issue-detail"); }}
            onNavigateToPrs={(prNumber) => { if (prNumber !== undefined) setTargetPrNumber(prNumber); setTab("prs"); }}
            onDeleteBranch={(name) => setBranchToDelete(name)}
          />
        </div>

        {tab === "issues" && issuesInsightsOpen && (
          <IssueInsightsPanel issues={issues} filterNamespace="repo-issues" className="w-72 shrink-0" />
        )}
        {tab === "prs" && prsInsightsOpen && (
          <PrInsightsPanel prs={prs} filterNamespace="repo-prs" className="w-72 shrink-0" />
        )}
      </div>

      <PrDetailSheet
        pr={selectedPr}
        open={prSheetOpen}
        organizationId={activeRepo.organizationId}
        repoName={activeRepo.name}
        owner={activeRepo.owner}
        onOpenChange={setPrSheetOpen}
        onOpenUrl={handleOpenUrl}
        onMerged={handleMerged}
      />

      <CreateIssueDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
        repos={allRepos}
        issues={issues}
        currentUserLoginByOrg={currentLogin ? { [activeRepo.organizationId]: currentLogin } : {}}
        assignToSelfByDefault={assignIssuesToSelfByDefault}
        orgId={activeRepo.organizationId}
        repoName={activeRepo.name}
        onCreated={(createdIssue) => {
          queryClient.setQueryData<IssueDto[]>(
            queryKeys.issues(activeRepo.organizationId, activeRepo.name, issueScope),
            (current) => {
              if (!current) return [createdIssue];
              return [createdIssue, ...current.filter((entry) => entry.id !== createdIssue.id)];
            },
          );
        }}
      />

      <CreateBranchDialog
        open={createBranchOpen}
        onOpenChange={setCreateBranchOpen}
        branches={branches}
        defaultBranch={defaultBranch}
        onSubmit={createBranch}
      />

      <RepositoryVisibilitySheet
        repo={currentRepo}
        open={repoConfigOpen}
        onOpenChange={setRepoConfigOpen}
      />

      <AlertDialog open={!!branchToDelete} onOpenChange={(open) => { if (!open) setBranchToDelete(null); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("pages.repositoryBranches.confirm.title")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("pages.repositoryBranches.confirm.description").replace("{name}", branchToDelete ?? "")}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("common.cancel")}</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              onClick={() => {
                if (branchToDelete) deleteBranchMutation.mutate(branchToDelete);
                setBranchToDelete(null);
              }}
            >
              {t("pages.repositoryBranches.confirm.action")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <PrNewTaskDialog
        pr={newTaskPr}
        repoNameWithOwner={activeRepo ? `${activeRepo.owner}/${activeRepo.name}` : null}
        open={newTaskOpen}
        onOpenChange={setNewTaskOpen}
      />
    </PageLayout>
  );
}
