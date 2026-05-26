import { Circle, CircleDot, GitMerge, XCircle } from "lucide-react";

import { cn } from "@/lib/utils";
import type { PullRequestDto } from "@/types/organization";

export type PrColumnId = "todo" | "failed" | "inprogress" | "review" | "done";

export const PR_COLUMN_ORDER: PrColumnId[] = ["todo", "failed", "inprogress", "review", "done"];

export const PR_COLUMN_LABEL_KEY: Record<PrColumnId, string> = {
  todo: "kanban.columns.open",
  failed: "kanban.columns.failed",
  inprogress: "kanban.columns.build",
  review: "kanban.columns.ready",
  done: "kanban.columns.merge",
};

export function mapPrToColumn(pr: PullRequestDto): PrColumnId {
  if (pr.merged_at !== null) return "done";
  if (pr.ci_status === "failure" || pr.ci_status === "error") return "failed";
  if (pr.ci_status === "success" && pr.reviewers.length > 0) return "review";
  if (pr.ci_status === "success") return "inprogress";
  return "todo";
}

export function PrStatusIcon({ column, className }: { column: PrColumnId; className?: string }) {
  const cls = cn("h-3.5 w-3.5 shrink-0", className);
  if (column === "done") return <GitMerge className={cn(cls, "text-emerald-500")} />;
  if (column === "failed") return <XCircle className={cn(cls, "text-rose-500")} />;
  if (column === "review") return <CircleDot className={cn(cls, "text-amber-500")} />;
  if (column === "inprogress") return <CircleDot className={cn(cls, "text-blue-500")} />;
  return <Circle className={cn(cls, "text-zinc-400")} />;
}
