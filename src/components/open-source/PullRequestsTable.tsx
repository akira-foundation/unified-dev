import { openUrl } from "@tauri-apps/plugin-opener";
import { ExternalLink, GitMerge, GitPullRequest } from "lucide-react";
import { useMemo, useState } from "react";

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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useI18n } from "@/i18n/i18n";
import { useOssPullRequests } from "@/hooks/useOpenSource";
import { useOpenSourceFiltersStore } from "@/stores/useOpenSourceFiltersStore";
import type { OssPullRequest } from "@/types/openSource";

import { EmptyOpenSourceState } from "./EmptyOpenSourceState";
import { OssOrgFilter } from "./OssOrgFilter";
import { OssTableCard } from "./OssTableCard";
import { OssTableSearch } from "./OssTableSearch";

interface PullRequestsTableProps {
  onlyMerged?: boolean;
}

function stateVariant(pr: OssPullRequest) {
  if (pr.merged) return "default";
  if (pr.state === "OPEN") return "secondary";
  return "outline";
}

function ownerOf(nwo: string): string {
  return nwo.split("/")[0] ?? "";
}

export function PullRequestsTable({ onlyMerged = false }: PullRequestsTableProps) {
  const { t } = useI18n();
  const filters = useOpenSourceFiltersStore();
  const [search, setSearch] = useState("");
  const [stateFilter, setStateFilter] = useState<string>("all");
  const [orgFilter, setOrgFilter] = useState<string>("all");

  const { data, isLoading } = useOssPullRequests({
    year: filters.year,
    org: filters.org,
    repo: filters.repo,
    state: onlyMerged ? "merged" : filters.state,
  });

  const orgs = useMemo(() => {
    const set = new Set<string>();
    (data ?? []).forEach((pr) => set.add(ownerOf(pr.nameWithOwner)));
    return Array.from(set).sort();
  }, [data]);

  const filtered = useMemo(() => {
    if (!data) return [];
    const q = search.trim().toLowerCase();
    return data.filter((pr) => {
      if (orgFilter !== "all" && ownerOf(pr.nameWithOwner) !== orgFilter) return false;
      if (q && !pr.title.toLowerCase().includes(q) && !pr.nameWithOwner.toLowerCase().includes(q)) {
        return false;
      }
      if (!onlyMerged && stateFilter !== "all") {
        if (stateFilter === "merged") return pr.merged;
        if (stateFilter === "open") return pr.state === "OPEN";
        if (stateFilter === "closed") return pr.state === "CLOSED" && !pr.merged;
      }
      return true;
    });
  }, [data, search, stateFilter, orgFilter, onlyMerged]);

  if (isLoading) return <Skeleton className="h-64 w-full" />;
  if (!data || data.length === 0) return <EmptyOpenSourceState />;

  return (
    <OssTableCard
      icon={onlyMerged ? GitMerge : GitPullRequest}
      title={onlyMerged ? t("openSource.tabs.merged") : t("openSource.tabs.prs")}
      count={`${filtered.length} ${t("openSource.tables.prs.total")}`}
      actions={
        <>
          <OssTableSearch value={search} onChange={setSearch} placeholder={t("openSource.search")} />
          <OssOrgFilter value={orgFilter} onChange={setOrgFilter} orgs={orgs} />
          {!onlyMerged ? (
            <Select value={stateFilter} onValueChange={setStateFilter}>
              <SelectTrigger className="h-9 w-32 text-sm">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">{t("openSource.filters.allStates")}</SelectItem>
                <SelectItem value="open">Open</SelectItem>
                <SelectItem value="merged">Merged</SelectItem>
                <SelectItem value="closed">Closed</SelectItem>
              </SelectContent>
            </Select>
          ) : null}
        </>
      }
    >
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
          {filtered.length === 0 ? (
            <TableRow>
              <TableCell colSpan={5} className="py-10 text-center text-sm italic text-zinc-500">
                {t("openSource.search.empty")}
              </TableCell>
            </TableRow>
          ) : (
            filtered.map((pr) => (
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
            ))
          )}
        </TableBody>
      </Table>
    </OssTableCard>
  );
}
