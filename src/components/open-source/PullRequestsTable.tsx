import { openUrl } from "@tauri-apps/plugin-opener";
import { ExternalLink } from "lucide-react";

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
import { useOssPullRequests } from "@/hooks/useOpenSource";
import { useOpenSourceFiltersStore } from "@/stores/useOpenSourceFiltersStore";
import type { OssPullRequest } from "@/types/openSource";

import { EmptyOpenSourceState } from "./EmptyOpenSourceState";

interface PullRequestsTableProps {
  onlyMerged?: boolean;
}

function stateVariant(pr: OssPullRequest) {
  if (pr.merged) return "default";
  if (pr.state === "OPEN") return "secondary";
  return "outline";
}

export function PullRequestsTable({ onlyMerged = false }: PullRequestsTableProps) {
  const { t } = useI18n();
  const filters = useOpenSourceFiltersStore();
  const { data, isLoading } = useOssPullRequests({
    year: filters.year,
    org: filters.org,
    repo: filters.repo,
    state: onlyMerged ? "merged" : filters.state,
  });

  if (isLoading) return <Skeleton className="h-64 w-full" />;
  if (!data || data.length === 0) return <EmptyOpenSourceState />;

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{t("openSource.tables.prs.title")}</TableHead>
          <TableHead>{t("openSource.tables.prs.repository")}</TableHead>
          <TableHead>{t("openSource.tables.prs.state")}</TableHead>
          <TableHead className="text-right">{t("openSource.tables.prs.changes")}</TableHead>
          <TableHead className="text-right">{t("openSource.tables.prs.created")}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {data.map((pr) => (
          <TableRow
            key={pr.id}
            className="cursor-pointer"
            onClick={() => openUrl(pr.url).catch(() => window.open(pr.url, "_blank"))}
          >
            <TableCell>
              <div className="flex items-center gap-2 font-medium">
                <span className="text-zinc-500">#{pr.number}</span>
                <span className="line-clamp-1">{pr.title}</span>
                <ExternalLink className="h-3 w-3 text-zinc-400" />
              </div>
            </TableCell>
            <TableCell className="text-zinc-600 dark:text-zinc-400">{pr.nameWithOwner}</TableCell>
            <TableCell>
              <Badge variant={stateVariant(pr)}>{pr.merged ? "MERGED" : pr.state}</Badge>
            </TableCell>
            <TableCell className="text-right text-xs">
              <span className="text-emerald-600">+{pr.additions}</span>{" "}
              <span className="text-rose-600">-{pr.deletions}</span>
            </TableCell>
            <TableCell className="text-right text-xs text-zinc-500">
              {new Date(pr.createdAt).toLocaleDateString()}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
