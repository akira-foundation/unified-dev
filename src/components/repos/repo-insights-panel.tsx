import { useMemo, useState } from "react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { useFiltersStore } from "@/stores/filters-store";
import { REPO_FILTER_NS } from "@/components/repos/repo-toolbar";
import type { OrganizationRepoWithOrg } from "@/types/organization";

type TabId = "visibility" | "organization" | "branch";

const TABS: Array<{ id: TabId; labelKey: string; filterKey: string }> = [
  { id: "visibility", labelKey: "repos.table.filter.visibility", filterKey: "visibility" },
  { id: "organization", labelKey: "repos.table.filter.organization", filterKey: "organizations" },
  { id: "branch", labelKey: "repos.table.filter.defaultBranch", filterKey: "defaultBranch" },
];

function tally(map: Map<string, number>, key: string) {
  map.set(key, (map.get(key) ?? 0) + 1);
}

export function RepoInsightsPanel({
  repos,
  className,
  filterNamespace = REPO_FILTER_NS,
}: {
  repos: OrganizationRepoWithOrg[];
  className?: string;
  filterNamespace?: string;
}) {
  const { t } = useI18n();
  const [tab, setTab] = useState<TabId>("visibility");
  const setFilter = useFiltersStore((s) => s.setFilter);
  const clearFilters = useFiltersStore((s) => s.clearFilters);
  const active = useFiltersStore((s) => s.filters[filterNamespace]);

  const counts = useMemo(() => {
    const visibility = new Map<string, number>();
    const organization = new Map<string, number>();
    const branch = new Map<string, number>();
    repos.forEach((r) => {
      tally(visibility, r.visibility);
      tally(organization, r.organization_name);
      if (r.default_branch) tally(branch, r.default_branch);
    });
    return { visibility, organization, branch };
  }, [repos]);

  const current = TABS.find((tabItem) => tabItem.id === tab)!;
  const selected = active?.[current.filterKey] ?? [];
  const activeCount = active ? Object.values(active).reduce((sum, v) => sum + v.length, 0) : 0;
  const hasOpenPrs = (active?.hasOpenPrs ?? []).includes("true");
  const rows = Array.from(counts[tab].entries()).sort((a, b) => b[1] - a[1]);

  const toggleValue = (value: string) => {
    const next = selected.includes(value) ? selected.filter((v) => v !== value) : [...selected, value];
    setFilter(filterNamespace, current.filterKey, next);
  };

  const valueLabel = (value: string) =>
    tab === "visibility" ? t(`repos.table.filter.${value}`) : value;

  const dotColor = (value: string) =>
    tab === "visibility"
      ? value === "private"
        ? "bg-amber-500"
        : "bg-emerald-500"
      : "bg-zinc-400 dark:bg-zinc-600";

  return (
    <aside className={cn("flex flex-col border-l border-zinc-200 dark:border-zinc-800", className)}>
      <div className="flex items-center justify-between px-3 pt-3">
        <span className="text-[12px] font-semibold uppercase tracking-wider text-zinc-500">{t("repos.table.filter")}</span>
        {(activeCount > 0 || hasOpenPrs) && (
          <button
            onClick={() => clearFilters(filterNamespace)}
            className="text-[11px] text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"
          >
            {t("repos.table.filter.clear")}
          </button>
        )}
      </div>

      <label className="mx-3 mt-3 flex cursor-pointer items-center gap-2 rounded-md px-2.5 py-2 text-[13px] text-zinc-700 transition-colors hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-white/[0.04]">
        <input
          type="checkbox"
          checked={hasOpenPrs}
          onChange={(e) => setFilter(filterNamespace, "hasOpenPrs", e.target.checked ? ["true"] : [])}
          className="accent-purple-600"
        />
        {t("repos.table.filter.hasOpenPrs")}
      </label>

      <div className="flex flex-wrap gap-1.5 p-3">
        {TABS.map((tabItem) => (
          <button
            key={tabItem.id}
            onClick={() => setTab(tabItem.id)}
            className={cn(
              "rounded-full border px-2.5 py-1 text-[12px] font-medium transition-colors",
              tab === tabItem.id
                ? "border-zinc-300 bg-zinc-100 text-zinc-900 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100"
                : "border-transparent text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300",
            )}
          >
            {t(tabItem.labelKey)}
          </button>
        ))}
      </div>

      <div className="flex flex-col overflow-y-auto custom-scrollbar px-2 pb-3">
        {rows.length === 0 ? (
          <p className="px-2.5 py-6 text-center text-[12px] text-zinc-500">{t("issues.filter.noData")}</p>
        ) : (
          rows.map(([value, count]) => {
            const isActive = selected.includes(value);
            return (
              <button
                key={value}
                onClick={() => toggleValue(value)}
                className={cn(
                  "flex items-center gap-2.5 rounded-md px-2.5 py-2 text-left transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.04]",
                  isActive && "bg-zinc-100 dark:bg-white/[0.06]",
                )}
              >
                <span className={cn("h-2 w-2 shrink-0 rounded-sm", dotColor(value))} />
                <span
                  className={cn(
                    "min-w-0 flex-1 truncate text-[13px] text-zinc-700 dark:text-zinc-300",
                    isActive && "text-zinc-900 dark:text-zinc-100",
                  )}
                >
                  {valueLabel(value)}
                </span>
                <span className="text-[12px] tabular-nums text-zinc-500">{count}</span>
              </button>
            );
          })
        )}
      </div>
    </aside>
  );
}
