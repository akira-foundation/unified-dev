import { Github, Loader2 } from "lucide-react";
import { useQueryClient } from "@tanstack/react-query";

import { PageLayout } from "@/components/layout/page-layout";
import { ContributedRepositoriesTable } from "@/components/open-source/ContributedRepositoriesTable";
import { ContributionPanel } from "@/components/open-source/ContributionPanel";
import {
  ContributionStatsCards,
  ContributionStatsCardsSkeleton,
} from "@/components/open-source/ContributionStatsCards";
import { GithubAppNoUserTokenState } from "@/components/open-source/GithubAppNoUserTokenState";
import { GithubNotConnectedState } from "@/components/open-source/GithubNotConnectedState";
import { GithubRateLimitedState } from "@/components/open-source/GithubRateLimitedState";
import { OpenSourceHeader } from "@/components/open-source/OpenSourceHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { useI18n } from "@/i18n/i18n";
import { useOssAutoSync, useOssSummary, useOssSync } from "@/hooks/useOpenSource";
import { useProviders } from "@/hooks/useProviders";
import { queryKeys } from "@/lib/query-keys";
import { providerService } from "@/services/providerService";
import { useOpenSourceFiltersStore } from "@/stores/useOpenSourceFiltersStore";

function detectErrorKind(
  error: unknown,
): "not_connected" | "rate_limited" | "not_synced" | "app_no_user_token" | null {
  if (!error) return null;
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes("github_app_no_user_token")) return "app_no_user_token";
  if (message.includes("github_not_connected")) return "not_connected";
  if (message.includes("github_not_synced")) return "not_synced";
  if (message.includes("github_rate_limited") || message.includes("rate limit")) return "rate_limited";
  return null;
}

function FirstSyncState() {
  const { t } = useI18n();
  const sync = useOssSync();

  return (
    <Card>
      <CardContent className="flex flex-col items-center justify-center gap-4 p-12 text-center">
        <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-zinc-900/5 text-zinc-700 dark:bg-zinc-50/10 dark:text-zinc-200">
          <Github className="h-6 w-6" />
        </div>
        <div className="flex flex-col gap-1">
          <span className="text-base font-semibold">{t("openSource.firstSync.title")}</span>
          <span className="max-w-md text-sm text-zinc-500 dark:text-zinc-400">
            {t("openSource.firstSync.description")}
          </span>
        </div>
        <Button onClick={() => sync.mutate()} disabled={sync.isPending}>
          {sync.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
          {sync.isPending ? t("openSource.sync.inProgress") : t("openSource.sync.now")}
        </Button>
      </CardContent>
    </Card>
  );
}

export function OpenSourcePage() {
  const { data: summary, isLoading, error } = useOssSummary();
  const filterYear = useOpenSourceFiltersStore((s) => s.year);
  const setYear = useOpenSourceFiltersStore((s) => s.setYear);
  const { providers } = useProviders();
  const queryClient = useQueryClient();

  useOssAutoSync(summary?.lastSyncedAt, summary?.connected ?? false);

  const errorKind = detectErrorKind(error);
  if (errorKind === "app_no_user_token") {
    const githubProvider = providers.find((p) => p.kind === "github");
    const handleReconnect = githubProvider
      ? async () => {
          await providerService.reconnectGithub(githubProvider.id);
          await queryClient.invalidateQueries({ queryKey: queryKeys.ossSummary() });
        }
      : undefined;
    return (
      <PageLayout className="items-center justify-center">
        <GithubAppNoUserTokenState onReconnect={handleReconnect} />
      </PageLayout>
    );
  }
  if (errorKind === "not_connected")
    return (
      <PageLayout className="items-center justify-center">
        <GithubNotConnectedState />
      </PageLayout>
    );
  if (errorKind === "rate_limited")
    return (
      <PageLayout className="items-center justify-center">
        <GithubRateLimitedState />
      </PageLayout>
    );
  if (errorKind === "not_synced")
    return (
      <PageLayout className="items-center justify-center">
        <FirstSyncState />
      </PageLayout>
    );

  const calendarYear = filterYear ?? new Date().getFullYear();

  return (
    <PageLayout>
      <OpenSourceHeader summary={summary} />

      <div className="flex flex-col gap-10 px-4 pb-10 md:px-6">
        {isLoading || !summary ? (
          <ContributionStatsCardsSkeleton />
        ) : (
          <ContributionStatsCards summary={summary} />
        )}

        {summary ? (
          <ContributionPanel
            summary={summary}
            year={calendarYear}
            years={summary.years}
            onYearChange={setYear}
          />
        ) : (
          <Skeleton className="h-72 w-full" />
        )}

        <ContributedRepositoriesTable />
      </div>
    </PageLayout>
  );
}
