import { useState, useEffect, useMemo } from "react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { GitPullRequest, RefreshCw } from "lucide-react";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import { Card, CardContent } from "../components/ui/card";
import { RepoPrsFilterPopover } from "../components/repos/repo-prs-filter-popover";
import { EmptyState } from "../components/ui/empty-state";
import { Skeleton } from "../components/ui/skeleton";
import { Button } from "../components/ui/button";
import {
  PageHeader,
  PageHeaderMeta,
  PageHeaderTitle,
} from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { PrItem } from "../components/repos/pr-item";
import { useI18n } from "../i18n/i18n";
import { useDateLabel } from "../hooks/use-date-label";
import { useOrganizations } from "@/hooks/useOrganizations";
import { useProviders } from "@/hooks/useProviders";
import { useNavigationStore } from "../stores/navigation-store";
import { useFiltersStore } from "../stores/filters-store";
import { useSettingsStore } from "@/stores/settings-store";
import { queryKeys } from "../lib/query-keys";
import { resolveCurrentLogin } from "@/lib/work-visibility";
import { cache } from "../config/cache";
import type { PullRequestDto } from "../types/organization";

const FILTER_NAMESPACE = "repo-prs";

export function RepositoryPRsPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { activeRepo, navigateTo, setActivePr, targetPrNumber, setTargetPrNumber, targetPrScope, setTargetPrScope } = useNavigationStore();
  const { organizations } = useOrganizations();
  const { providers } = useProviders();
  const { resolvePrScope } = useSettingsStore();
  const queryClient = useQueryClient();
  const [isSyncing, setIsSyncing] = useState(false);
  const currentLogin = activeRepo ? resolveCurrentLogin(activeRepo.organizationId, organizations, providers) : null;
  const prScope = targetPrScope ?? (activeRepo ? resolvePrScope(activeRepo.organizationId, activeRepo.name) : "mine_or_review_requested");

  useEffect(() => {
    if (targetPrScope) {
      setTargetPrScope(null);
    }
  }, [targetPrScope, setTargetPrScope]);

  const setFilter = useFiltersStore((s) => s.setFilter);
  const clearFilters = useFiltersStore((s) => s.clearFilters);
  const storeFilters = useFiltersStore((s) => s.filters[FILTER_NAMESPACE]);

  const filters = useMemo(
    () => ({
      state: storeFilters?.state ?? [],
      isDraft: storeFilters?.isDraft ?? [],
      author: storeFilters?.author ?? [],
      labels: storeFilters?.labels ?? [],
      ciStatus: storeFilters?.ciStatus ?? [],
      reviewers: storeFilters?.reviewers ?? [],
    }),
    [storeFilters],
  );

  const { data: prs = [], isLoading } = useQuery({
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

  useEffect(() => {
    if (!targetPrNumber || prs.length === 0) return;
    const match = prs.find((pr) => pr.number === targetPrNumber);
    if (match) {
      setActivePr(match);
      setTargetPrNumber(null);
      navigateTo("pr-detail");
    }
  }, [targetPrNumber, prs, setTargetPrNumber, setActivePr, navigateTo]);

  const allAuthors = useMemo(() => {
    const set = new Set<string>();
    prs.forEach((pr) => { if (pr.author) set.add(pr.author); });
    return Array.from(set).sort();
  }, [prs]);

  const allLabels = useMemo(() => {
    const set = new Set<string>();
    prs.forEach((pr) => pr.labels.forEach((l) => set.add(l)));
    return Array.from(set).sort();
  }, [prs]);

  const allCiStatuses = useMemo(() => {
    const set = new Set<string>();
    prs.forEach((pr) => { if (pr.ci_status) set.add(pr.ci_status); });
    return Array.from(set).sort();
  }, [prs]);

  const allReviewers = useMemo(() => {
    const set = new Set<string>();
    prs.forEach((pr) => pr.reviewers.forEach((r) => set.add(r)));
    return Array.from(set).sort();
  }, [prs]);

  const showDraftsOnly = filters.isDraft.includes("true");

  const activeFilterCount =
    filters.state.length +
    filters.isDraft.length +
    filters.author.length +
    filters.labels.length +
    filters.ciStatus.length +
    filters.reviewers.length;

  const filteredPrs = useMemo(() => {
    return prs.filter((pr) => {
      if (filters.state.length > 0) {
        const prState = pr.merged_at ? "merged" : pr.state;
        if (!filters.state.includes(prState)) return false;
      }
      if (showDraftsOnly && !pr.is_draft) return false;
      if (filters.author.length > 0 && (!pr.author || !filters.author.includes(pr.author))) return false;
      if (filters.labels.length > 0 && !filters.labels.some((l) => pr.labels.includes(l))) return false;
      if (filters.ciStatus.length > 0 && (!pr.ci_status || !filters.ciStatus.includes(pr.ci_status))) return false;
      if (filters.reviewers.length > 0 && !filters.reviewers.some((r) => pr.reviewers.includes(r))) return false;
      return true;
    });
  }, [prs, filters, showDraftsOnly]);

  const handleOpenUrl = async (url: string) => {
    try {
      await openUrl(url);
    } catch {
      window.open(url, "_blank");
    }
  };

  const handleViewDetail = (pr: PullRequestDto) => {
    setActivePr(pr);
    navigateTo("pr-detail");
  };

  const handleReview = (pr: PullRequestDto) => {
    setActivePr(pr);
    navigateTo("pr-detail");
  };

  const handleSync = async () => {
    if (!activeRepo || isSyncing) return;
    setIsSyncing(true);
    try {
      await invoke("sync_pull_requests", {
        organizationId: activeRepo.organizationId,
        repoName: activeRepo.name,
        owner: activeRepo.owner,
        scope: prScope,
        currentLogin,
      });
      await queryClient.invalidateQueries({
        queryKey: queryKeys.pullRequests(activeRepo.organizationId, activeRepo.name),
      });
    } finally {
      setIsSyncing(false);
    }
  };

  if (!activeRepo) return null;

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>
            {activeRepo.owner}/{activeRepo.name}
          </PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("pages.repositoryPrs.title")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>

      </PageHeader>

      <div className="flex flex-col gap-6">
        {isLoading ? (
          <div className="space-y-3">
            <Skeleton className="h-24 w-full" />
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
            <div className="flex flex-row items-center justify-between px-6 py-6 pb-6">
              <div className="flex flex-row items-center gap-4">
                <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
                  <GitPullRequest size={22} strokeWidth={2} />
                </div>
                <div className="flex flex-col gap-1">
                  <span className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">
                    {t("pages.repositoryPrs.title")}
                  </span>
                   <span className="text-[13px] font-medium text-zinc-500/80 leading-none">
                     {filteredPrs.length === 1
                       ? t("pages.repositoryPrs.openCount").replace("{count}", String(filteredPrs.length))
                       : t("pages.repositoryPrs.openCountPlural").replace("{count}", String(filteredPrs.length))}
                   </span>
                </div>
              </div>

              <div className="flex items-center gap-2">
                <Button
                  variant="outline"
                  size="icon"
                  onClick={handleSync}
                  disabled={isSyncing}
                  title="Sync pull requests"
                >
                  <RefreshCw className={`h-4 w-4 ${isSyncing ? "animate-spin" : ""}`} />
                </Button>

                <RepoPrsFilterPopover
                  namespace={FILTER_NAMESPACE}
                  filters={filters}
                  activeFilterCount={activeFilterCount}
                  showDraftsOnly={showDraftsOnly}
                  authors={allAuthors}
                  labels={allLabels}
                  ciStatuses={allCiStatuses}
                  reviewers={allReviewers}
                  setFilter={setFilter}
                  clearFilters={clearFilters}
                />
              </div>
            </div>
            <CardContent className="">
              {filteredPrs.map((pr) => (
                 <PrItem
                   key={pr.id}
                   pr={pr}
                   onOpen={handleOpenUrl}
                   onViewDetail={handleViewDetail}
                   onReview={handleReview}
                 />
              ))}
            </CardContent>
          </Card>
        )}
      </div>
    </PageLayout>
  );
}
