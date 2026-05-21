import { GitPullRequest } from "lucide-react";

import { formatRelativeDate } from "../repos/pr-item";
import { LabelBadge } from "./label-badge";
import { StatusIcon } from "./issue-status";
import { IssueActionsMenu } from "./issue-actions-menu";
import type { IssueColumnId, IssueDto } from "../../types/issue";

interface IssueRowProps {
  issue: IssueDto;
  column: IssueColumnId;
  onSelect?: (issue: IssueDto) => void;
  onNavigateToPrs?: (repoName: string, orgId: string, prNumber?: number) => void;
  onNavigateToRepo?: (repoName: string, orgId: string) => void;
  onOpenUrl?: (url: string) => void;
  onDelete?: (issue: IssueDto) => Promise<void>;
  onAssignToMe?: (issue: IssueDto) => Promise<void> | void;
  delegateIssue: (issue: IssueDto) => Promise<void>;
  t: (key: string) => string;
  setIssueToDelete: (issue: IssueDto | null) => void;
}

function Assignees({ names }: { names: string[] }) {
  if (names.length === 0) return null;
  return (
    <div className="flex items-center shrink-0" title={names.join(", ")}>
      <span className="flex h-5 w-5 items-center justify-center rounded-full bg-zinc-200 text-[9px] font-semibold text-zinc-600 dark:bg-zinc-700 dark:text-zinc-300">
        {names[0].slice(0, 2).toUpperCase()}
      </span>
      {names.length > 1 && <span className="ml-1 text-[10px] text-zinc-500">+{names.length - 1}</span>}
    </div>
  );
}

export function IssueRow({
  issue,
  column,
  onSelect,
  onNavigateToPrs,
  onNavigateToRepo,
  onOpenUrl,
  onDelete,
  onAssignToMe,
  delegateIssue,
  t,
  setIssueToDelete,
}: IssueRowProps) {
  const prNumber = issue.linkedPrNumbers[0];

  return (
    <div
      onClick={() => onSelect?.(issue)}
      className="group flex h-9 cursor-pointer items-center gap-2.5 rounded-md pl-3 pr-2 transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.03]"
    >
      <StatusIcon column={column} />
      <span className="w-12 shrink-0 text-[12px] tabular-nums text-zinc-500">#{issue.number}</span>
      <span className="min-w-0 flex-1 truncate text-[13px] text-zinc-800 dark:text-zinc-100">{issue.title}</span>

      <div className="flex shrink-0 items-center gap-2">
        {issue.labels[0] && <LabelBadge name={issue.labels[0]} />}
        {prNumber !== undefined && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              onNavigateToPrs?.(issue.repoName, issue.orgId, prNumber);
            }}
            className="flex items-center gap-1 text-[11px] text-purple-500 hover:underline"
          >
            <GitPullRequest className="h-3 w-3" />#{prNumber}
          </button>
        )}
        <button
          onClick={(e) => {
            e.stopPropagation();
            onNavigateToRepo?.(issue.repoName, issue.orgId);
          }}
          className="hidden max-w-[140px] truncate rounded border border-zinc-200 px-1.5 py-0.5 text-[11px] text-zinc-500 hover:text-zinc-700 dark:border-zinc-800 dark:text-zinc-400 dark:hover:text-zinc-200 md:inline-block"
        >
          {issue.repoName}
        </button>
        <Assignees names={issue.assignees} />
        <span className="w-12 shrink-0 text-right text-[11px] tabular-nums text-zinc-500">
          {formatRelativeDate(issue.updatedAt)}
        </span>
        <IssueActionsMenu
          issue={issue}
          onSelect={onSelect}
          onOpenUrl={onOpenUrl}
          onAssignToMe={onAssignToMe}
          onDelete={onDelete}
          delegateIssue={delegateIssue}
          t={t}
          setIssueToDelete={setIssueToDelete}
        />
      </div>
    </div>
  );
}
