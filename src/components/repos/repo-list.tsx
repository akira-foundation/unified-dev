import { Eye, FolderGit2, GitPullRequest, MoreVertical, Plus, RefreshCw, RotateCw, Trash2 } from "lucide-react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { useRepoActions } from "@/hooks/useRepoActions";
import { Badge } from "@/components/ui/badge";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { GhCliErrorDialog } from "@/components/repos/gh-cli-error-dialog";
import { EmptyState } from "@/components/ui/empty-state";
import type { OrganizationRepoWithOrg } from "@/types/organization";

interface RepoListProps {
  repos: OrganizationRepoWithOrg[];
  syncingRepoId?: string;
  onSyncRepo?: (repo: OrganizationRepoWithOrg) => void;
  onVisibilitySettings?: (repo: OrganizationRepoWithOrg) => void;
  onRemoveRepo?: (repo: OrganizationRepoWithOrg) => void;
  onOrganizationClick?: (repo: OrganizationRepoWithOrg) => void;
}

export function RepoList({
  repos,
  syncingRepoId,
  onSyncRepo,
  onVisibilitySettings,
  onRemoveRepo,
  onOrganizationClick,
}: RepoListProps) {
  const { t } = useI18n();
  const { handleViewRepo, handleViewPrs, handleViewIssues, handleNewTask, ghCliError, setGhCliError } = useRepoActions();

  if (repos.length === 0) {
    return <EmptyState title={t("pages.repository.empty.title")} description={t("pages.repository.empty.description")} />;
  }

  return (
    <>
      <div className="flex flex-col">
        {repos.map((repo) => (
          <div
            key={repo.id}
            onClick={() => handleViewRepo(repo)}
            className="group flex h-10 cursor-pointer items-center gap-2.5 rounded-md pl-3 pr-2 transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.03]"
          >
            <FolderGit2 className="h-4 w-4 shrink-0 text-zinc-400" />
            <span className="truncate text-[13px] font-medium text-zinc-800 dark:text-zinc-100">{repo.repo_name}</span>
            <span className="hidden truncate text-[11px] text-zinc-500 sm:inline">{repo.owner}</span>
            {repo.is_fork && (
              <Badge variant="info" className="h-4 px-1.5 py-0 text-[10px] font-medium">Fork</Badge>
            )}

            <div className="ml-auto flex shrink-0 items-center gap-2">
              {onOrganizationClick && (
                <button
                  onClick={(e) => { e.stopPropagation(); onOrganizationClick(repo); }}
                  className="hidden md:inline-block"
                >
                  <Badge variant="secondary" className="transition-colors hover:bg-zinc-200 dark:hover:bg-zinc-700">
                    {repo.organization_name}
                  </Badge>
                </button>
              )}
              <span className="flex w-12 items-center justify-end gap-1 text-[11px] tabular-nums text-zinc-500">
                <GitPullRequest className="h-3 w-3" />
                {(repo.open_prs_count ?? 0) > 0 ? (
                  <button
                    onClick={(e) => { e.stopPropagation(); handleViewPrs(repo); }}
                    className="font-semibold text-purple-500 hover:underline"
                  >
                    {repo.open_prs_count}
                  </button>
                ) : (
                  <span>—</span>
                )}
              </span>
              <span className="hidden w-16 truncate text-right text-[11px] text-zinc-500 md:inline">{repo.default_branch || "—"}</span>
              <Badge variant={repo.visibility === "private" ? "warning" : "secondary"} className="text-[10px]">
                {repo.visibility}
              </Badge>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <button
                    onClick={(e) => e.stopPropagation()}
                    className="flex h-6 w-6 items-center justify-center rounded text-zinc-400 transition-colors hover:bg-zinc-200 hover:text-zinc-700 dark:hover:bg-zinc-700 dark:hover:text-zinc-200"
                  >
                    <MoreVertical className="h-4 w-4" />
                  </button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" onClick={(e) => e.stopPropagation()}>
                  <DropdownMenuLabel className="text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">{t("common.open")}</DropdownMenuLabel>
                  <DropdownMenuItem onSelect={() => handleViewRepo(repo)}>
                    <Eye className="mr-2 h-4 w-4" />
                    {t("common.viewRepo")}
                  </DropdownMenuItem>
                  <DropdownMenuItem onSelect={() => handleViewIssues(repo)}>
                    <GitPullRequest className="mr-2 h-4 w-4" />
                    {t("issues.page.title")}
                  </DropdownMenuItem>
                  <DropdownMenuItem onSelect={() => void handleNewTask(repo)}>
                    <Plus className="mr-2 h-4 w-4" />
                    {t("common.newTask")}
                  </DropdownMenuItem>
                  {(onVisibilitySettings || onSyncRepo) && (
                    <>
                      <DropdownMenuSeparator />
                      <DropdownMenuLabel className="text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">{t("common.manage")}</DropdownMenuLabel>
                    </>
                  )}
                  {onVisibilitySettings && (
                    <DropdownMenuItem onSelect={() => onVisibilitySettings(repo)}>
                      <RefreshCw className="mr-2 h-4 w-4" />
                      {t("common.configureSync")}
                    </DropdownMenuItem>
                  )}
                  {onSyncRepo && (
                    <DropdownMenuItem onSelect={() => onSyncRepo(repo)} disabled={syncingRepoId === String(repo.id)}>
                      <RotateCw className={cn("mr-2 h-4 w-4", syncingRepoId === String(repo.id) && "animate-spin")} />
                      {t("common.sync")}
                    </DropdownMenuItem>
                  )}
                  {onRemoveRepo && (
                    <>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem onSelect={() => onRemoveRepo(repo)} className="text-red-500 focus:text-red-500">
                        <Trash2 className="mr-2 h-4 w-4" />
                        {t("common.remove")}
                      </DropdownMenuItem>
                    </>
                  )}
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          </div>
        ))}
      </div>

      <GhCliErrorDialog open={!!ghCliError} onOpenChange={(open) => { if (!open) setGhCliError(null); }} kind={ghCliError} />
    </>
  );
}
