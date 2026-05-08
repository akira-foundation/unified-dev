import { openUrl } from "@tauri-apps/plugin-opener";
import { CircleDot, ExternalLink, MessageSquare } from "lucide-react";
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
import { useOssIssues } from "@/hooks/useOpenSource";
import { useOpenSourceFiltersStore } from "@/stores/useOpenSourceFiltersStore";

import { EmptyOpenSourceState } from "./EmptyOpenSourceState";
import { OssOrgFilter } from "./OssOrgFilter";
import { OssTableCard } from "./OssTableCard";
import { OssTableSearch } from "./OssTableSearch";

function ownerOf(nwo: string): string {
  return nwo.split("/")[0] ?? "";
}

export function IssuesTable() {
  const { t } = useI18n();
  const filters = useOpenSourceFiltersStore();
  const [search, setSearch] = useState("");
  const [stateFilter, setStateFilter] = useState<string>("all");
  const [orgFilter, setOrgFilter] = useState<string>("all");

  const { data, isLoading } = useOssIssues({
    year: filters.year,
    org: filters.org,
    repo: filters.repo,
    state: filters.state,
  });

  const orgs = useMemo(() => {
    const set = new Set<string>();
    (data ?? []).forEach((i) => set.add(ownerOf(i.nameWithOwner)));
    return Array.from(set).sort();
  }, [data]);

  const filtered = useMemo(() => {
    if (!data) return [];
    const q = search.trim().toLowerCase();
    return data.filter((issue) => {
      if (orgFilter !== "all" && ownerOf(issue.nameWithOwner) !== orgFilter) return false;
      if (q && !issue.title.toLowerCase().includes(q) && !issue.nameWithOwner.toLowerCase().includes(q)) {
        return false;
      }
      if (stateFilter !== "all" && !issue.state.toLowerCase().includes(stateFilter)) {
        return false;
      }
      return true;
    });
  }, [data, search, stateFilter, orgFilter]);

  if (isLoading) return <Skeleton className="h-64 w-full" />;
  if (!data || data.length === 0) return <EmptyOpenSourceState />;

  return (
    <OssTableCard
      icon={CircleDot}
      title={t("openSource.tabs.issues")}
      count={`${filtered.length} ${t("openSource.tables.issues.total")}`}
      actions={
        <>
          <OssTableSearch value={search} onChange={setSearch} placeholder={t("openSource.search")} />
          <OssOrgFilter value={orgFilter} onChange={setOrgFilter} orgs={orgs} />
          <Select value={stateFilter} onValueChange={setStateFilter}>
            <SelectTrigger className="h-9 w-32 text-sm">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">{t("openSource.filters.allStates")}</SelectItem>
              <SelectItem value="open">Open</SelectItem>
              <SelectItem value="closed">Closed</SelectItem>
            </SelectContent>
          </Select>
        </>
      }
    >
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
          {filtered.length === 0 ? (
            <TableRow>
              <TableCell colSpan={5} className="py-10 text-center text-sm italic text-zinc-500">
                {t("openSource.search.empty")}
              </TableCell>
            </TableRow>
          ) : (
            filtered.map((issue) => (
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
            ))
          )}
        </TableBody>
      </Table>
    </OssTableCard>
  );
}
