import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { FolderGit2, GitMerge } from "lucide-react";

import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import { PrStatusIcon } from "@/lib/pr-column";
import { formatRelativeDate } from "@/components/repos/pr-item";
import type { PrCardType } from "@/hooks/usePrCards";

function CiBadge({ status }: { status: string | null }) {
  if (!status) return null;
  return (
    <span
      className={cn(
        "shrink-0 rounded px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider",
        status === "success"
          ? "bg-emerald-500/10 text-emerald-500"
          : status === "failure"
            ? "bg-red-500/10 text-red-500"
            : "bg-amber-500/10 text-amber-500",
      )}
    >
      {status}
    </span>
  );
}

export function PrCardView({
  card,
  overlay = false,
  onSelect,
}: {
  card: PrCardType;
  overlay?: boolean;
  onSelect?: (card: PrCardType) => void;
}) {
  const pr = card.pr;

  return (
    <Card
      className={cn(
        "flex flex-col gap-2 border-zinc-200 bg-white p-2.5 transition-colors hover:border-zinc-300 dark:border-zinc-800 dark:bg-zinc-900/40 dark:hover:border-zinc-700",
        overlay ? "cursor-grabbing rotate-2 shadow-xl" : "cursor-grab active:cursor-grabbing",
      )}
      onClick={() => onSelect?.(card)}
    >
      <div className="flex items-center justify-between">
        <span className="text-[11px] tabular-nums text-zinc-500">#{pr.number}</span>
        {pr.author ? (
          <span
            className="flex h-5 w-5 items-center justify-center rounded-full bg-zinc-200 text-[9px] font-semibold text-zinc-600 dark:bg-zinc-700 dark:text-zinc-300"
            title={pr.author}
          >
            {pr.author.slice(0, 2).toUpperCase()}
          </span>
        ) : (
          <span className="h-5 w-5 rounded-full border border-dashed border-zinc-300 dark:border-zinc-700" />
        )}
      </div>

      <div className="flex items-start gap-2">
        <PrStatusIcon column={card.columnId} className="mt-0.5" />
        <span className="line-clamp-2 text-[13px] font-medium leading-snug text-zinc-800 dark:text-zinc-100">
          {pr.title}
        </span>
      </div>

      <div className="flex flex-wrap items-center gap-x-2.5 gap-y-1 text-[10px] text-zinc-500 dark:text-zinc-400">
        <span className="inline-flex max-w-[130px] items-center gap-1 truncate">
          <FolderGit2 className="h-3 w-3 shrink-0" />
          {card.repoName}
        </span>
        {pr.merged_at && (
          <span className="inline-flex items-center gap-0.5 text-emerald-500">
            <GitMerge className="h-3 w-3" />
          </span>
        )}
        <CiBadge status={pr.ci_status} />
        {pr.labels.slice(0, 2).map((label) => (
          <span key={label} className="inline-flex max-w-[120px] items-center gap-1 truncate">
            <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-zinc-400 dark:bg-zinc-500" />
            {label}
          </span>
        ))}
      </div>

      <span className="text-[10px] text-zinc-400 dark:text-zinc-500">{formatRelativeDate(pr.updated_at)}</span>
    </Card>
  );
}

export function PrCard({ card, onSelect }: { card: PrCardType; onSelect?: (card: PrCardType) => void }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: card.id });

  return (
    <div
      ref={setNodeRef}
      style={{
        transform: CSS.Transform.toString(transform),
        transition,
        opacity: isDragging ? 0 : 1,
        contentVisibility: "auto",
        containIntrinsicSize: "auto 80px",
      }}
      {...attributes}
      {...listeners}
    >
      <PrCardView card={card} onSelect={onSelect} />
    </div>
  );
}
