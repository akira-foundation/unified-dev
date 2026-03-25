import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { CircleDot, GitPullRequest, Plus } from "lucide-react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { Card, CardContent } from "../components/ui/card";
import { Button } from "../components/ui/button";
import { EmptyState } from "../components/ui/empty-state";
import { Skeleton } from "../components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "../components/ui/tabs";
import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { PrItem } from "../components/repos/pr-item";
import { PrDetailSheet } from "../components/repos/pr-detail-sheet";
import { IssueTable } from "../components/issues/issue-table";
import { IssueDetailSheet } from "../components/issues/issue-detail-sheet";
import { CreateIssueDialog } from "../components/issues/create-issue-dialog";
import { useI18n } from "../i18n/i18n";
import { useDateLabel } from "../hooks/use-date-label";
import { useNavigationStore } from "../stores/navigation-store";
import { repositorySelectionService } from "../services/repositorySelectionService";
import { queryKeys } from "../lib/query-keys";
import type { PullRequestDto } from "../types/organization";
import type { IssueDto } from "../types/issue";

export function RepositoryDetailPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const {
    activeRepo,
    activeIssue,
    setActiveIssue,
    setActivePr,
    targetPrNumber,
    setTargetPrNumber,
    navigateTo,
  } = useNavigationStore();
  const queryClient = useQueryClient();

  const { data: allRepos = [] } = useQuery({
    queryKey: queryKeys.allRepositories(),
    queryFn: () => repositorySelectionService.listAllSelectedRepositories(),
    staleTime: 60_000,
  });

  const [tab, setTab] = useState<"prs" | "issues">("prs");
  const [selectedPr, setSelectedPr] = useState<PullRequestDto | null>(null);
  const [prSheetOpen, setPrSheetOpen] = useState(false);
  const [issueSheetOpen, setIssueSheetOpen] = useState(false);
  const [createOpen, setCreateOpen] = useState(false);

  // ── PRs ──────────────────────────────────────────────────────────────────
  const { data: prs = [], isLoading: prsLoading } = useQuery({
    queryKey: queryKeys.pullRequests(activeRepo?.organizationId ?? "", activeRepo?.name ?? ""),
    queryFn: () =>
      invoke<PullRequestDto[]>("list_repo_pull_requests", {
        organizationId: activeRepo!.organizationId,
        repoName: activeRepo!.name,
      }),
    enabled: !!activeRepo,
    staleTime: 0,
  });

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

  // ── Issues ────────────────────────────────────────────────────────────────
  const { data: issues = [], isLoading: issuesLoading } = useQuery({
    queryKey: queryKeys.issues(activeRepo?.organizationId ?? "", activeRepo?.name ?? ""),
    queryFn: () =>
      invoke<IssueDto[]>("list_issues", {
        orgId: activeRepo!.organizationId,
        repoName: activeRepo!.name,
      }),
    enabled: !!activeRepo,
    staleTime: 0,
  });

  const syncIssuesMutation = useMutation({
    mutationFn: () =>
      invoke("sync_issues", {
        orgId: activeRepo!.organizationId,
        owner: activeRepo!.owner,
        repoName: activeRepo!.name,
        stateFilter: "all",
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: queryKeys.issues(activeRepo!.organizationId, activeRepo!.name),
      });
    },
  });

  const handleMerged = () => {
    queryClient.invalidateQueries({
      queryKey: queryKeys.pullRequests(activeRepo?.organizationId ?? "", activeRepo?.name ?? ""),
    });
  };

  const handleOpenUrl = async (url: string) => {
    try {
      await openUrl(url);
    } catch {
      window.open(url, "_blank");
    }
  };

  if (!activeRepo) return null;

  const openIssuesCount = issues.filter((i) => i.status === "open").length;

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>
            {activeRepo.owner}/{activeRepo.name}
          </PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        <PageHeaderActions>
          {tab === "issues" && (
            <Button onClick={() => setCreateOpen(true)}>
              <Plus size={18} />
              {t("pages.repositoryIssues.newIssue")}
            </Button>
          )}
        </PageHeaderActions>
      </PageHeader>

      <Tabs value={tab} onValueChange={(v) => setTab(v as "prs" | "issues")}>
        <TabsList>
          <TabsTrigger value="prs">
            <GitPullRequest className="h-4 w-4" />
            {t("pages.repositoryPrs.title")}
            {prs.length > 0 && (
              <span className="ml-1.5 rounded-full bg-zinc-200 dark:bg-zinc-700 px-1.5 py-0.5 text-[10px] font-bold leading-none">
                {prs.length}
              </span>
            )}
          </TabsTrigger>
          <TabsTrigger value="issues">
            <CircleDot className="h-4 w-4" />
            {t("pages.repositoryIssues.title")}
            {openIssuesCount > 0 && (
              <span className="ml-1.5 rounded-full bg-zinc-200 dark:bg-zinc-700 px-1.5 py-0.5 text-[10px] font-bold leading-none">
                {openIssuesCount}
              </span>
            )}
          </TabsTrigger>
        </TabsList>

        {/* PRs tab */}
        <TabsContent value="prs">
          {prsLoading ? (
            <div className="space-y-3">
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
            </div>
          ) : prs.length === 0 ? (
            <EmptyState
              title={t("pages.repositoryPrs.empty.title")}
              description={t("pages.repositoryPrs.empty.description")}
            />
          ) : (
            <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
              <div className="flex flex-row items-center px-6 py-6">
                <div className="flex flex-row items-center gap-4">
                  <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
                    <GitPullRequest size={22} strokeWidth={2} />
                  </div>
                  <div className="flex flex-col gap-1">
                    <span className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">
                      {t("pages.repositoryPrs.title")}
                    </span>
                    <span className="text-[13px] font-medium text-zinc-500/80 leading-none">
                      {prs.length === 1
                        ? t("pages.repositoryPrs.openCount").replace("{count}", String(prs.length))
                        : t("pages.repositoryPrs.openCountPlural").replace("{count}", String(prs.length))}
                    </span>
                  </div>
                </div>
              </div>
              <CardContent className="p-0 border-t border-zinc-100 dark:border-zinc-800/50">
                {prs.map((pr) => (
                  <PrItem
                    key={pr.id}
                    pr={pr}
                    onOpen={handleOpenUrl}
                    onViewDetail={(pr) => { setSelectedPr(pr); setPrSheetOpen(true); }}
                    onReview={(pr) => { setActivePr(pr); navigateTo("pr-review"); }}
                  />
                ))}
              </CardContent>
            </Card>
          )}
        </TabsContent>

        {/* Issues tab */}
        <TabsContent value="issues">
          {issuesLoading ? (
            <div className="space-y-3">
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
            </div>
          ) : issues.length === 0 ? (
            <EmptyState
              title={t("pages.repositoryIssues.empty.title")}
              description={t("pages.repositoryIssues.empty.description")}
            />
          ) : (
            <IssueTable
              issues={issues}
              onSelect={(issue) => { setActiveIssue(issue); setIssueSheetOpen(true); }}
              onNavigateToPrs={(_, __, prNumber) => {
                if (prNumber !== undefined) setTargetPrNumber(prNumber);
                setTab("prs");
              }}
              onSync={() => syncIssuesMutation.mutate()}
              isSyncing={syncIssuesMutation.isPending}
            />
          )}
        </TabsContent>
      </Tabs>

      <PrDetailSheet
        pr={selectedPr}
        open={prSheetOpen}
        organizationId={activeRepo.organizationId}
        repoName={activeRepo.name}
        onOpenChange={setPrSheetOpen}
        onOpenUrl={handleOpenUrl}
        onMerged={handleMerged}
      />

      <IssueDetailSheet
        issue={activeIssue}
        open={issueSheetOpen}
        onOpenChange={setIssueSheetOpen}
      />

      <CreateIssueDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
        repos={allRepos}
        orgId={activeRepo.organizationId}
        repoName={activeRepo.name}
      />
    </PageLayout>
  );
}
