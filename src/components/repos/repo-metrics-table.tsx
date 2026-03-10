import type { OrganizationRepoSummary } from "../../types/organization";
import { FolderGit2 } from "lucide-react";

import { Badge } from "../ui/badge";
import { Card, CardContent, CardHeader } from "../ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";

interface RepoMetricsTableProps {
  repos: OrganizationRepoSummary[];
  title?: string;
}

export function RepoMetricsTable({ repos, title = "Repositories" }: RepoMetricsTableProps) {
  return (
    <Card>
      <CardHeader>
        <div className="flex items-center gap-2">
          <FolderGit2 className="h-4 w-4 text-muted-foreground" />
          <span className="text-sm font-semibold">{title}</span>
        </div>
      </CardHeader>
      <CardContent>
        <div className="overflow-hidden rounded-xl">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Name</TableHead>
                <TableHead className="text-right">Issues</TableHead>
                <TableHead className="text-right">PRs</TableHead>
                <TableHead className="text-right">Branches</TableHead>
                <TableHead className="text-right">Visibility</TableHead>
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
