import { Filter } from "lucide-react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { useFiltersStore } from "@/stores/filters-store";
import { usePrViewStore } from "@/stores/pr-view-store";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { PR_FILTER_NS } from "@/hooks/usePrCards";

export function PrToolbar({ filterNamespace = PR_FILTER_NS }: { filterNamespace?: string }) {
  const { t } = useI18n();
  const storeFilters = useFiltersStore((s) => s.filters[filterNamespace]);
  const insightsOpen = usePrViewStore((s) => s.insightsOpen);
  const toggleInsights = usePrViewStore((s) => s.toggleInsights);

  const activeFilterCount = storeFilters
    ? Object.values(storeFilters).reduce((sum, values) => sum + values.length, 0)
    : 0;

  return (
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
      <TooltipContent>{t("prs.table.filter")}</TooltipContent>
    </Tooltip>
  );
}
