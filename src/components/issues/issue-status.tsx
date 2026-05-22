import { Circle, CircleCheckBig, CircleDashed, CircleDot } from "lucide-react";

import { cn } from "@/lib/utils";
import { ISSUE_COLUMNS, type IssueColumnId } from "../../types/issue";

export const STATUS_META: Record<IssueColumnId, { icon: typeof Circle; color: string }> = {
  backlog: { icon: CircleDashed, color: "text-zinc-500" },
  todo: { icon: Circle, color: "text-zinc-400" },
  in_progress: { icon: CircleDot, color: "text-amber-500" },
  done: { icon: CircleCheckBig, color: "text-emerald-500" },
};

export const GROUP_ORDER: IssueColumnId[] = ["in_progress", "todo", "backlog", "done"];

export const COLUMN_LABEL = Object.fromEntries(
  ISSUE_COLUMNS.map((c) => [c.id, c.label]),
) as Record<IssueColumnId, string>;

export function StatusIcon({ column, className }: { column: IssueColumnId; className?: string }) {
  const meta = STATUS_META[column];
  const Icon = meta.icon;
  return <Icon className={cn("h-3.5 w-3.5 shrink-0", meta.color, className)} />;
}
