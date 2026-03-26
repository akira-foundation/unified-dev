import { useState, useEffect, useMemo } from "react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { Filter, GitPullRequest } from "lucide-react";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import { Card, CardContent } from "../components/ui/card";
import {
  FilterPopover,
  FilterPopoverContent,
  FilterPopoverTrigger,
} from "../components/filters/filter-popover";
import { MultiSelectFilterSection } from "../components/filters/multi-select-filter-section";
import {
  FilterBooleanSection,
  FilterPopoverHeader,
  FilterSectionDivider,
  FilterToggleSection,
} from "../components/filters/filter-popover-section";
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
import { PrDetailSheet } from "../components/repos/pr-detail-sheet";
import { useI18n } from "../i18n/i18n";
import { useDateLabel } from "../hooks/use-date-label";
import { useNavigationStore } from "../stores/navigation-store";
import { useFiltersStore } from "../stores/filters-store";
import { queryKeys } from "../lib/query-keys";
import { cache } from "../config/cache";
import type { PullRequestDto } from "../types/organization";

const FILTER_NAMESPACE = "repo-prs";

function toggleItem(arr: string[], item: string): string[] {
  return arr.includes(item) ? arr.filter((x) => x !== item) : [...arr, item];
}

export function RepositoryPRsPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { activeRepo, navigateTo, setActivePr, targetPrNumber, setTargetPrNumber } = useNavigationStore();
  const queryClient = useQueryClient();
  const [selectedPr, setSelectedPr] = useState<PullRequestDto | null>(null);
  const [sheetOpen, setSheetOpen] = useState(false);

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
    queryKey: queryKeys.pullRequests(activeRepo?.organizationId ?? "", activeRepo?.name ?? ""),
    queryFn: () =>
      invoke<PullRequestDto[]>("list_repo_pull_requests", {
        organizationId: activeRepo!.organizationId,
        repoName: activeRepo!.name,
      }),
    enabled: !!activeRepo,
    staleTime: cache.staleTime.live,
  });

  useEffect(() => {
    if (!targetPrNumber || prs.length === 0) return;
    const match = prs.find((pr) => pr.number === targetPrNumber);
    if (match) {
      setSelectedPr(match);
      setSheetOpen(true);
      setTargetPrNumber(null);
    }
  }, [targetPrNumber, prs, setTargetPrNumber]);

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
    setSelectedPr(pr);
    setSheetOpen(true);
  };

  const handleReview = (pr: PullRequestDto) => {
    setActivePr(pr);
    navigateTo("pr-review");
  };

  const handleMerged = () => {
    queryClient.invalidateQueries({
      queryKey: queryKeys.pullRequests(activeRepo?.organizationId ?? "", activeRepo?.name ?? ""),
    });
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

              <FilterPopover>
                <FilterPopoverTrigger asChild>
                  <Button variant="outline" size="icon" className="relative">
                    <Filter className="h-4 w-4" />
                    {activeFilterCount > 0 && (
                      <span className="absolute -top-1.5 -right-1.5 h-4 w-4 rounded-full bg-purple-500 text-[10px] font-bold text-white flex items-center justify-center">
                        {activeFilterCount}
                      </span>
                    )}
                  </Button>
                </FilterPopoverTrigger>
                <FilterPopoverContent>
                  <FilterPopoverHeader
                    title={t("prs.filter")}
                    clearLabel={t("prs.filter.clear")}
                    canClear={activeFilterCount > 0}
                    onClear={() => clearFilters(FILTER_NAMESPACE)}
                  />
                  <FilterSectionDivider />

                  {/* State */}
                  <FilterToggleSection
                    label={t("prs.filter.state")}
                    options={(["open", "merged"] as const).map((s) => ({
                      key: s,
                      label: t(`prs.filter.${s}`),
                      checked: filters.state.includes(s),
                      onCheckedChange: () =>
                        setFilter(FILTER_NAMESPACE, "state", toggleItem(filters.state, s)),
                    }))}
                  />

                  {/* Drafts */}
                  <FilterSectionDivider />
                  <FilterBooleanSection
                    label={t("prs.filter.isDraft")}
                    checked={showDraftsOnly}
                    onCheckedChange={(checked) =>
                      setFilter(FILTER_NAMESPACE, "isDraft", checked ? ["true"] : [])
                    }
                  />

                  {/* Author */}
                  {allAuthors.length > 0 && (
                    <>
                      <FilterSectionDivider />
                      <MultiSelectFilterSection
                        label={t("prs.filter.author")}
                        placeholder={t("prs.filter.authorSearch")}
                        items={allAuthors}
                        value={filters.author}
                        onValueChange={(value) => setFilter(FILTER_NAMESPACE, "author", value)}
                      />
                    </>
                  )}

                  {/* Labels */}
                  {allLabels.length > 0 && (
                    <>
                      <FilterSectionDivider />
                      <MultiSelectFilterSection
                        label={t("prs.filter.labels")}
                        placeholder={t("prs.filter.labelSearch")}
                        items={allLabels}
                        value={filters.labels}
                        onValueChange={(value) => setFilter(FILTER_NAMESPACE, "labels", value)}
                      />
                    </>
                  )}

                  {/* CI Status */}
                  {allCiStatuses.length > 0 && (
                    <>
                      <FilterSectionDivider />
                      <MultiSelectFilterSection
                        label={t("prs.filter.ciStatus")}
                        placeholder={t("prs.filter.ciStatusSearch")}
                        items={allCiStatuses}
                        value={filters.ciStatus}
                        onValueChange={(value) => setFilter(FILTER_NAMESPACE, "ciStatus", value)}
                      />
                    </>
                  )}

                  {/* Reviewers */}
                  {allReviewers.length > 0 && (
                    <>
                      <FilterSectionDivider />
                      <MultiSelectFilterSection
                        label={t("prs.filter.reviewers")}
                        placeholder={t("prs.filter.reviewerSearch")}
                        items={allReviewers}
                        value={filters.reviewers}
                        onValueChange={(value) => setFilter(FILTER_NAMESPACE, "reviewers", value)}
                      />
                    </>
                  )}
                </FilterPopoverContent>
              </FilterPopover>
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

      <PrDetailSheet
        pr={selectedPr}
        open={sheetOpen}
        organizationId={activeRepo.organizationId}
        repoName={activeRepo.name}
        onOpenChange={setSheetOpen}
        onOpenUrl={handleOpenUrl}
        onMerged={handleMerged}
      />
    </PageLayout>
  );
}
