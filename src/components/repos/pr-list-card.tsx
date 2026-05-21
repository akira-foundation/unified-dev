import { useMemo, useState } from "react";
import { Filter, RefreshCw } from "lucide-react";
import { openUrl } from "@tauri-apps/plugin-opener";

import { Button } from "../ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "../ui/dropdown-menu";
import { Tooltip, TooltipContent, TooltipTrigger } from "../ui/tooltip";
import { AppbarActions } from "../layout/appbar-actions";
import { PrItem } from "./pr-item";
import { PrDetailSheet } from "./pr-detail-sheet";
import { useI18n } from "../../i18n/i18n";
import { useFiltersStore } from "../../stores/filters-store";
import { useNavigationStore } from "../../stores/navigation-store";
import { usePrViewStore } from "../../stores/pr-view-store";
import { cn } from "../../lib/utils";
import type { PullRequestDto } from "../../types/organization";

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
  onNewTask?: (pr: PullRequestDto) => void;
  actionsInAppbar?: boolean;
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
  onNewTask,
  actionsInAppbar,
}: PrListCardProps) {
  const { t } = useI18n();
  const { navigateTo, setActivePr, setActiveRepo } = useNavigationStore();
  const insightsOpen = usePrViewStore((s) => s.insightsOpen);
  const toggleInsights = usePrViewStore((s) => s.toggleInsights);
  const [selectedPr, setSelectedPr] = useState<PullRequestDto | null>(null);
  const [sheetOpen, setSheetOpen] = useState(false);

  const storeFilters = useFiltersStore((s) => s.filters[filterNamespace]);
  const activeFilterCount = storeFilters
    ? Object.values(storeFilters).reduce((sum, values) => sum + values.length, 0)
    : 0;

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

  const showDraftsOnly = filters.isDraft.includes("true");

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

  const toolbar = (
    <>
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

            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="outline"
                  size="icon"
                  onClick={toggleInsights}
                  className={cn("relative", insightsOpen && "bg-zinc-100 text-zinc-900 dark:bg-zinc-800 dark:text-zinc-100")}
                >
                  <Filter className="h-4 w-4" />
                  {activeFilterCount > 0 && (
                    <span className="absolute -top-1.5 -right-1.5 h-4 w-4 rounded-full bg-purple-500 text-[10px] font-bold text-white flex items-center justify-center">
                      {activeFilterCount}
                    </span>
                  )}
                </Button>
              </TooltipTrigger>
              <TooltipContent>{t("prs.filter")}</TooltipContent>
            </Tooltip>
    </>
  );

  return (
    <>
      {actionsInAppbar && <AppbarActions>{toolbar}</AppbarActions>}
      <div className="flex flex-col">
        {!actionsInAppbar && <div className="flex items-center justify-end gap-2 px-1 pb-2">{toolbar}</div>}
        {filteredPrs.map((pr) => (
          <PrItem
            key={pr.id}
            pr={pr}
            onOpen={handleOpenUrl}
            onViewDetail={handleViewDetail}
            onReview={handleReview}
            onNewTask={onNewTask}
          />
        ))}
      </div>

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
