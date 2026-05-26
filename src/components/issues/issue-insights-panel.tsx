import { useMemo, useState } from "react";
import { UserCircle2 } from "lucide-react";

import { cn } from "@/lib/utils";
import { useFiltersStore } from "../../stores/filters-store";
import { useI18n } from "@/i18n/i18n";
import { LabelBadge } from "./label-badge";
import type { IssueDto } from "../../types/issue";

interface IssueInsightsPanelProps {
  issues: IssueDto[];
  filterNamespace?: string;
  className?: string;
}

type TabId = "status" | "assignees" | "labels" | "projects" | "repos" | "provider" | "source";

const TABS: Array<{ id: TabId; labelKey: string; filterKey: string }> = [
  { id: "status", labelKey: "issues.detail.labelStatus", filterKey: "statuses" },
  { id: "assignees", labelKey: "issues.detail.labelAssignees", filterKey: "assignees" },
  { id: "labels", labelKey: "issues.detail.labelLabels", filterKey: "labels" },
  { id: "projects", labelKey: "issues.filter.projects", filterKey: "projects" },
  { id: "repos", labelKey: "issues.filter.repos", filterKey: "repos" },
  { id: "provider", labelKey: "issues.filter.provider", filterKey: "providers" },
  { id: "source", labelKey: "issues.detail.source", filterKey: "sources" },
];

function tally(map: Map<string, number>, key: string) {
  map.set(key, (map.get(key) ?? 0) + 1);
}

function valueLabel(t: (key: string) => string, tab: TabId, value: string): string {
  if (tab === "status") return value === "open" ? t("issues.table.filter.open") : t("issues.table.filter.closed");
  if (tab === "source") return value === "synced" ? t("issues.detail.synced") : t("issues.detail.local");
  if (tab === "provider") return value.charAt(0).toUpperCase() + value.slice(1);
  return value;
}

function dotColor(tab: TabId, value: string): string {
  const positive = (tab === "status" && value === "open") || (tab === "source" && value === "synced");
  return positive ? "bg-emerald-500" : "bg-zinc-400 dark:bg-zinc-600";
}

export function IssueInsightsPanel({ issues, filterNamespace = "issues", className }: IssueInsightsPanelProps) {
  const { t } = useI18n();
  const [tab, setTab] = useState<TabId>("status");
  const setFilter = useFiltersStore((s) => s.setFilter);
  const clearFilters = useFiltersStore((s) => s.clearFilters);
  const active = useFiltersStore((s) => s.filters[filterNamespace]);

  const counts = useMemo(() => {
    const status = new Map<string, number>();
    const assignees = new Map<string, number>();
    const labels = new Map<string, number>();
    const projects = new Map<string, number>();
    const repos = new Map<string, number>();
    const provider = new Map<string, number>();
    const source = new Map<string, number>();
    let noAssignee = 0;
    issues.forEach((issue) => {
      tally(status, issue.status);
      tally(source, issue.syncWithProvider ? "synced" : "local");
      tally(projects, issue.projectName ?? "No project");
      tally(repos, issue.repoName);
      tally(provider, issue.provider);
      if (issue.assignees.length === 0) noAssignee += 1;
      else issue.assignees.forEach((a) => tally(assignees, a));
      issue.labels.forEach((l) => tally(labels, l));
    });
    return { status, assignees, labels, projects, repos, provider, source, noAssignee };
  }, [issues]);

  const current = TABS.find((tabItem) => tabItem.id === tab)!;
  const selected = active?.[current.filterKey] ?? [];
  const activeCount = active ? Object.values(active).reduce((sum, v) => sum + v.length, 0) : 0;
  const rows = Array.from(counts[tab].entries()).sort((a, b) => {
    const aSel = selected.includes(a[0]) ? 1 : 0;
    const bSel = selected.includes(b[0]) ? 1 : 0;
    if (aSel !== bSel) return bSel - aSel;
    return b[1] - a[1];
  });

  const toggleValue = (value: string) => {
    const next = selected.includes(value) ? selected.filter((v) => v !== value) : [...selected, value];
    setFilter(filterNamespace, current.filterKey, next);
  };

  return (
    <aside className={cn("flex flex-col border-l border-zinc-200 dark:border-zinc-800", className)}>
      <div className="flex items-center justify-between px-3 pt-3">
        <span className="text-[12px] font-semibold uppercase tracking-wider text-zinc-500">{t("issues.filter.title")}</span>
        {activeCount > 0 && (
          <button
            onClick={() => clearFilters(filterNamespace)}
            className="text-[11px] text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"
          >
            {t("issues.filter.clear")}
          </button>
        )}
      </div>

      <div className="flex flex-wrap gap-1.5 p-3">
        {TABS.map((tabItem) => {
          const activeFilters = active?.[tabItem.filterKey]?.length ?? 0;
          return (
            <button
              key={tabItem.id}
              onClick={() => setTab(tabItem.id)}
              className={cn(
                "flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[12px] font-medium transition-colors",
                tab === tabItem.id
                  ? "border-zinc-300 bg-zinc-100 text-zinc-900 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100"
                  : "border-transparent text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300",
              )}
            >
              {t(tabItem.labelKey)}
              {activeFilters > 0 && (
                <span className="flex h-4 min-w-4 items-center justify-center rounded-full bg-purple-500 px-1 text-[9px] font-semibold text-white">
                  {activeFilters}
                </span>
              )}
            </button>
          );
        })}
      </div>

      <div className="flex flex-col gap-0.5 overflow-y-auto custom-scrollbar px-2 pb-3">
        {tab === "assignees" && counts.noAssignee > 0 && (
          <div className="flex items-center gap-2.5 rounded-md px-2.5 py-2">
            <UserCircle2 className="h-4 w-4 shrink-0 text-zinc-500" />
            <span className="flex-1 truncate text-[13px] text-zinc-600 dark:text-zinc-400">{t("issues.filter.noAssignee")}</span>
            <span className="text-[12px] tabular-nums text-zinc-500">{counts.noAssignee}</span>
          </div>
        )}

        {rows.length === 0 && counts.noAssignee === 0 ? (
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
                {tab === "labels" ? (
                  <span className="min-w-0 flex-1 truncate">
                    <LabelBadge name={value} />
                  </span>
                ) : (
                  <>
                    {tab === "assignees" ? (
                      <span className="flex h-5 w-5 items-center justify-center rounded-full bg-zinc-200 text-[9px] font-semibold text-zinc-600 dark:bg-zinc-700 dark:text-zinc-300">
                        {value.slice(0, 2).toUpperCase()}
                      </span>
                    ) : (
                      <span
                        className={cn(
                          "h-2 w-2 shrink-0 rounded-sm transition-all",
                          dotColor(tab, value),
                          isActive && "ring-2 ring-zinc-400/50 dark:ring-zinc-500/50",
                        )}
                      />
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
