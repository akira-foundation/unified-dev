import { Bot, CircleDot, ExternalLink, MoreVertical, Trash2 } from "lucide-react";
import { useState } from "react";

import { cn } from "@/lib/utils";
import { Button } from "../ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "../ui/dropdown-menu";
import type { IssueDto } from "../../types/issue";

interface IssueActionsMenuProps {
  issue: IssueDto;
  onSelect?: (issue: IssueDto) => void;
  onOpenUrl?: (url: string) => void;
  onAssignToMe?: (issue: IssueDto) => Promise<void> | void;
  onDelete?: (issue: IssueDto) => Promise<void>;
  delegateIssue: (issue: IssueDto) => Promise<void>;
  t: (key: string) => string;
  setIssueToDelete: (issue: IssueDto | null) => void;
}

export function IssueActionsMenu({
  issue,
  onSelect,
  onOpenUrl,
  onAssignToMe,
  onDelete,
  delegateIssue,
  t,
  setIssueToDelete,
}: IssueActionsMenuProps) {
  const [open, setOpen] = useState(false);

  return (
    <div onClick={(e) => e.stopPropagation()} onPointerDown={(e) => e.stopPropagation()}>
      <DropdownMenu open={open} onOpenChange={setOpen} modal={false}>
        <DropdownMenuTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            className={cn(
              "h-6 w-6 text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200",
              !open && "opacity-0 group-hover:opacity-100",
            )}
          >
            <MoreVertical className="h-4 w-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent
          align="end"
          onCloseAutoFocus={(e) => e.preventDefault()}
          onPointerDown={(e) => e.stopPropagation()}
        >
          <DropdownMenuLabel className="text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">
            {t("common.open")}
          </DropdownMenuLabel>
          {onSelect && (
            <DropdownMenuItem onSelect={() => onSelect(issue)}>
              <CircleDot className="mr-2 h-4 w-4" />
              {t("issues.table.viewIssue")}
            </DropdownMenuItem>
          )}
          {onOpenUrl && issue.url && (
            <DropdownMenuItem onSelect={() => onOpenUrl(issue.url)}>
              <ExternalLink className="mr-2 h-4 w-4" />
              {t("issues.table.openInBrowser")}
            </DropdownMenuItem>
          )}
          <DropdownMenuSeparator />
          <DropdownMenuLabel className="text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">
            {t("common.manage")}
          </DropdownMenuLabel>
          <DropdownMenuItem onSelect={() => void delegateIssue(issue)}>
            <Bot className="mr-2 h-4 w-4" />
            {t("issues.detail.delegate")}
          </DropdownMenuItem>
          {onAssignToMe && issue.status === "open" && (
            <DropdownMenuItem onSelect={() => void onAssignToMe(issue)}>
              <CircleDot className="mr-2 h-4 w-4" />
              {t("issues.table.assignToMe")}
            </DropdownMenuItem>
          )}
          {onDelete && issue.status === "open" && (
            <>
              <DropdownMenuSeparator />
              <DropdownMenuLabel className="text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">
                {t("common.dangerZone")}
              </DropdownMenuLabel>
              <DropdownMenuItem
                onSelect={() => setIssueToDelete(issue)}
                className="text-red-500 focus:text-red-500 focus:bg-red-500/10"
              >
                <Trash2 className="mr-2 h-4 w-4" />
                {t("issues.table.deleteIssue")}
              </DropdownMenuItem>
            </>
          )}
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}
