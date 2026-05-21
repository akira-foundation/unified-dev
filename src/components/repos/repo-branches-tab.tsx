import { ExternalLink, GitBranch, MoreVertical, RefreshCw, Trash2 } from "lucide-react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { EmptyState } from "../ui/empty-state";
import { Skeleton } from "../ui/skeleton";
import { Tooltip, TooltipContent, TooltipTrigger } from "../ui/tooltip";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "../ui/dropdown-menu";
import { AppbarActions } from "../layout/appbar-actions";
import type { BranchDto } from "../../types/organization";

interface RepoBranchesTabProps {
  branches: BranchDto[];
  loading: boolean;
  syncing: boolean;
  deleting: boolean;
  owner: string;
  repoName: string;
  onSync: () => void;
  onDelete: (branchName: string) => void;
  onOpenUrl: (url: string) => void;
  actionsInAppbar?: boolean;
}

export function RepoBranchesTab({
  branches,
  loading,
  syncing,
  deleting,
  owner,
  repoName,
  onSync,
  onDelete,
  onOpenUrl,
  actionsInAppbar,
}: RepoBranchesTabProps) {
  const { t } = useI18n();

  const syncControl = (
    <DropdownMenu>
      <Tooltip>
        <TooltipTrigger asChild>
          <DropdownMenuTrigger asChild>
            <Button variant="outline" size="icon" onClick={(e) => e.preventDefault()} disabled={syncing}>
              <RefreshCw className={cn("h-4 w-4", syncing && "animate-spin")} />
            </Button>
          </DropdownMenuTrigger>
        </TooltipTrigger>
        <TooltipContent>{t("pages.repositoryBranches.syncBranches")}</TooltipContent>
      </Tooltip>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onSelect={onSync} disabled={syncing}>
          <RefreshCw className={cn("mr-2 h-4 w-4", syncing && "animate-spin")} />
          {t("pages.repositoryBranches.syncBranches")}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );

  if (loading) {
    return (
      <div className="space-y-3">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-12 w-full" />
        ))}
      </div>
    );
  }

  if (branches.length === 0) {
    return (
      <EmptyState
        title={t("pages.repositoryBranches.empty.title")}
        description={t("pages.repositoryBranches.empty.description")}
      />
    );
  }

  return (
    <div className="flex flex-col">
      {actionsInAppbar ? (
        <AppbarActions>{syncControl}</AppbarActions>
      ) : (
        <div className="flex justify-end px-1 pb-2">{syncControl}</div>
      )}

      {branches.map((branch) => (
        <div
          key={branch.name}
          className="group flex h-10 items-center gap-2.5 rounded-md pl-3 pr-2 transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.03]"
        >
          <GitBranch className="h-4 w-4 shrink-0 text-zinc-400" />
          <span className="truncate font-mono text-[13px] text-zinc-800 dark:text-zinc-100">{branch.name}</span>

          <div className="ml-auto flex shrink-0 items-center gap-2">
            {branch.is_default && (
              <Badge variant="secondary" className="px-1.5 py-0 text-[10px]">{t("pages.repositoryBranches.default")}</Badge>
            )}
            {branch.is_protected && (
              <Badge variant="warning" className="px-1.5 py-0 text-[10px]">{t("pages.repositoryBranches.protected")}</Badge>
            )}
            <span className="font-mono text-[11px] text-zinc-400 dark:text-zinc-500">{branch.sha.slice(0, 7)}</span>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <button className="flex h-6 w-6 items-center justify-center rounded text-zinc-400 transition-colors hover:bg-zinc-200 hover:text-zinc-700 dark:hover:bg-zinc-700 dark:hover:text-zinc-200">
                  <MoreVertical className="h-4 w-4" />
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem onSelect={() => onOpenUrl(`https://github.com/${owner}/${repoName}/tree/${branch.name}`)}>
                  <ExternalLink className="mr-2 h-4 w-4" />
                  {t("pages.repositoryBranches.openInBrowser")}
                </DropdownMenuItem>
                {!branch.is_default && !branch.is_protected && (
                  <>
                    <DropdownMenuSeparator />
                    <DropdownMenuItem
                      onSelect={() => onDelete(branch.name)}
                      disabled={deleting}
                      className="text-red-500 focus:text-red-500 focus:bg-red-500/10"
                    >
                      <Trash2 className="mr-2 h-4 w-4" />
                      {t("pages.repositoryBranches.deleteBranch")}
                    </DropdownMenuItem>
                  </>
                )}
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      ))}
    </div>
  );
}
