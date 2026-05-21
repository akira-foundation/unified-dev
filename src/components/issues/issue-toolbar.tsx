import { Filter, RefreshCw } from "lucide-react";

import { cn } from "@/lib/utils";
import { useFiltersStore } from "../../stores/filters-store";
import { useIssueViewStore } from "../../stores/issue-view-store";
import { useI18n } from "../../i18n/i18n";
import { Button } from "../ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "../ui/tooltip";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "../ui/dropdown-menu";

interface IssueToolbarProps {
  filterNamespace: string;
  onSync?: () => void;
  syncOptions?: Array<{ label: string; onSelect: () => void }>;
  isSyncing?: boolean;
  disableSync?: boolean;
}

export function IssueToolbar({
  filterNamespace,
  onSync,
  syncOptions,
  isSyncing,
  disableSync,
}: IssueToolbarProps) {
  const { t } = useI18n();
  const storeFilters = useFiltersStore((s) => s.filters[filterNamespace]);
  const insightsOpen = useIssueViewStore((s) => s.insightsOpen);
  const toggleInsights = useIssueViewStore((s) => s.toggleInsights);

  const activeFilterCount = storeFilters
    ? Object.values(storeFilters).reduce((sum, values) => sum + values.length, 0)
    : 0;

  return (
    <>
      {onSync &&
        (syncOptions && syncOptions.length > 0 ? (
          <DropdownMenu>
            <Tooltip>
              <TooltipTrigger asChild>
                <DropdownMenuTrigger asChild>
                  <Button variant="outline" size="icon-sm" disabled={isSyncing || disableSync}>
                    <RefreshCw className={`h-4 w-4 ${isSyncing ? "animate-spin" : ""}`} />
                  </Button>
                </DropdownMenuTrigger>
              </TooltipTrigger>
              <TooltipContent>{t("issues.table.syncIssues")}</TooltipContent>
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
              <Button variant="outline" size="icon-sm" onClick={onSync} disabled={isSyncing || disableSync}>
                <RefreshCw className={`h-4 w-4 ${isSyncing ? "animate-spin" : ""}`} />
              </Button>
            </TooltipTrigger>
            <TooltipContent>{t("issues.table.syncIssues")}</TooltipContent>
          </Tooltip>
        ))}

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
        <TooltipContent>{t("issues.table.filter")}</TooltipContent>
      </Tooltip>
    </>
  );
}
