import { useState, useEffect, useMemo } from "react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { CircleDot, ExternalLink, FileDiff, GitBranch, GitPullRequest, Plus, RefreshCw, Trash2 } from "lucide-react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { toast } from "sonner";

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
import { CreateBranchDialog } from "../components/repos/create-branch-dialog";
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
import { useNavigationStore } from "../stores/navigation-store";
import { repositorySelectionService } from "../services/repositorySelectionService";
import { queryKeys } from "../lib/query-keys";
import { cache } from "../config/cache";
import { cn } from "../lib/utils";
import type { BranchDto, PullRequestDto } from "../types/organization";
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
  const [issueSheetOpen, setIssueSheetOpen] = useState(false);
  const [createOpen, setCreateOpen] = useState(false);
  const [createBranchOpen, setCreateBranchOpen] = useState(false);
  const [branchToDelete, setBranchToDelete] = useState<string | null>(null);

  // ── PRs ──────────────────────────────────────────────────────────────────
  const { data: prs = [], isLoading: prsLoading } = useQuery({
    queryKey: queryKeys.pullRequests(activeRepo?.organizationId ?? "", activeRepo?.name ?? ""),
    queryFn: () =>
      invoke<PullRequestDto[]>("list_repo_pull_requests", {
        organizationId: activeRepo!.organizationId,
        repoName: activeRepo!.name,
      }),
    enabled: !!activeRepo,
    staleTime: cache.staleTime.live,
  });

  const syncPrsMutation = useMutation({
    mutationFn: async () => {
      const id = toast.loading(t("pages.repositoryDetail.toast.syncingPrs"));
      try {
        await invoke("sync_pull_requests", {
          organizationId: activeRepo!.organizationId,
          repoName: activeRepo!.name,
        });
        toast.success(t("pages.repositoryDetail.toast.syncedPrs"), { id });
      } catch (error) {
        toast.error(error instanceof Error ? error.message : String(error), { id });
        throw error;
      }
    },
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
    staleTime: cache.staleTime.live,
  });

  const syncIssuesMutation = useMutation({
    mutationFn: async () => {
      const id = toast.loading(t("pages.repositoryIssues.toast.syncingIssues"));
      try {
        await invoke("sync_issues", {
          orgId: activeRepo!.organizationId,
          owner: activeRepo!.owner,
          repoName: activeRepo!.name,
          stateFilter: "all",
        });
        toast.success(t("pages.repositoryIssues.toast.syncedIssues"), { id });
      } catch (error) {
        toast.error(error instanceof Error ? error.message : String(error), { id });
        throw error;
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: queryKeys.issues(activeRepo!.organizationId, activeRepo!.name),
      });
    },
  });

  const deleteIssueMutation = useMutation({
    mutationFn: (issue: IssueDto) =>
      invoke("delete_issue", {
        orgId: activeRepo!.organizationId,
        repoName: activeRepo!.name,
        number: issue.number,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: queryKeys.issues(activeRepo!.organizationId, activeRepo!.name),
      });
    },
  });

  // ── Branches ──────────────────────────────────────────────────────────────
  const { data: branches = [], isLoading: branchesLoading } = useQuery({
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
      queryClient.invalidateQueries({
        queryKey: queryKeys.branches(activeRepo!.organizationId, activeRepo!.name),
      });
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
        toast.success(
          t("pages.repositoryBranches.toast.deleted").replace("{name}", branchName),
          { id },
        );
      } catch (error) {
        toast.error(error instanceof Error ? error.message : String(error), { id });
        throw error;
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: queryKeys.branches(activeRepo!.organizationId, activeRepo!.name),
      });
    },
  });

  const handleCreateBranch = async (branchName: string, fromSha: string) => {
    const loadingId = toast.loading(t("pages.repositoryBranches.dialog.creating"));
    try {
      await invoke("create_repo_branch", {
        organizationId: activeRepo!.organizationId,
        repoName: activeRepo!.name,
        branchName,
        fromSha,
      });
      await queryClient.invalidateQueries({
        queryKey: queryKeys.branches(activeRepo!.organizationId, activeRepo!.name),
      });
      toast.success(
        t("pages.repositoryBranches.dialog.created").replace("{name}", branchName),
        { id: loadingId },
      );
    } catch (error) {
      toast.error(error instanceof Error ? error.message : String(error), { id: loadingId });
      throw error;
    }
  };

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
          {tab === "branches" && (
            <Button onClick={() => setCreateBranchOpen(true)}>
              <Plus size={18} />
              {t("pages.repositoryBranches.newBranch")}
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

      <Tabs value={tab} onValueChange={(v) => setTab(v as "prs" | "issues" | "branches")}>
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
          <TabsTrigger value="branches">
            <GitBranch className="h-4 w-4" />
            {t("pages.repositoryBranches.title")}
            {branches.length > 0 && (
              <span className="ml-1.5 rounded-full bg-zinc-200 dark:bg-zinc-700 px-1.5 py-0.5 text-[10px] font-bold leading-none">
                {branches.length}
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
               filterNamespace="repo-issues"
               onSelect={(issue) => { setActiveIssue(issue); setIssueSheetOpen(true); }}
              onNavigateToPrs={(_, __, prNumber) => {
                if (prNumber !== undefined) setTargetPrNumber(prNumber);
                setTab("prs");
              }}
              onSync={() => syncIssuesMutation.mutate()}
              isSyncing={syncIssuesMutation.isPending}
              onOpenUrl={handleOpenUrl}
              onDelete={(issue) => deleteIssueMutation.mutateAsync(issue).then(() => undefined)}
            />
          )}
        </TabsContent>
        {/* Branches tab */}
        <TabsContent value="branches">
          {branchesLoading ? (
            <div className="space-y-3">
              <Skeleton className="h-12 w-full" />
              <Skeleton className="h-12 w-full" />
              <Skeleton className="h-12 w-full" />
              <Skeleton className="h-12 w-full" />
            </div>
          ) : branches.length === 0 ? (
            <EmptyState
              title={t("pages.repositoryBranches.empty.title")}
              description={t("pages.repositoryBranches.empty.description")}
            />
          ) : (
            <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
              <div className="flex flex-row items-center justify-between px-6 py-6">
                <div className="flex flex-row items-center gap-4">
                  <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-blue-500/10 text-blue-500 border border-blue-500/10 shrink-0">
                    <GitBranch size={22} strokeWidth={2} />
                  </div>
                  <div className="flex flex-col gap-1">
                    <span className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">
                      {t("pages.repositoryBranches.title")}
                    </span>
                    <span className="text-[13px] font-medium text-zinc-500/80 leading-none">
                      {branches.length === 1
                        ? t("pages.repositoryBranches.count").replace("{count}", String(branches.length))
                        : t("pages.repositoryBranches.countPlural").replace("{count}", String(branches.length))}
                    </span>
                  </div>
                </div>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => syncBranchesMutation.mutate()}
                  disabled={syncBranchesMutation.isPending}
                >
                  <RefreshCw className={cn("h-4 w-4", syncBranchesMutation.isPending && "animate-spin")} />
                  {t("pages.repositoryBranches.syncBranches")}
                </Button>
              </div>
              <CardContent className="p-0 border-t border-zinc-100 dark:border-zinc-800/50">
                {branches.map((branch) => (
                  <div
                    key={branch.name}
                    className="flex items-center justify-between px-6 py-3 border-b border-zinc-100 dark:border-zinc-800/50 last:border-0 hover:bg-zinc-50 dark:hover:bg-zinc-800/30 transition-colors"
                  >
                    <div className="flex items-center gap-2 min-w-0">
                      <GitBranch className="h-4 w-4 shrink-0 text-zinc-400" />
                      <span className="font-mono text-sm font-medium text-zinc-900 dark:text-white truncate">
                        {branch.name}
                      </span>
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      {branch.is_default && (
                        <Badge variant="secondary" className="text-[10px] px-1.5 py-0">
                          {t("pages.repositoryBranches.default")}
                        </Badge>
                      )}
                      {branch.is_protected && (
                        <Badge variant="warning" className="text-[10px] px-1.5 py-0">
                          {t("pages.repositoryBranches.protected")}
                        </Badge>
                      )}
                      <span className="font-mono text-[11px] text-zinc-400 dark:text-zinc-500">
                        {branch.sha.slice(0, 7)}
                      </span>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-7 w-7 text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200"
                        onClick={() =>
                          void handleOpenUrl(
                            `https://github.com/${activeRepo.owner}/${activeRepo.name}/tree/${branch.name}`,
                          )
                        }
                        title={t("pages.repositoryBranches.openInBrowser")}
                      >
                        <ExternalLink className="h-3.5 w-3.5" />
                      </Button>
                      {!branch.is_default && !branch.is_protected && (
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7 text-zinc-400 hover:text-red-500 hover:bg-red-500/10"
                          disabled={deleteBranchMutation.isPending}
                          onClick={() => setBranchToDelete(branch.name)}
                          title={t("pages.repositoryBranches.deleteBranch")}
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      )}
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>
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

      <CreateBranchDialog
        open={createBranchOpen}
        onOpenChange={setCreateBranchOpen}
        branches={branches}
        defaultBranch={defaultBranch}
        onSubmit={handleCreateBranch}
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
    </PageLayout>
  );
}
