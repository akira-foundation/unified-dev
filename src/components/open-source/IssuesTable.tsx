import { openUrl } from "@tauri-apps/plugin-opener";
import { ExternalLink, MessageSquare } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useI18n } from "@/i18n/i18n";
import { useOssIssues } from "@/hooks/useOpenSource";
import { useOpenSourceFiltersStore } from "@/stores/useOpenSourceFiltersStore";

import { EmptyOpenSourceState } from "./EmptyOpenSourceState";

export function IssuesTable() {
  const { t } = useI18n();
  const filters = useOpenSourceFiltersStore();
  const { data, isLoading } = useOssIssues({
    year: filters.year,
    org: filters.org,
    repo: filters.repo,
    state: filters.state,
  });

  if (isLoading) return <Skeleton className="h-64 w-full" />;
  if (!data || data.length === 0) return <EmptyOpenSourceState />;

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{t("openSource.tables.issues.title")}</TableHead>
          <TableHead>{t("openSource.tables.issues.repository")}</TableHead>
          <TableHead>{t("openSource.tables.issues.state")}</TableHead>
          <TableHead className="text-right">{t("openSource.tables.issues.comments")}</TableHead>
          <TableHead className="text-right">{t("openSource.tables.issues.created")}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {data.map((issue) => (
          <TableRow
            key={issue.id}
            className="cursor-pointer"
            onClick={() => openUrl(issue.url).catch(() => window.open(issue.url, "_blank"))}
          >
            <TableCell>
              <div className="flex items-center gap-2 font-medium">
                <span className="text-zinc-500">#{issue.number}</span>
                <span className="line-clamp-1">{issue.title}</span>
                <ExternalLink className="h-3 w-3 text-zinc-400" />
              </div>
            </TableCell>
            <TableCell className="text-zinc-600 dark:text-zinc-400">{issue.nameWithOwner}</TableCell>
            <TableCell>
              <Badge variant={issue.state === "OPEN" ? "success" : "secondary"}>{issue.state}</Badge>
            </TableCell>
            <TableCell className="text-right">
              <span className="inline-flex items-center gap-1 text-xs text-zinc-500">
                <MessageSquare className="h-3 w-3" />
                {issue.commentsCount}
              </span>
            </TableCell>
            <TableCell className="text-right text-xs text-zinc-500">
              {new Date(issue.createdAt).toLocaleDateString()}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
