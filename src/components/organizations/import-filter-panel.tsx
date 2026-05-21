import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import type { VisibilityFilterValue } from "@/components/organizations/repo-selection-table";

interface ImportFilterPanelProps {
  visibility: VisibilityFilterValue;
  onChange: (value: VisibilityFilterValue) => void;
  counts: { all: number; public: number; private: number };
}

export function ImportFilterPanel({ visibility, onChange, counts }: ImportFilterPanelProps) {
  const { t } = useI18n();
  const options: Array<[VisibilityFilterValue, string, number]> = [
    ["all", t("repos.table.filter.all"), counts.all],
    ["public", t("repos.table.filter.public"), counts.public],
    ["private", t("repos.table.filter.private"), counts.private],
  ];

  return (
    <aside className="flex w-60 shrink-0 flex-col border-l border-zinc-200 pl-4 dark:border-zinc-800">
      <div className="flex items-center justify-between pb-2">
        <span className="text-[12px] font-semibold uppercase tracking-wider text-zinc-500">
          {t("repos.table.filter.visibility")}
        </span>
        {visibility !== "all" && (
          <button onClick={() => onChange("all")} className="text-[11px] text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300">
            {t("repos.table.filter.clear")}
          </button>
        )}
      </div>
      <div className="flex flex-col">
        {options.map(([val, label, count]) => (
          <button
            key={val}
            onClick={() => onChange(val)}
            className={cn(
              "flex items-center justify-between rounded-md px-2.5 py-2 text-left text-[13px] transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.04]",
              visibility === val ? "bg-zinc-100 text-zinc-900 dark:bg-white/[0.06] dark:text-zinc-100" : "text-zinc-700 dark:text-zinc-300",
            )}
          >
            <span>{label}</span>
            <span className="text-[12px] tabular-nums text-zinc-500">{count}</span>
          </button>
        ))}
      </div>
    </aside>
  );
}
