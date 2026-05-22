import { Filter } from "lucide-react";

import { Button } from "../ui/button";
import { FilterPopover, FilterPopoverContent, FilterPopoverTrigger } from "../filters/filter-popover";
import { MultiSelectFilterSection } from "../filters/multi-select-filter-section";
import {
  FilterBooleanSection,
  FilterPopoverHeader,
  FilterSectionDivider,
  FilterToggleSection,
} from "../filters/filter-popover-section";
import { useI18n } from "../../i18n/i18n";

function toggleItem(arr: string[], item: string): string[] {
  return arr.includes(item) ? arr.filter((x) => x !== item) : [...arr, item];
}

interface RepoPrsFilterPopoverProps {
  namespace: string;
  filters: { state: string[]; author: string[]; labels: string[]; ciStatus: string[]; reviewers: string[] };
  activeFilterCount: number;
  showDraftsOnly: boolean;
  authors: string[];
  labels: string[];
  ciStatuses: string[];
  reviewers: string[];
  setFilter: (namespace: string, key: string, values: string[]) => void;
  clearFilters: (namespace: string) => void;
}

export function RepoPrsFilterPopover({
  namespace,
  filters,
  activeFilterCount,
  showDraftsOnly,
  authors,
  labels,
  ciStatuses,
  reviewers,
  setFilter,
  clearFilters,
}: RepoPrsFilterPopoverProps) {
  const { t } = useI18n();

  return (
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
          onClear={() => clearFilters(namespace)}
        />
        <FilterSectionDivider />
        <FilterToggleSection
          label={t("prs.filter.state")}
          options={(["open", "merged"] as const).map((s) => ({
            key: s,
            label: t(`prs.filter.${s}`),
            checked: filters.state.includes(s),
            onCheckedChange: () => setFilter(namespace, "state", toggleItem(filters.state, s)),
          }))}
        />
        <FilterSectionDivider />
        <FilterBooleanSection
          label={t("prs.filter.isDraft")}
          checked={showDraftsOnly}
          onCheckedChange={(checked) => setFilter(namespace, "isDraft", checked ? ["true"] : [])}
        />
        {authors.length > 0 && (
          <>
            <FilterSectionDivider />
            <MultiSelectFilterSection
              label={t("prs.filter.author")}
              placeholder={t("prs.filter.authorSearch")}
              items={authors}
              value={filters.author}
              onValueChange={(value) => setFilter(namespace, "author", value)}
            />
          </>
        )}
        {labels.length > 0 && (
          <>
            <FilterSectionDivider />
            <MultiSelectFilterSection
              label={t("prs.filter.labels")}
              placeholder={t("prs.filter.labelSearch")}
              items={labels}
              value={filters.labels}
              onValueChange={(value) => setFilter(namespace, "labels", value)}
            />
          </>
        )}
        {ciStatuses.length > 0 && (
          <>
            <FilterSectionDivider />
            <MultiSelectFilterSection
              label={t("prs.filter.ciStatus")}
              placeholder={t("prs.filter.ciStatusSearch")}
              items={ciStatuses}
              value={filters.ciStatus}
              onValueChange={(value) => setFilter(namespace, "ciStatus", value)}
            />
          </>
        )}
        {reviewers.length > 0 && (
          <>
            <FilterSectionDivider />
            <MultiSelectFilterSection
              label={t("prs.filter.reviewers")}
              placeholder={t("prs.filter.reviewerSearch")}
              items={reviewers}
              value={filters.reviewers}
              onValueChange={(value) => setFilter(namespace, "reviewers", value)}
            />
          </>
        )}
      </FilterPopoverContent>
    </FilterPopover>
  );
}
