import { ChevronDown } from "lucide-react";

import { useI18n } from "@/i18n/i18n";
import { PrStatusIcon, PR_COLUMN_LABEL_KEY, type PrColumnId } from "@/lib/pr-column";

interface PrHiddenRailProps {
  ids: PrColumnId[];
  counts: Record<PrColumnId, number>;
  onShow: (id: PrColumnId) => void;
}

export function PrHiddenRail({ ids, counts, onShow }: PrHiddenRailProps) {
  const { t } = useI18n();
  if (ids.length === 0) return null;

  return (
    <div className="w-64 shrink-0">
      <div className="flex items-center gap-1 px-1 pb-2 text-[12px] font-medium text-zinc-500">
        <ChevronDown className="h-3.5 w-3.5" />
        {t("prs.kanban.hiddenColumns")}
      </div>
      <div className="flex flex-col gap-1">
        {ids.map((id) => (
          <button
            key={id}
            onClick={() => onShow(id)}
            className="flex items-center justify-between rounded-lg border border-zinc-200 px-3 py-2.5 text-left transition-colors hover:bg-zinc-100 dark:border-zinc-800 dark:hover:bg-white/[0.03]"
          >
            <span className="flex items-center gap-2 text-[13px] text-zinc-700 dark:text-zinc-300">
              <PrStatusIcon column={id} />
              {t(PR_COLUMN_LABEL_KEY[id])}
            </span>
            <span className="text-[12px] tabular-nums text-zinc-500">{counts[id]}</span>
          </button>
        ))}
      </div>
    </div>
  );
}
