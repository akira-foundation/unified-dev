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
import { useOssReviews } from "@/hooks/useOpenSource";
import { useOpenSourceFiltersStore } from "@/stores/useOpenSourceFiltersStore";
import type { OssReviewState } from "@/types/openSource";

import { EmptyOpenSourceState } from "./EmptyOpenSourceState";

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

export function ReviewsTable() {
  const { t } = useI18n();
  const filters = useOpenSourceFiltersStore();
  const { data, isLoading } = useOssReviews({
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
          <TableHead>{t("openSource.tables.reviews.pr")}</TableHead>
          <TableHead>{t("openSource.tables.reviews.repository")}</TableHead>
          <TableHead>{t("openSource.tables.reviews.state")}</TableHead>
          <TableHead className="text-right">{t("openSource.tables.reviews.submitted")}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {data.map((review) => (
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
        ))}
      </TableBody>
    </Table>
  );
}
