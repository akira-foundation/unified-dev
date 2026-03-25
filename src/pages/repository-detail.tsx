import { useState, useEffect, useMemo } from "react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { CircleDot, FileDiff, GitBranch, GitPullRequest, Plus, RefreshCw } from "lucide-react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { Badge } from "../components/ui/badge";
import { Card, CardContent } from "../components/ui/card";
import { CardDescription, CardHeader } from "../components/ui/card";
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
import { cn } from "../lib/utils";
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

  const currentRepo = useMemo(
    () =>
      allRepos.find(
        (r) =>
          r.repo_name === activeRepo?.name &&
          r.organization_id === activeRepo?.organizationId,
      ) ?? null,
    [allRepos, activeRepo],
  );

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

  const syncPrsMutation = useMutation({
    mutationFn: () =>
      invoke("sync_pull_requests", {
        organizationId: activeRepo!.organizationId,
        owner: activeRepo!.owner,
        repoName: activeRepo!.name,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: queryKeys.pullRequests(activeRepo!.organizationId, activeRepo!.name),
      });
    },
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

  const openPrsCount = prs.length;
  const draftPrsCount = prs.filter((p) => p.is_draft).length;
  const openIssuesCount = issues.filter((i) => i.status === "open").length;
  const defaultBranch = currentRepo?.default_branch ?? "—";
  const visibility = currentRepo?.visibility ?? null;

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
            {defaultBranch !== "—" && (
              <>
                <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
                <span className="flex items-center gap-1 text-zinc-500 dark:text-zinc-400">
                  <GitBranch className="h-3 w-3" />
                  {defaultBranch}
                </span>
              </>
            )}
            {visibility && (
              <>
                <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
                <Badge
                  variant={visibility === "private" ? "warning" : "secondary"}
                  className="text-[10px] px-1.5 py-0"
                >
                  {visibility}
                </Badge>
              </>
            )}
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

      {/* Stats cards */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
            <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
              {t("pages.repositoryDetail.stats.openPrs")}
            </CardDescription>
            <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-purple-500/10 text-purple-500">
              <GitPullRequest size={16} />
            </div>
          </CardHeader>
          <CardContent className="p-4 pt-4">
            <div className="text-2xl font-black tracking-tight text-zinc-900 dark:text-white leading-none">
              {prsLoading ? <Skeleton className="h-7 w-8" /> : openPrsCount}
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
            <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
              {t("pages.repositoryDetail.stats.draftPrs")}
            </CardDescription>
            <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-zinc-500/10 text-zinc-500">
              <FileDiff size={16} />
            </div>
          </CardHeader>
          <CardContent className="p-4 pt-4">
            <div className="text-2xl font-black tracking-tight text-zinc-900 dark:text-white leading-none">
              {prsLoading ? <Skeleton className="h-7 w-8" /> : draftPrsCount}
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
            <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
              {t("pages.repositoryDetail.stats.openIssues")}
            </CardDescription>
            <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-emerald-500/10 text-emerald-500">
              <CircleDot size={16} />
            </div>
          </CardHeader>
          <CardContent className="p-4 pt-4">
            <div className="text-2xl font-black tracking-tight text-zinc-900 dark:text-white leading-none">
              {issuesLoading ? <Skeleton className="h-7 w-8" /> : openIssuesCount}
            </div>
          </CardContent>
        </Card>
        <Card
          className={defaultBranch !== "—" ? "cursor-pointer hover:border-blue-500/40 transition-colors" : ""}
          onClick={() => {
            if (defaultBranch !== "—") {
              void handleOpenUrl(
                `https://github.com/${activeRepo.owner}/${activeRepo.name}/tree/${defaultBranch}`,
              );
            }
          }}
        >
          <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
            <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
              {t("pages.repositoryDetail.stats.defaultBranch")}
            </CardDescription>
            <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-blue-500/10 text-blue-500">
              <GitBranch size={16} />
            </div>
          </CardHeader>
          <CardContent className="p-4 pt-4">
            <div className="text-2xl font-black tracking-tight text-zinc-900 dark:text-white leading-none font-mono">
              {defaultBranch}
            </div>
          </CardContent>
        </Card>
      </div>

      <Tabs value={tab} onValueChange={(v) => setTab(v as "prs" | "issues")}>
        <TabsList>
          <TabsTrigger value="prs">
            <GitPullRequest className="h-4 w-4" />
            {t("pages.repositoryPrs.title")}
            {openPrsCount > 0 && (
              <span className="ml-1.5 rounded-full bg-zinc-200 dark:bg-zinc-700 px-1.5 py-0.5 text-[10px] font-bold leading-none">
                {openPrsCount}
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
              <div className="flex flex-row items-center justify-between px-6 py-6">
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
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => syncPrsMutation.mutate()}
                  disabled={syncPrsMutation.isPending}
                >
                  <RefreshCw className={cn("h-4 w-4", syncPrsMutation.isPending && "animate-spin")} />
                  {t("pages.repositoryDetail.syncPrs")}
                </Button>
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
