import { Filter, RefreshCw } from "lucide-react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { useFiltersStore } from "@/stores/filters-store";
import { useRepoViewStore } from "@/stores/repo-view-store";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";

export const REPO_FILTER_NS = "repos";

export function RepoToolbar({ onSync, isSyncing }: { onSync?: () => void; isSyncing?: boolean }) {
  const { t } = useI18n();
  const storeFilters = useFiltersStore((s) => s.filters[REPO_FILTER_NS]);
  const insightsOpen = useRepoViewStore((s) => s.insightsOpen);
  const toggleInsights = useRepoViewStore((s) => s.toggleInsights);

  const activeFilterCount = storeFilters
    ? Object.values(storeFilters).reduce((sum, values) => sum + values.length, 0)
    : 0;

  return (
    <>
      {onSync && (
        <Tooltip>
          <TooltipTrigger asChild>
            <Button variant="outline" size="icon-sm" onClick={onSync} disabled={isSyncing}>
              <RefreshCw className={cn("h-4 w-4", isSyncing && "animate-spin")} />
            </Button>
          </TooltipTrigger>
          <TooltipContent>{t("common.syncAll")}</TooltipContent>
        </Tooltip>
      )}
      <Tooltip>
        <TooltipTrigger asChild>
          <Button
            variant="outline"
            size="icon-sm"
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
        <TooltipContent>{t("repos.table.filter")}</TooltipContent>
      </Tooltip>
    </>
  );
}
