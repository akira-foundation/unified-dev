import { ChevronDown, ChevronRight, CheckCircle2, Clock, ExternalLink, FileCode, MoreVertical, XCircle } from "lucide-react";
import { useMemo, useState, type RefObject } from "react";
import { useVirtualizer } from "@tanstack/react-virtual";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { EmptyState } from "@/components/ui/empty-state";
import { formatRelativeDate } from "@/components/repos/pr-item";
import { PrStatusIcon, PR_COLUMN_LABEL_KEY, PR_COLUMN_ORDER, type PrColumnId } from "@/lib/pr-column";
import type { PrCardType } from "@/hooks/usePrCards";

function CiIcon({ status }: { status: string | null }) {
  if (status === "success") return <CheckCircle2 className="h-3.5 w-3.5 shrink-0 text-emerald-500" />;
  if (status === "failure") return <XCircle className="h-3.5 w-3.5 shrink-0 text-red-500" />;
  if (status === "pending") return <Clock className="h-3.5 w-3.5 shrink-0 text-amber-500" />;
  return null;
}

function PrRow({
  card,
  onSelect,
  onOpenUrl,
}: {
  card: PrCardType;
  onSelect?: (card: PrCardType) => void;
  onOpenUrl?: (url: string) => void;
}) {
  const { t } = useI18n();
  const pr = card.pr;

  return (
    <div
      onClick={() => onSelect?.(card)}
      className="group flex h-9 cursor-pointer items-center gap-2.5 rounded-md pl-3 pr-2 transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.03]"
    >
      <PrStatusIcon column={card.columnId} />
      <span className="w-12 shrink-0 text-[12px] tabular-nums text-zinc-500">#{pr.number}</span>
      <span className="min-w-0 flex-1 truncate text-[13px] text-zinc-800 dark:text-zinc-100">{pr.title}</span>

      <div className="flex shrink-0 items-center gap-2">
        <CiIcon status={pr.ci_status} />
        {pr.labels[0] && (
          <span className="hidden max-w-[120px] truncate rounded border border-zinc-200 px-1.5 py-0.5 text-[11px] text-zinc-500 dark:border-zinc-800 dark:text-zinc-400 md:inline-block">
            {pr.labels[0]}
          </span>
        )}
        <span className="hidden max-w-[140px] truncate rounded border border-zinc-200 px-1.5 py-0.5 text-[11px] text-zinc-500 dark:border-zinc-800 dark:text-zinc-400 md:inline-block">
          {card.repoName}
        </span>
        {pr.author && (
          <span
            className="flex h-5 w-5 items-center justify-center rounded-full bg-zinc-200 text-[9px] font-semibold text-zinc-600 dark:bg-zinc-700 dark:text-zinc-300"
            title={pr.author}
          >
            {pr.author.slice(0, 2).toUpperCase()}
          </span>
        )}
        <span className="w-12 shrink-0 text-right text-[11px] tabular-nums text-zinc-500">
          {formatRelativeDate(pr.updated_at)}
        </span>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              onClick={(e) => e.stopPropagation()}
              className="flex h-6 w-6 items-center justify-center rounded text-zinc-400 transition-colors hover:bg-zinc-200 hover:text-zinc-700 dark:hover:bg-zinc-700 dark:hover:text-zinc-200"
            >
              <MoreVertical className="h-4 w-4" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onSelect={() => onSelect?.(card)}>
              <FileCode className="mr-2 h-4 w-4" />
              {t("components.prDetail.review")}
            </DropdownMenuItem>
            <DropdownMenuItem onSelect={() => onOpenUrl?.(pr.url)}>
              <ExternalLink className="mr-2 h-4 w-4" />
              {t("components.prReview.viewPrButton")}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  );
}

export function PrList({
  cards,
  onSelect,
  onOpenUrl,
  scrollParentRef,
}: {
  cards: PrCardType[];
  onSelect?: (card: PrCardType) => void;
  onOpenUrl?: (url: string) => void;
  scrollParentRef?: RefObject<HTMLElement | null>;
}) {
  const { t } = useI18n();
  const [collapsed, setCollapsed] = useState<Set<PrColumnId>>(new Set());

  const grouped = useMemo(() => {
    const map: Record<PrColumnId, PrCardType[]> = { todo: [], inprogress: [], review: [], done: [] };
    cards.forEach((card) => (map[card.columnId] ?? map.todo).push(card));
    PR_COLUMN_ORDER.forEach((col) => map[col].sort((a, b) => b.pr.updated_at.localeCompare(a.pr.updated_at)));
    return map;
  }, [cards]);

  const toggleGroup = (col: PrColumnId) =>
    setCollapsed((prev) => {
      const next = new Set(prev);
      if (next.has(col)) next.delete(col);
      else next.add(col);
      return next;
    });

  type FlatItem =
    | { kind: "header"; col: PrColumnId; count: number }
    | { kind: "row"; card: PrCardType; col: PrColumnId };

  const flatItems = useMemo(() => {
    const out: FlatItem[] = [];
    PR_COLUMN_ORDER.forEach((col) => {
      const rows = grouped[col];
      if (rows.length === 0) return;
      out.push({ kind: "header", col, count: rows.length });
      if (!collapsed.has(col)) rows.forEach((card) => out.push({ kind: "row", card, col }));
    });
    return out;
  }, [grouped, collapsed]);

  const virtualizer = useVirtualizer({
    count: flatItems.length,
    getScrollElement: () => scrollParentRef?.current ?? null,
    estimateSize: (index) => (flatItems[index].kind === "header" ? 34 : 36),
    overscan: 12,
  });

  if (cards.length === 0) {
    return <EmptyState title={t("prs.table.empty")} />;
  }

  return (
    <div style={{ height: virtualizer.getTotalSize(), position: "relative" }}>
      {virtualizer.getVirtualItems().map((virtualItem) => {
        const item = flatItems[virtualItem.index];
        return (
          <div
            key={virtualItem.key}
            data-index={virtualItem.index}
            ref={virtualizer.measureElement}
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              width: "100%",
              transform: `translateY(${virtualItem.start}px)`,
            }}
          >
            {item.kind === "header" ? (
              <button
                onClick={() => toggleGroup(item.col)}
                className="flex w-full items-center gap-2 bg-background px-3 py-1.5 text-left"
              >
                <PrStatusIcon column={item.col} />
                <span className={cn("text-[13px] font-semibold capitalize text-zinc-700 dark:text-zinc-200")}>
                  {t(PR_COLUMN_LABEL_KEY[item.col]).toLowerCase()}
                </span>
                <span className="text-[12px] font-medium text-zinc-500">{item.count}</span>
                {collapsed.has(item.col) ? (
                  <ChevronRight className="ml-auto h-3.5 w-3.5 text-zinc-500" />
                ) : (
                  <ChevronDown className="ml-auto h-3.5 w-3.5 text-zinc-500" />
                )}
              </button>
            ) : (
              <PrRow card={item.card} onSelect={onSelect} onOpenUrl={onOpenUrl} />
            )}
          </div>
        );
      })}
    </div>
  );
}
