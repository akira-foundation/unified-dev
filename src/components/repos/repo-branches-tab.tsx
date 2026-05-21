import { ExternalLink, GitBranch, MoreVertical, RefreshCw, Trash2 } from "lucide-react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent } from "../ui/card";
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
}: RepoBranchesTabProps) {
  const { t } = useI18n();

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

  const count = branches.length;
  const countKey = count === 1 ? "pages.repositoryBranches.count" : "pages.repositoryBranches.countPlural";

  return (
    <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
      <div className="flex flex-row items-center justify-between px-6 py-6">
        <div className="flex flex-row items-center gap-4">
          <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-blue-500/10 text-blue-500 border border-blue-500/10 shrink-0">
            <GitBranch size={22} strokeWidth={2} />
          </div>
          <div className="flex flex-col gap-1">
            <span className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">
              {t("pages.repositoryBranches.title")}
            </span>
            <span className="text-[13px] font-medium text-zinc-500/80 leading-none">
              {t(countKey).replace("{count}", String(count))}
            </span>
          </div>
        </div>
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
      </div>
      <CardContent className="p-0 border-t border-zinc-100 dark:border-zinc-800/50">
        {branches.map((branch) => (
          <div
            key={branch.name}
            className="flex items-center justify-between px-6 py-3 border-b border-zinc-100 dark:border-zinc-800/50 last:border-0 hover:bg-zinc-50 dark:hover:bg-zinc-800/30 transition-colors"
          >
            <div className="flex items-center gap-2 min-w-0">
              <GitBranch className="h-4 w-4 shrink-0 text-zinc-400" />
              <span className="font-mono text-sm font-medium text-zinc-900 dark:text-white truncate">{branch.name}</span>
            </div>
            <div className="flex items-center gap-2 shrink-0">
              {branch.is_default && (
                <Badge variant="secondary" className="text-[10px] px-1.5 py-0">{t("pages.repositoryBranches.default")}</Badge>
              )}
              {branch.is_protected && (
                <Badge variant="warning" className="text-[10px] px-1.5 py-0">{t("pages.repositoryBranches.protected")}</Badge>
              )}
              <span className="font-mono text-[11px] text-zinc-400 dark:text-zinc-500">{branch.sha.slice(0, 7)}</span>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" size="icon" className="h-7 w-7 text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200">
                    <MoreVertical className="h-4 w-4" />
                  </Button>
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
      </CardContent>
    </Card>
  );
}
