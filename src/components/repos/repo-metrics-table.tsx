import type { OrganizationRepoWithOrg } from "../../types/organization";
import { FolderGit2, MoreVertical, Plus, RefreshCw, RotateCw } from "lucide-react";
import { useI18n } from "../../i18n/i18n";
import { cn } from "@/lib/utils";

import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent } from "../ui/card";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";

interface RepoMetricsTableProps {
  repos: OrganizationRepoWithOrg[];
  title?: string;
  onCreate?: () => void;
  onNewTask?: (repo: OrganizationRepoWithOrg) => void;
  onSync?: () => void;
  onSyncRepo?: (repo: OrganizationRepoWithOrg) => void;
  onOrganizationClick?: (repo: OrganizationRepoWithOrg) => void;
  isSyncing?: boolean;
  syncingRepoId?: string;
  hideOrganization?: boolean;
}

export function RepoMetricsTable({ repos, title = "Repositories", onCreate, onNewTask, onSync, onSyncRepo, onOrganizationClick, isSyncing, syncingRepoId, hideOrganization }: RepoMetricsTableProps) {
  const { t } = useI18n();
  return (
    <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
      <div className="flex flex-row items-center justify-between px-6 py-6 pb-6">
        <div className="flex flex-row items-center gap-4">
          <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
            <FolderGit2 size={22} strokeWidth={2} />
          </div>
          <div className="flex flex-col gap-1">
            <span className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">{title}</span>
            <span className="text-[13px] font-medium text-zinc-500/80 leading-none">
              {t("components.repoTable.description")}
            </span>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {onSync && (
            <Button variant="outline" onClick={onSync} disabled={isSyncing}>
              <RefreshCw className={cn("h-4 w-4", isSyncing && "animate-spin")} />
              {t("common.syncAll")}
            </Button>
          )}
          {onCreate && (
            <Button onClick={onCreate}>
              <Plus size={18} />
              {t("common.newRepository")}
            </Button>
          )}
        </div>
      </div>
      <CardContent className="p-0 border-t border-zinc-100 dark:border-zinc-800/50 px-0">
        <div className="overflow-hidden rounded-xl">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("tables.header.name")}</TableHead>
                {!hideOrganization && <TableHead>{t("tables.header.organization")}</TableHead>}
                <TableHead className="text-right">{t("tables.header.prs")}</TableHead>
                <TableHead className="text-right">{t("tables.header.default")}</TableHead>
                <TableHead className="text-right">{t("tables.header.visibility")}</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {repos.map((repo) => (
                <TableRow key={repo.id}>
                  <TableCell>
                    <div className="flex flex-col">
                      <span className="text-sm font-semibold text-gray-900 dark:text-white">
                        {repo.repo_name}
                      </span>
                      <span className="text-xs text-gray-500 dark:text-gray-400">{repo.owner}</span>
                    </div>
                  </TableCell>
                  {!hideOrganization && (
                    <TableCell>
                      {onOrganizationClick ? (
                        <button onClick={() => onOrganizationClick(repo)} className="cursor-pointer">
                          <Badge variant="secondary" className="hover:bg-zinc-200 dark:hover:bg-zinc-700 transition-colors">
                            {repo.organization_name}
                          </Badge>
                        </button>
                      ) : (
                        <Badge variant="secondary">{repo.organization_name}</Badge>
                      )}
                    </TableCell>
                  )}
                  <TableCell className="text-right text-sm text-gray-500 dark:text-gray-400">
                    {repo.open_prs_count > 0 ? repo.open_prs_count : "—"}
                  </TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end items-center gap-2">
                      <Badge variant="secondary">{repo.default_branch}</Badge>
                    </div>
                  </TableCell>
                  <TableCell className="text-right">
                    <Badge variant={repo.visibility === "private" ? "warning" : "secondary"}>
                      {repo.visibility}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-right">
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button variant="ghost" size="icon">
                          <MoreVertical className="h-4 w-4" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem onSelect={() => onNewTask?.(repo)}>
                          <Plus className="mr-2 h-4 w-4" />
                          {t("common.newTask")}
                        </DropdownMenuItem>
                        {onSyncRepo && (
                          <DropdownMenuItem onSelect={() => onSyncRepo(repo)} disabled={syncingRepoId === String(repo.id)}>
                            <RotateCw className={cn("mr-2 h-4 w-4", syncingRepoId === String(repo.id) && "animate-spin")} />
                            {t("common.sync")}
                          </DropdownMenuItem>
                        )}
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      </CardContent>
    </Card>
  );
}
