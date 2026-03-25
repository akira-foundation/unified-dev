import { CircleDot, CheckCircle2, ExternalLink, Tag } from "lucide-react";
import { openUrl } from "@tauri-apps/plugin-opener";

import type { IssueDto } from "../../types/issue";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "../ui/tooltip";
import { formatRelativeDate } from "../repos/pr-item";

interface IssueRowProps {
  issue: IssueDto;
  onClick?: (issue: IssueDto) => void;
}

async function handleOpenUrl(url: string) {
  try {
    await openUrl(url);
  } catch {
    window.open(url, "_blank");
  }
}

export function IssueRow({ issue, onClick }: IssueRowProps) {
  const isOpen = issue.status === "open";

  return (
    <div className="flex items-start justify-between px-4 py-3 transition-colors hover:bg-zinc-50/50 dark:hover:bg-zinc-900/20 border-b border-zinc-100 dark:border-zinc-800/60 last:border-b-0">
      <div className="flex items-start gap-3 min-w-0 flex-1">
        <div className="mt-1.5 shrink-0">
          {isOpen ? (
            <div className="h-2.5 w-2.5 rounded-full bg-green-500" />
          ) : (
            <div className="h-2.5 w-2.5 rounded-full bg-zinc-500" />
          )}
        </div>
        <div className="flex flex-col gap-1 min-w-0">
          <button
            className="text-sm font-semibold text-gray-900 dark:text-white leading-snug text-left hover:text-purple-600 dark:hover:text-purple-400 transition-colors cursor-pointer"
            onClick={() => onClick?.(issue)}
          >
            {issue.title}
          </button>
          <div className="flex items-center gap-1.5 flex-wrap text-xs text-gray-500 dark:text-gray-400">
            <span className="font-medium">#{issue.number}</span>
            <span className="text-zinc-300 dark:text-zinc-600">·</span>
            <span>{issue.repoName}</span>
            {issue.author && (
              <>
                <span className="text-zinc-300 dark:text-zinc-600">·</span>
                <span>{issue.author}</span>
              </>
            )}
            <span className="text-zinc-300 dark:text-zinc-600">·</span>
            <span>{formatRelativeDate(issue.updatedAt)}</span>
          </div>
          {issue.labels.length > 0 && (
            <div className="flex items-center gap-1 flex-wrap mt-0.5">
              {issue.labels.slice(0, 3).map((label) => (
                <Badge key={label} variant="outline" className="text-[10px]">
                  {label}
                </Badge>
              ))}
            </div>
          )}
        </div>
      </div>
      <div className="flex items-center gap-1 shrink-0 ml-4">
        {!isOpen && (
          <Badge variant="secondary" className="text-[10px] uppercase">
            {issue.status}
          </Badge>
        )}
        {issue.assignees.length > 0 && (
          <span className="text-xs text-zinc-500 hidden sm:inline">
            {issue.assignees[0]}
            {issue.assignees.length > 1 && ` +${issue.assignees.length - 1}`}
          </span>
        )}
        {issue.url && (
          <Tooltip>
            <TooltipTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                className="text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200 cursor-pointer"
                onClick={(e) => { e.stopPropagation(); handleOpenUrl(issue.url); }}
              >
                <ExternalLink className="h-4 w-4" />
              </Button>
            </TooltipTrigger>
            <TooltipContent>Open on GitHub</TooltipContent>
          </Tooltip>
        )}
      </div>
    </div>
  );
}
