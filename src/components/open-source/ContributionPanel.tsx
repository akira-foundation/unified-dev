import { BookOpen } from "lucide-react";
import { useMemo } from "react";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Card, CardContent } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import { useI18n } from "@/i18n/i18n";
import { useOssCalendar, useOssYearOverview } from "@/hooks/useOpenSource";
import type { ContributionSummary } from "@/types/openSource";

import { ActivityRadarChart } from "./ActivityRadarChart";
import { ContributionCalendar, ContributionLegend } from "./ContributionCalendar";
import { YearSelector } from "./YearSelector";

interface ContributionPanelProps {
  summary: ContributionSummary;
  year: number;
  years: number[];
  onYearChange: (year: number) => void;
}

export function ContributionPanel({ summary: _summary, year, years, onYearChange }: ContributionPanelProps) {
  const { t } = useI18n();
  const { data: calendar } = useOssCalendar(year);
  const overview = useOssYearOverview(year);

  const total = useMemo(
    () => (calendar ?? []).reduce((s, d) => s + d.count, 0),
    [calendar],
  );

  const remaining = overview.data
    ? Math.max(0, overview.data.reposTotal - overview.data.reposPreview.length)
    : 0;

  const orgs = overview.data?.organizations ?? [];
  const repos = overview.data?.reposPreview ?? [];
  const breakdown = overview.data?.breakdown ?? {
    commits: 0,
    pullRequests: 0,
    issues: 0,
    codeReview: 0,
  };

  return (
    <div className="flex gap-6">
      <Card className="flex-1">
        <CardContent className="p-6 space-y-6">
          <div className="flex items-center justify-between">
            <h3 className="text-base font-semibold text-zinc-900 dark:text-zinc-100">
              {t("openSource.calendar.contributionsIn", {
                count: total.toLocaleString(),
                year: String(year),
              })}
            </h3>
            <ContributionLegend />
          </div>

          <ContributionCalendar year={year} />

          <Separator className="bg-zinc-100 dark:bg-zinc-800/60" />

          {overview.isLoading ? (
            <Skeleton className="h-7 w-72" />
          ) : orgs.length > 0 ? (
            <div className="flex flex-wrap items-center gap-2">
              {orgs.map((org) => (
                <a
                  key={org.login}
                  href={org.url}
                  target="_blank"
                  rel="noreferrer"
                  className="flex items-center gap-2 rounded-full border border-zinc-200 bg-zinc-50 px-2 py-1 text-xs font-semibold text-zinc-700 transition-colors hover:bg-zinc-100 dark:border-zinc-800 dark:bg-zinc-900/40 dark:text-zinc-200 dark:hover:bg-zinc-800/60"
                >
                  <Avatar className="h-5 w-5">
                    <AvatarImage src={org.avatarUrl ?? undefined} alt={org.login} />
                    <AvatarFallback className="text-[8px]">
                      {org.login.slice(0, 2).toUpperCase()}
                    </AvatarFallback>
                  </Avatar>
                  @{org.login}
                </a>
              ))}
            </div>
          ) : null}

          <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
            <div>
              <div className="mb-3 flex items-center gap-2 text-sm font-semibold text-zinc-700 dark:text-zinc-300">
                <BookOpen size={14} className="text-indigo-500" />
                {t("openSource.activity.title")}
              </div>
              {overview.isLoading ? (
                <Skeleton className="h-20 w-full" />
              ) : repos.length === 0 ? (
                <div className="flex flex-col items-start gap-2 rounded-lg border border-dashed border-zinc-200 bg-zinc-50/50 p-4 dark:border-zinc-800 dark:bg-zinc-900/30">
                  <div className="flex h-8 w-8 items-center justify-center rounded-md border border-zinc-100 dark:border-zinc-800 bg-zinc-100 text-zinc-400 dark:bg-zinc-800/60 dark:text-zinc-500">
                    <BookOpen size={14} />
                  </div>
                  <span className="text-sm font-semibold text-zinc-700 dark:text-zinc-200">
                    {t("openSource.activity.noRepos")}
                  </span>
                  <span className="text-xs text-zinc-500 dark:text-zinc-400">
                    {t("openSource.activity.noReposHint")}
                  </span>
                </div>
              ) : (
                <p className="text-sm leading-relaxed text-zinc-600 dark:text-zinc-300">
                  Contributed to{" "}
                  {repos.map((repo, i) => (
                    <span key={repo}>
                      <a
                        href={`https://github.com/${repo}`}
                        target="_blank"
                        rel="noreferrer"
                        className="font-medium text-purple-600 hover:underline dark:text-purple-400"
                      >
                        {repo}
                      </a>
                      {i < repos.length - 1 ? ", " : ""}
                    </span>
                  ))}
                  {remaining > 0 ? (
                    <span className="text-zinc-500"> and {remaining} other repositories</span>
                  ) : null}
                </p>
              )}
            </div>

            <div className="flex items-center justify-center">
              {overview.isLoading ? (
                <Skeleton className="h-48 w-48 rounded-full" />
              ) : (
                <ActivityRadarChart breakdown={breakdown} />
              )}
            </div>
          </div>
        </CardContent>
      </Card>

      {years.length > 0 ? (
        <YearSelector years={years} value={year} onChange={onYearChange} />
      ) : null}
    </div>
  );
}
