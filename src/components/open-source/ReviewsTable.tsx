import { openUrl } from "@tauri-apps/plugin-opener";
import { ExternalLink, Star } from "lucide-react";
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
import { useOssReviews } from "@/hooks/useOpenSource";
import { useOpenSourceFiltersStore } from "@/stores/useOpenSourceFiltersStore";
import type { OssReviewState } from "@/types/openSource";

import { EmptyOpenSourceState } from "./EmptyOpenSourceState";
import { OssOrgFilter } from "./OssOrgFilter";
import { OssTableCard } from "./OssTableCard";
import { OssTableSearch } from "./OssTableSearch";

function reviewVariant(state: OssReviewState) {
  switch (state) {
    case "APPROVED":
      return "success" as const;
    case "CHANGES_REQUESTED":
      return "warning" as const;
    case "DISMISSED":
      return "outline" as const;
    default:
      return "secondary" as const;
  }
}

function ownerOf(nwo: string): string {
  return nwo.split("/")[0] ?? "";
}

export function ReviewsTable() {
  const { t } = useI18n();
  const filters = useOpenSourceFiltersStore();
  const [search, setSearch] = useState("");
  const [stateFilter, setStateFilter] = useState<string>("all");
  const [orgFilter, setOrgFilter] = useState<string>("all");

  const { data, isLoading } = useOssReviews({
    year: filters.year,
    org: filters.org,
    repo: filters.repo,
    state: filters.state,
  });

  const orgs = useMemo(() => {
    const set = new Set<string>();
    (data ?? []).forEach((r) => set.add(ownerOf(r.nameWithOwner)));
    return Array.from(set).sort();
  }, [data]);

  const filtered = useMemo(() => {
    if (!data) return [];
    const q = search.trim().toLowerCase();
    return data.filter((review) => {
      if (orgFilter !== "all" && ownerOf(review.nameWithOwner) !== orgFilter) return false;
      if (q && !review.nameWithOwner.toLowerCase().includes(q) && !(review.prTitle ?? "").toLowerCase().includes(q)) {
        return false;
      }
      if (stateFilter !== "all" && !review.state.toLowerCase().includes(stateFilter)) {
        return false;
      }
      return true;
    });
  }, [data, search, stateFilter, orgFilter]);

  if (isLoading) return <Skeleton className="h-64 w-full" />;
  if (!data || data.length === 0) return <EmptyOpenSourceState />;

  return (
    <OssTableCard
      icon={Star}
      title={t("openSource.tabs.reviews")}
      count={`${filtered.length} ${t("openSource.tables.reviews.total")}`}
      actions={
        <>
          <OssTableSearch value={search} onChange={setSearch} placeholder={t("openSource.search")} />
          <OssOrgFilter value={orgFilter} onChange={setOrgFilter} orgs={orgs} />
          <Select value={stateFilter} onValueChange={setStateFilter}>
            <SelectTrigger className="h-9 w-40 text-sm">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">{t("openSource.filters.allStates")}</SelectItem>
              <SelectItem value="approved">Approved</SelectItem>
              <SelectItem value="changes">Changes requested</SelectItem>
              <SelectItem value="commented">Commented</SelectItem>
              <SelectItem value="dismissed">Dismissed</SelectItem>
            </SelectContent>
          </Select>
        </>
      }
    >
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t("openSource.tables.reviews.pr")}</TableHead>
            <TableHead>{t("openSource.tables.reviews.repository")}</TableHead>
            <TableHead>{t("openSource.tables.reviews.state")}</TableHead>
            <TableHead className="text-right">{t("openSource.tables.reviews.submitted")}</TableHead>
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
            filtered.map((review) => (
              <TableRow
                key={review.id}
                className="cursor-pointer"
                onClick={() => openUrl(review.url).catch(() => window.open(review.url, "_blank"))}
              >
                <TableCell>
                  <div className="flex items-center gap-2 font-medium">
                    <span className="text-zinc-500">#{review.prNumber}</span>
                    <span className="line-clamp-1">{review.prTitle ?? "—"}</span>
                    <ExternalLink className="h-3 w-3 text-zinc-400" />
                  </div>
                </TableCell>
                <TableCell className="text-zinc-600 dark:text-zinc-400">{review.nameWithOwner}</TableCell>
                <TableCell>
                  <Badge variant={reviewVariant(review.state)}>{review.state}</Badge>
                </TableCell>
                <TableCell className="text-right text-xs text-zinc-500">
                  {new Date(review.submittedAt).toLocaleDateString()}
                </TableCell>
              </TableRow>
            ))
          )}
        </TableBody>
      </Table>
    </OssTableCard>
  );
}
