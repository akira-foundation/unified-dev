import { ExternalLink, FolderGit2, Star } from "lucide-react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { useMemo, useState } from "react";

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
import { useOssRepositories } from "@/hooks/useOpenSource";
import { useOpenSourceFiltersStore } from "@/stores/useOpenSourceFiltersStore";

import { EmptyOpenSourceState } from "./EmptyOpenSourceState";
import { OssOrgFilter } from "./OssOrgFilter";
import { OssTableCard } from "./OssTableCard";
import { OssTableSearch } from "./OssTableSearch";

export function ContributedRepositoriesTable() {
  const { t } = useI18n();
  const filters = useOpenSourceFiltersStore();
  const [search, setSearch] = useState("");
  const [orgFilter, setOrgFilter] = useState<string>("all");
  const { data, isLoading } = useOssRepositories({
    year: filters.year,
    org: filters.org,
    repo: filters.repo,
  });

  const orgs = useMemo(() => {
    const set = new Set<string>();
    (data ?? []).forEach((r) => set.add(r.ownerLogin));
    return Array.from(set).sort();
  }, [data]);

  const filtered = useMemo(() => {
    if (!data) return [];
    const q = search.trim().toLowerCase();
    return data.filter((r) => {
      if (orgFilter !== "all" && r.ownerLogin !== orgFilter) return false;
      if (!q) return true;
      return (
        r.nameWithOwner.toLowerCase().includes(q) ||
        (r.description ?? "").toLowerCase().includes(q) ||
        (r.primaryLanguage ?? "").toLowerCase().includes(q)
      );
    });
  }, [data, search, orgFilter]);

  if (isLoading) return <Skeleton className="h-64 w-full" />;
  if (!data || data.length === 0) return <EmptyOpenSourceState />;

  return (
    <OssTableCard
      icon={FolderGit2}
      title={t("openSource.tabs.repos")}
      count={`${filtered.length} ${t("openSource.tables.repos.total")}`}
      actions={
        <>
          <OssTableSearch value={search} onChange={setSearch} placeholder={t("openSource.search")} />
          <OssOrgFilter value={orgFilter} onChange={setOrgFilter} orgs={orgs} />
        </>
      }
    >
      <Table className="table-fixed">
        <TableHeader>
          <TableRow>
            <TableHead className="w-1/2">{t("openSource.tables.repos.name")}</TableHead>
            <TableHead className="w-32">{t("openSource.tables.repos.language")}</TableHead>
            <TableHead className="w-24 text-right">{t("openSource.tables.repos.stars")}</TableHead>
            <TableHead className="w-40 text-right">{t("openSource.tables.repos.lastContribution")}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {filtered.length === 0 ? (
            <TableRow>
              <TableCell colSpan={4} className="py-10 text-center text-sm italic text-zinc-500">
                {t("openSource.search.empty")}
              </TableCell>
            </TableRow>
          ) : (
            filtered.map((repo) => (
              <TableRow
                key={repo.id}
                className="cursor-pointer"
                onClick={() => openUrl(repo.url).catch(() => window.open(repo.url, "_blank"))}
              >
                <TableCell className="max-w-0">
                  <div className="flex items-center gap-2 font-medium">
                    <span className="truncate">{repo.nameWithOwner}</span>
                    <ExternalLink className="h-3 w-3 shrink-0 text-zinc-400" />
                  </div>
                  {repo.description ? (
                    <p className="truncate text-xs text-zinc-500">{repo.description}</p>
                  ) : null}
                </TableCell>
                <TableCell className="text-zinc-600 dark:text-zinc-400">
                  {repo.primaryLanguage ?? "—"}
                </TableCell>
                <TableCell className="text-right">
                  <span className="inline-flex items-center gap-1 text-zinc-600 dark:text-zinc-400">
                    <Star className="h-3 w-3" />
                    {repo.stars.toLocaleString()}
                  </span>
                </TableCell>
                <TableCell className="text-right text-xs text-zinc-500">
                  {repo.lastContributionAt ? new Date(repo.lastContributionAt).toLocaleDateString() : "—"}
                </TableCell>
              </TableRow>
            ))
          )}
        </TableBody>
      </Table>
    </OssTableCard>
  );
}
