import { useMemo } from "react";
import { Filter, GitPullRequest, RefreshCw, X } from "lucide-react";
import { openUrl } from "@tauri-apps/plugin-opener";

import { Card, CardContent } from "../ui/card";
import { Button } from "../ui/button";
import { Switch } from "../ui/switch";
import { Tooltip, TooltipContent, TooltipTrigger } from "../ui/tooltip";
import { Popover, PopoverContent, PopoverTrigger } from "../ui/popover";
import {
  Combobox,
  ComboboxInput,
  ComboboxContent,
  ComboboxEmpty,
  ComboboxItem,
  ComboboxList,
} from "../ui/combobox";
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
  isSyncing?: boolean;
  onSync?: () => void;
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
  isSyncing,
  onSync,
  onMerged,
}: PrListCardProps) {
  const { t } = useI18n();
  const { navigateTo, setActivePr } = useNavigationStore();
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
              <Tooltip>
                <TooltipTrigger asChild>
                  <Button variant="outline" size="icon" onClick={onSync} disabled={isSyncing}>
                    <RefreshCw className={cn("h-4 w-4", isSyncing && "animate-spin")} />
                  </Button>
                </TooltipTrigger>
                <TooltipContent>{t("pages.repositoryDetail.syncPrs")}</TooltipContent>
              </Tooltip>
            )}

            <Popover>
              <PopoverTrigger asChild>
                <Button variant="outline" size="icon" className="relative">
                  <Filter className="h-4 w-4" />
                  {activeFilterCount > 0 && (
                    <span className="absolute -top-1.5 -right-1.5 h-4 w-4 rounded-full bg-purple-500 text-[10px] font-bold text-white flex items-center justify-center">
                      {activeFilterCount}
                    </span>
                  )}
                </Button>
              </PopoverTrigger>
              <PopoverContent align="end" className="w-64 p-0 bg-card text-card-foreground">
                <div className="flex items-center justify-between px-3 py-2">
                  <span className="text-sm font-semibold">{t("prs.filter")}</span>
                  {activeFilterCount > 0 && (
                    <button
                      type="button"
                      onClick={() => clearFilters(filterNamespace)}
                      className="text-xs text-zinc-400 hover:text-zinc-200"
                    >
                      {t("prs.filter.clear")}
                    </button>
                  )}
                </div>
                <div className="border-t border-border" />

                {/* State */}
                <div className="px-3 py-2 space-y-2">
                  <p className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
                    {t("prs.filter.state")}
                  </p>
                  {(["open", "merged"] as const).map((s) => (
                    <div key={s} className="flex items-center justify-between">
                      <span className="text-sm capitalize">{t(`prs.filter.${s}`)}</span>
                      <Switch
                        checked={filters.state.includes(s)}
                        onCheckedChange={() =>
                          setFilter(filterNamespace, "state", toggleItem(filters.state, s))
                        }
                      />
                    </div>
                  ))}
                </div>

                {/* Drafts */}
                <div className="border-t border-border" />
                <div className="px-3 py-2 space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-sm">{t("prs.filter.isDraft")}</span>
                    <Switch
                      checked={showDraftsOnly}
                      onCheckedChange={(checked) =>
                        setFilter(filterNamespace, "isDraft", checked ? ["true"] : [])
                      }
                    />
                  </div>
                </div>

                {/* Author */}
                {allAuthors.length > 0 && (
                  <>
                    <div className="border-t border-border" />
                    <div className="px-3 py-2 space-y-1.5">
                      <p className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
                        {t("prs.filter.author")}
                      </p>
                      <Combobox items={allAuthors} multiple value={filters.author} onValueChange={(v) => setFilter(filterNamespace, "author", v as string[])}>
                        <ComboboxInput placeholder={t("prs.filter.authorSearch")} className="w-full text-xs" showTrigger={false} />
                        <ComboboxContent className="bg-card text-card-foreground">
                          <ComboboxEmpty>No results.</ComboboxEmpty>
                          <ComboboxList>
                            {(item: string) => <ComboboxItem key={item} value={item}>{item}</ComboboxItem>}
                          </ComboboxList>
                        </ComboboxContent>
                      </Combobox>
                      {filters.author.length > 0 && (
                        <div className="flex flex-wrap gap-1 pt-1">
                          {filters.author.map((item) => (
                            <button key={item} type="button" onClick={() => setFilter(filterNamespace, "author", toggleItem(filters.author, item))} className="inline-flex items-center gap-1 rounded-[6px] bg-muted px-2 py-1 text-[11px] text-muted-foreground transition-colors hover:bg-accent hover:text-foreground">
                              <span>{item}</span>
                              <X className="h-3 w-3" />
                            </button>
                          ))}
                        </div>
                      )}
                    </div>
                  </>
                )}

                {/* Labels */}
                {allLabels.length > 0 && (
                  <>
                    <div className="border-t border-border" />
                    <div className="px-3 py-2 space-y-1.5">
                      <p className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
                        {t("prs.filter.labels")}
                      </p>
                      <Combobox items={allLabels} multiple value={filters.labels} onValueChange={(v) => setFilter(filterNamespace, "labels", v as string[])}>
                        <ComboboxInput placeholder={t("prs.filter.labelSearch")} className="w-full text-xs" showTrigger={false} />
                        <ComboboxContent className="bg-card text-card-foreground">
                          <ComboboxEmpty>No results.</ComboboxEmpty>
                          <ComboboxList>
                            {(item: string) => <ComboboxItem key={item} value={item}>{item}</ComboboxItem>}
                          </ComboboxList>
                        </ComboboxContent>
                      </Combobox>
                      {filters.labels.length > 0 && (
                        <div className="flex flex-wrap gap-1 pt-1">
                          {filters.labels.map((item) => (
                            <button key={item} type="button" onClick={() => setFilter(filterNamespace, "labels", toggleItem(filters.labels, item))} className="inline-flex items-center gap-1 rounded-[6px] bg-muted px-2 py-1 text-[11px] text-muted-foreground transition-colors hover:bg-accent hover:text-foreground">
                              <span>{item}</span>
                              <X className="h-3 w-3" />
                            </button>
                          ))}
                        </div>
                      )}
                    </div>
                  </>
                )}

                {/* CI Status */}
                {allCiStatuses.length > 0 && (
                  <>
                    <div className="border-t border-border" />
                    <div className="px-3 py-2 space-y-1.5">
                      <p className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
                        {t("prs.filter.ciStatus")}
                      </p>
                      <Combobox items={allCiStatuses} multiple value={filters.ciStatus} onValueChange={(v) => setFilter(filterNamespace, "ciStatus", v as string[])}>
                        <ComboboxInput placeholder={t("prs.filter.ciStatusSearch")} className="w-full text-xs" showTrigger={false} />
                        <ComboboxContent className="bg-card text-card-foreground">
                          <ComboboxEmpty>No results.</ComboboxEmpty>
                          <ComboboxList>
                            {(item: string) => <ComboboxItem key={item} value={item}>{item}</ComboboxItem>}
                          </ComboboxList>
                        </ComboboxContent>
                      </Combobox>
                      {filters.ciStatus.length > 0 && (
                        <div className="flex flex-wrap gap-1 pt-1">
                          {filters.ciStatus.map((item) => (
                            <button key={item} type="button" onClick={() => setFilter(filterNamespace, "ciStatus", toggleItem(filters.ciStatus, item))} className="inline-flex items-center gap-1 rounded-[6px] bg-muted px-2 py-1 text-[11px] text-muted-foreground transition-colors hover:bg-accent hover:text-foreground">
                              <span>{item}</span>
                              <X className="h-3 w-3" />
                            </button>
                          ))}
                        </div>
                      )}
                    </div>
                  </>
                )}

                {/* Reviewers */}
                {allReviewers.length > 0 && (
                  <>
                    <div className="border-t border-border" />
                    <div className="px-3 py-2 space-y-1.5">
                      <p className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
                        {t("prs.filter.reviewers")}
                      </p>
                      <Combobox items={allReviewers} multiple value={filters.reviewers} onValueChange={(v) => setFilter(filterNamespace, "reviewers", v as string[])}>
                        <ComboboxInput placeholder={t("prs.filter.reviewerSearch")} className="w-full text-xs" showTrigger={false} />
                        <ComboboxContent className="bg-card text-card-foreground">
                          <ComboboxEmpty>No results.</ComboboxEmpty>
                          <ComboboxList>
                            {(item: string) => <ComboboxItem key={item} value={item}>{item}</ComboboxItem>}
                          </ComboboxList>
                        </ComboboxContent>
                      </Combobox>
                      {filters.reviewers.length > 0 && (
                        <div className="flex flex-wrap gap-1 pt-1">
                          {filters.reviewers.map((item) => (
                            <button key={item} type="button" onClick={() => setFilter(filterNamespace, "reviewers", toggleItem(filters.reviewers, item))} className="inline-flex items-center gap-1 rounded-[6px] bg-muted px-2 py-1 text-[11px] text-muted-foreground transition-colors hover:bg-accent hover:text-foreground">
                              <span>{item}</span>
                              <X className="h-3 w-3" />
                            </button>
                          ))}
                        </div>
                      )}
                    </div>
                  </>
                )}
              </PopoverContent>
            </Popover>
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
        onOpenChange={setSheetOpen}
        onOpenUrl={handleOpenUrl}
        onMerged={onMerged ?? (() => {})} 
      />
    </>
  );
}
