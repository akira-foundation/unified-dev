import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { FolderGit2, GitPullRequest } from "lucide-react";

import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import { StatusIcon } from "@/components/issues/issue-status";
import { formatRelativeDate } from "@/components/repos/pr-item";
import type { IssueColumnId, IssueDto } from "@/types/issue";

export interface IssueCardType {
  id: string;
  issue: IssueDto;
  columnId: IssueColumnId;
}

export function KanbanCardView({
  card,
  overlay = false,
  onSelect,
}: {
  card: IssueCardType;
  overlay?: boolean;
  onSelect?: (issue: IssueDto) => void;
}) {
  const issue = card.issue;
  const prNumber = issue.linkedPrNumbers[0];

  return (
    <Card
      className={cn(
        "flex flex-col gap-2 border-zinc-200 bg-white p-2.5 transition-colors hover:border-zinc-300 dark:border-zinc-800 dark:bg-zinc-900/40 dark:hover:border-zinc-700",
        overlay ? "cursor-grabbing rotate-2 shadow-xl" : "cursor-grab active:cursor-grabbing",
      )}
      onClick={() => onSelect?.(issue)}
    >
      <div className="flex items-center justify-between">
        <span className="text-[11px] tabular-nums text-zinc-500">#{issue.number}</span>
        {issue.assignees[0] ? (
          <span
            className="flex h-5 w-5 items-center justify-center rounded-full bg-zinc-200 text-[9px] font-semibold text-zinc-600 dark:bg-zinc-700 dark:text-zinc-300"
            title={issue.assignees.join(", ")}
          >
            {issue.assignees[0].slice(0, 2).toUpperCase()}
          </span>
        ) : (
          <span className="h-5 w-5 rounded-full border border-dashed border-zinc-300 dark:border-zinc-700" />
        )}
      </div>

      <div className="flex items-start gap-2">
        <StatusIcon column={card.columnId} className="mt-0.5" />
        <span className="line-clamp-2 text-[13px] font-medium leading-snug text-zinc-800 dark:text-zinc-100">
          {issue.title}
        </span>
      </div>

      <div className="flex flex-wrap items-center gap-x-2.5 gap-y-1 text-[10px] text-zinc-500 dark:text-zinc-400">
        <span className="inline-flex max-w-[130px] items-center gap-1 truncate">
          <FolderGit2 className="h-3 w-3 shrink-0" />
          {issue.repoName}
        </span>
        {prNumber !== undefined && (
          <span className="inline-flex items-center gap-0.5 text-purple-500">
            <GitPullRequest className="h-3 w-3" />#{prNumber}
          </span>
        )}
        {issue.labels.slice(0, 2).map((label) => (
          <span key={label} className="inline-flex max-w-[120px] items-center gap-1 truncate">
            <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-zinc-400 dark:bg-zinc-500" />
            {label}
          </span>
        ))}
      </div>

      <span className="text-[10px] text-zinc-400 dark:text-zinc-500">Created {formatRelativeDate(issue.createdAt)}</span>
    </Card>
  );
}

export function KanbanCard({ card, onSelect }: { card: IssueCardType; onSelect?: (issue: IssueDto) => void }) {
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
      <KanbanCardView card={card} onSelect={onSelect} />
    </div>
  );
}
