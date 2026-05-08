import { GitPullRequest, MessageSquare, Star } from "lucide-react";
import { useMemo } from "react";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { useI18n } from "@/i18n/i18n";
import { useOssIssues, useOssPullRequests, useOssReviews } from "@/hooks/useOpenSource";
import { useOpenSourceFiltersStore } from "@/stores/useOpenSourceFiltersStore";

interface TimelineEntry {
  id: string;
  date: string;
  kind: "pr" | "issue" | "review";
  title: string;
  repo: string;
  url: string;
}

export function ContributionTimeline() {
  const { t } = useI18n();
  const filters = useOpenSourceFiltersStore();
  const filterArgs = { year: filters.year, org: filters.org, repo: filters.repo };
  const prsQuery = useOssPullRequests(filterArgs);
  const issuesQuery = useOssIssues(filterArgs);
  const reviewsQuery = useOssReviews(filterArgs);

  const isLoading = prsQuery.isLoading || issuesQuery.isLoading || reviewsQuery.isLoading;

  const entries = useMemo<TimelineEntry[]>(() => {
    const items: TimelineEntry[] = [];
    for (const pr of prsQuery.data ?? []) {
      items.push({
        id: `pr-${pr.id}`,
        date: pr.mergedAt ?? pr.createdAt,
        kind: "pr",
        title: `#${pr.number} ${pr.title}`,
        repo: pr.nameWithOwner,
        url: pr.url,
      });
    }
    for (const issue of issuesQuery.data ?? []) {
      items.push({
        id: `issue-${issue.id}`,
        date: issue.createdAt,
        kind: "issue",
        title: `#${issue.number} ${issue.title}`,
        repo: issue.nameWithOwner,
        url: issue.url,
      });
    }
    for (const review of reviewsQuery.data ?? []) {
      items.push({
        id: `review-${review.id}`,
        date: review.submittedAt,
        kind: "review",
        title: `#${review.prNumber} ${review.prTitle ?? ""}`,
        repo: review.nameWithOwner,
        url: review.url,
      });
    }
    return items.sort((a, b) => b.date.localeCompare(a.date)).slice(0, 20);
  }, [prsQuery.data, issuesQuery.data, reviewsQuery.data]);

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm font-semibold">{t("openSource.timeline.title")}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3 p-4">
        {isLoading ? (
          <Skeleton className="h-32 w-full" />
        ) : entries.length === 0 ? (
          <p className="text-sm text-zinc-500">—</p>
        ) : (
          <ul className="space-y-3">
            {entries.map((entry) => (
              <li key={entry.id} className="flex items-start gap-3">
                <div className="mt-0.5 flex h-6 w-6 items-center justify-center rounded-full bg-purple-500/10 text-purple-600 dark:text-purple-400">
                  {entry.kind === "pr" ? (
                    <GitPullRequest className="h-3 w-3" />
                  ) : entry.kind === "issue" ? (
                    <MessageSquare className="h-3 w-3" />
                  ) : (
                    <Star className="h-3 w-3" />
                  )}
                </div>
                <div className="min-w-0 flex-1">
                  <a
                    href={entry.url}
                    target="_blank"
                    rel="noreferrer"
                    className="block truncate text-sm font-medium hover:underline"
                  >
                    {entry.title}
                  </a>
                  <div className="flex items-center gap-2 text-xs text-zinc-500">
                    <span>{entry.repo}</span>
                    <span>•</span>
                    <span>{new Date(entry.date).toLocaleDateString()}</span>
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
