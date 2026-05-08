import { ExternalLink, Star } from "lucide-react";
import { openUrl } from "@tauri-apps/plugin-opener";

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

export function ContributedRepositoriesTable() {
  const { t } = useI18n();
  const filters = useOpenSourceFiltersStore();
  const { data, isLoading } = useOssRepositories({
    year: filters.year,
    org: filters.org,
    repo: filters.repo,
  });

  if (isLoading) return <Skeleton className="h-64 w-full" />;
  if (!data || data.length === 0) return <EmptyOpenSourceState />;

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{t("openSource.tables.repos.name")}</TableHead>
          <TableHead>{t("openSource.tables.repos.language")}</TableHead>
          <TableHead className="text-right">{t("openSource.tables.repos.stars")}</TableHead>
          <TableHead className="text-right">{t("openSource.tables.repos.lastContribution")}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {data.map((repo) => (
          <TableRow
            key={repo.id}
            className="cursor-pointer"
            onClick={() => openUrl(repo.url).catch(() => window.open(repo.url, "_blank"))}
          >
            <TableCell>
              <div className="flex items-center gap-2 font-medium">
                {repo.nameWithOwner}
                <ExternalLink className="h-3 w-3 text-zinc-400" />
              </div>
              {repo.description ? (
                <p className="text-xs text-zinc-500 line-clamp-1">{repo.description}</p>
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
        ))}
      </TableBody>
    </Table>
  );
}
