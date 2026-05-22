import { useMemo } from "react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { useFiltersStore } from "@/stores/filters-store";
import { ORG_FILTER_NS } from "@/hooks/useFilteredOrgs";
import type { OrganizationSummary } from "@/types/organization";

export function OrgInsightsPanel({
  orgs,
  providerNameById,
  className,
}: {
  orgs: OrganizationSummary[];
  providerNameById: Record<string, string>;
  className?: string;
}) {
  const { t } = useI18n();
  const setFilter = useFiltersStore((s) => s.setFilter);
  const clearFilters = useFiltersStore((s) => s.clearFilters);
  const active = useFiltersStore((s) => s.filters[ORG_FILTER_NS]);
  const selected = active?.provider ?? [];

  const rows = useMemo(() => {
    const counts = new Map<string, number>();
    orgs.forEach((o) => {
      const name = o.provider_id ? providerNameById[o.provider_id] : undefined;
      if (name) counts.set(name, (counts.get(name) ?? 0) + 1);
    });
    return Array.from(counts.entries()).sort((a, b) => b[1] - a[1]);
  }, [orgs, providerNameById]);

  const toggle = (value: string) => {
    const next = selected.includes(value) ? selected.filter((v) => v !== value) : [...selected, value];
    setFilter(ORG_FILTER_NS, "provider", next);
  };

  return (
    <aside className={cn("flex flex-col border-l border-zinc-200 dark:border-zinc-800", className)}>
      <div className="flex items-center justify-between px-3 pt-3">
        <span className="text-[12px] font-semibold uppercase tracking-wider text-zinc-500">{t("issues.filter.title")}</span>
        {selected.length > 0 && (
          <button
            onClick={() => clearFilters(ORG_FILTER_NS)}
            className="text-[11px] text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"
          >
            {t("issues.filter.clear")}
          </button>
        )}
      </div>

      <div className="px-3 pt-3 text-[12px] font-medium text-zinc-500">{t("dialogs.addOrg.providerLabel")}</div>

      <div className="flex flex-col overflow-y-auto custom-scrollbar px-2 pb-3 pt-1">
        {rows.length === 0 ? (
          <p className="px-2.5 py-6 text-center text-[12px] text-zinc-500">{t("issues.filter.noData")}</p>
        ) : (
          rows.map(([value, count]) => {
            const isActive = selected.includes(value);
            return (
              <button
                key={value}
                onClick={() => toggle(value)}
                className={cn(
                  "flex items-center gap-2.5 rounded-md px-2.5 py-2 text-left transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.04]",
                  isActive && "bg-zinc-100 dark:bg-white/[0.06]",
                )}
              >
                <span className="h-2 w-2 shrink-0 rounded-sm bg-zinc-400 dark:bg-zinc-600" />
                <span
                  className={cn(
                    "min-w-0 flex-1 truncate text-[13px] text-zinc-700 dark:text-zinc-300",
                    isActive && "text-zinc-900 dark:text-zinc-100",
                  )}
                >
                  {value}
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
