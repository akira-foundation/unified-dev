import { useMemo } from "react";
import { Filter, GitPullRequest, RefreshCw } from "lucide-react";
import { openUrl } from "@tauri-apps/plugin-opener";

import { Card, CardContent } from "../ui/card";
import { Button } from "../ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "../ui/dropdown-menu";
import {
  FilterPopover,
  FilterPopoverContent,
  FilterPopoverTrigger,
} from "../filters/filter-popover";
import {
  FilterBooleanSection,
  FilterPopoverHeader,
  FilterSectionDivider,
  FilterToggleSection,
} from "../filters/filter-popover-section";
import { Tooltip, TooltipContent, TooltipTrigger } from "../ui/tooltip";
import { MultiSelectFilterSection } from "../filters/multi-select-filter-section";
import { PrItem } from "./pr-item";
import { PrDetailSheet } from "./pr-detail-sheet";
import { useI18n } from "../../i18n/i18n";
import { useFiltersStore } from "../../stores/filters-store";
import { useNavigationStore } from "../../stores/navigation-store";
import { cn } from "../../lib/utils";
import type { PullRequestDto } from "../../types/organization";
import { useState } from "react";

interface PrListCardProps {
  prs: PullRequestDto[];
  filterNamespace: string;
  organizationId: string;
  repoName: string;
  owner: string;
  isSyncing?: boolean;
  onSync?: () => void;
  syncOptions?: Array<{ label: string; onSelect: () => void }>;
  onMerged?: () => void;
}

function toggleItem(arr: string[], item: string): string[] {
  return arr.includes(item) ? arr.filter((x) => x !== item) : [...arr, item];
}

export function PrListCard({
  prs,
  filterNamespace,
  organizationId,
  repoName,
  owner,
  isSyncing,
  onSync,
  syncOptions,
  onMerged,
}: PrListCardProps) {
  const { t } = useI18n();
  const { navigateTo, setActivePr, setActiveRepo } = useNavigationStore();
  const [selectedPr, setSelectedPr] = useState<PullRequestDto | null>(null);
  const [sheetOpen, setSheetOpen] = useState(false);

  const setFilter = useFiltersStore((s) => s.setFilter);
  const clearFilters = useFiltersStore((s) => s.clearFilters);
  const storeFilters = useFiltersStore((s) => s.filters[filterNamespace]);

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
    setActiveRepo({ name: repoName, owner, organizationId });
    setActivePr(pr);
    navigateTo("pr-review");
  };

  return (
    <>
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
                {filteredPrs.length === 1
                  ? t("pages.repositoryPrs.openCount").replace("{count}", String(filteredPrs.length))
                  : t("pages.repositoryPrs.openCountPlural").replace("{count}", String(filteredPrs.length))}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-2">
            {onSync && (
              syncOptions && syncOptions.length > 0 ? (
                <DropdownMenu>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <DropdownMenuTrigger asChild>
                        <Button variant="outline" size="icon" disabled={isSyncing}>
                          <RefreshCw className={cn("h-4 w-4", isSyncing && "animate-spin")} />
                        </Button>
                      </DropdownMenuTrigger>
                    </TooltipTrigger>
                    <TooltipContent>{t("pages.repositoryDetail.syncPrs")}</TooltipContent>
                  </Tooltip>
                  <DropdownMenuContent align="end">
                    {syncOptions.map((option) => (
                      <DropdownMenuItem key={option.label} onSelect={option.onSelect}>
                        {option.label}
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuContent>
                </DropdownMenu>
              ) : (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button variant="outline" size="icon" onClick={onSync} disabled={isSyncing}>
                      <RefreshCw className={cn("h-4 w-4", isSyncing && "animate-spin")} />
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent>{t("pages.repositoryDetail.syncPrs")}</TooltipContent>
                </Tooltip>
              )
            )}

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
                  onClear={() => clearFilters(filterNamespace)}
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
                      setFilter(filterNamespace, "state", toggleItem(filters.state, s)),
                  }))}
                />

                {/* Drafts */}
                <FilterSectionDivider />
                <FilterBooleanSection
                  label={t("prs.filter.isDraft")}
                  checked={showDraftsOnly}
                  onCheckedChange={(checked) =>
                    setFilter(filterNamespace, "isDraft", checked ? ["true"] : [])
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
                        onValueChange={(value) => setFilter(filterNamespace, "author", value)}
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
                        onValueChange={(value) => setFilter(filterNamespace, "labels", value)}
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
                        onValueChange={(value) => setFilter(filterNamespace, "ciStatus", value)}
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
                        onValueChange={(value) => setFilter(filterNamespace, "reviewers", value)}
                      />
                  </>
                )}
              </FilterPopoverContent>
            </FilterPopover>
          </div>
        </div>

        <CardContent className="p-0 border-t border-zinc-100 dark:border-zinc-800/50">
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

      <PrDetailSheet
        pr={selectedPr}
        open={sheetOpen}
        organizationId={organizationId}
        repoName={repoName}
        owner={owner}
        onOpenChange={setSheetOpen}
        onOpenUrl={handleOpenUrl}
        onMerged={onMerged ?? (() => {})} 
      />
    </>
  );
}
