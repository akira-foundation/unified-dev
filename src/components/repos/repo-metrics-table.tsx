import type { OrganizationRepoSummary } from "../../types/organization";
import { FolderGit2, Plus } from "lucide-react";
import { useI18n } from "../../i18n/i18n";

import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent } from "../ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";

interface RepoMetricsTableProps {
  repos: OrganizationRepoSummary[];
  title?: string;
  onCreate?: () => void;
}

export function RepoMetricsTable({ repos, title = "Repositories", onCreate }: RepoMetricsTableProps) {
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
        {onCreate && (
          <Button onClick={onCreate}>
            <Plus size={18} />
            {t("common.newRepository")}
          </Button>
        )}
      </div>
      <CardContent className="p-0 border-t border-zinc-100 dark:border-zinc-800/50 px-0">
        <div className="overflow-hidden rounded-xl">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("tables.header.name")}</TableHead>
                <TableHead className="text-right">{t("tables.header.issues")}</TableHead>
                <TableHead className="text-right">{t("tables.header.prs")}</TableHead>
                <TableHead className="text-right">{t("tables.header.branches")}</TableHead>
                <TableHead className="text-right">{t("tables.header.visibility")}</TableHead>
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
                  <TableCell className="text-right text-sm text-gray-500 dark:text-gray-400">—</TableCell>
                  <TableCell className="text-right text-sm text-gray-500 dark:text-gray-400">—</TableCell>
                  <TableCell className="text-right text-sm text-gray-500 dark:text-gray-400">—</TableCell>
                  <TableCell className="text-right">
                    <Badge variant={repo.visibility === "private" ? "warning" : "secondary"}>
                      {repo.visibility}
                    </Badge>
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
