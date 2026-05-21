import { useMemo, useState } from "react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { useFiltersStore } from "@/stores/filters-store";
import { LabelBadge } from "@/components/issues/label-badge";
import { PR_FILTER_NS } from "@/hooks/usePrCards";
import type { PullRequestDto } from "@/types/organization";

type TabId = "state" | "author" | "labels" | "ci" | "reviewers";

const TABS: Array<{ id: TabId; labelKey: string; filterKey: string }> = [
  { id: "state", labelKey: "prs.filter.state", filterKey: "state" },
  { id: "author", labelKey: "prs.filter.author", filterKey: "author" },
  { id: "labels", labelKey: "prs.filter.labels", filterKey: "labels" },
  { id: "ci", labelKey: "prs.filter.ciStatus", filterKey: "ciStatus" },
  { id: "reviewers", labelKey: "prs.filter.reviewers", filterKey: "reviewers" },
];

function tally(map: Map<string, number>, key: string) {
  map.set(key, (map.get(key) ?? 0) + 1);
}

function valueLabel(t: (key: string) => string, tab: TabId, value: string): string {
  if (tab === "state") return value === "merged" ? t("prs.filter.merged") : t("prs.filter.open");
  return value;
}

function dotColor(tab: TabId, value: string): string {
  if (tab === "state") return value === "merged" ? "bg-emerald-500" : "bg-zinc-400 dark:bg-zinc-600";
  if (tab === "ci") {
    if (value === "success") return "bg-emerald-500";
    if (value === "failure") return "bg-red-500";
    return "bg-amber-500";
  }
  return "bg-zinc-400 dark:bg-zinc-600";
}

export function PrInsightsPanel({ prs, className }: { prs: PullRequestDto[]; className?: string }) {
  const { t } = useI18n();
  const [tab, setTab] = useState<TabId>("state");
  const setFilter = useFiltersStore((s) => s.setFilter);
  const clearFilters = useFiltersStore((s) => s.clearFilters);
  const active = useFiltersStore((s) => s.filters[PR_FILTER_NS]);

  const counts = useMemo(() => {
    const state = new Map<string, number>();
    const author = new Map<string, number>();
    const labels = new Map<string, number>();
    const ci = new Map<string, number>();
    const reviewers = new Map<string, number>();
    prs.forEach((pr) => {
      tally(state, pr.merged_at ? "merged" : pr.state);
      if (pr.author) tally(author, pr.author);
      if (pr.ci_status) tally(ci, pr.ci_status);
      pr.labels.forEach((l) => tally(labels, l));
      pr.reviewers.forEach((r) => tally(reviewers, r));
    });
    return { state, author, labels, ci, reviewers };
  }, [prs]);

  const current = TABS.find((tabItem) => tabItem.id === tab)!;
  const selected = active?.[current.filterKey] ?? [];
  const activeCount = active ? Object.values(active).reduce((sum, v) => sum + v.length, 0) : 0;
  const rows = Array.from(counts[tab].entries()).sort((a, b) => b[1] - a[1]);

  const toggleValue = (value: string) => {
    const next = selected.includes(value) ? selected.filter((v) => v !== value) : [...selected, value];
    setFilter(PR_FILTER_NS, current.filterKey, next);
  };

  return (
    <aside className={cn("flex flex-col border-l border-zinc-200 dark:border-zinc-800", className)}>
      <div className="flex items-center justify-between px-3 pt-3">
        <span className="text-[12px] font-semibold uppercase tracking-wider text-zinc-500">{t("prs.filter.title")}</span>
        {activeCount > 0 && (
          <button
            onClick={() => clearFilters(PR_FILTER_NS)}
            className="text-[11px] text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"
          >
            {t("prs.filter.clear")}
          </button>
        )}
      </div>

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
          <p className="px-2.5 py-6 text-center text-[12px] text-zinc-500">{t("prs.filter.noData")}</p>
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
                {tab === "labels" ? (
                  <span className="min-w-0 flex-1 truncate">
                    <LabelBadge name={value} />
                  </span>
                ) : (
                  <>
                    {tab === "author" || tab === "reviewers" ? (
                      <span className="flex h-5 w-5 items-center justify-center rounded-full bg-zinc-200 text-[9px] font-semibold text-zinc-600 dark:bg-zinc-700 dark:text-zinc-300">
                        {value.slice(0, 2).toUpperCase()}
                      </span>
                    ) : (
                      <span className={cn("h-2 w-2 shrink-0 rounded-sm", dotColor(tab, value))} />
                    )}
                    <span
                      className={cn(
                        "min-w-0 flex-1 truncate text-[13px] text-zinc-700 dark:text-zinc-300",
                        isActive && "text-zinc-900 dark:text-zinc-100",
                      )}
                    >
                      {valueLabel(t, tab, value)}
                    </span>
                  </>
                )}
                <span className="text-[12px] tabular-nums text-zinc-500">{count}</span>
              </button>
            );
          })
        )}
      </div>
    </aside>
  );
}
