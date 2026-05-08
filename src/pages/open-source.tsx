import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { PageLayout } from "@/components/layout/page-layout";
import { ContributedRepositoriesTable } from "@/components/open-source/ContributedRepositoriesTable";
import { ContributionCalendar } from "@/components/open-source/ContributionCalendar";
import { ContributionStatsCards } from "@/components/open-source/ContributionStatsCards";
import { ContributionTimeline } from "@/components/open-source/ContributionTimeline";
import { GithubNotConnectedState } from "@/components/open-source/GithubNotConnectedState";
import { GithubRateLimitedState } from "@/components/open-source/GithubRateLimitedState";
import { IssuesTable } from "@/components/open-source/IssuesTable";
import { OpenSourceFilters } from "@/components/open-source/OpenSourceFilters";
import { OpenSourceHeader } from "@/components/open-source/OpenSourceHeader";
import { PullRequestsTable } from "@/components/open-source/PullRequestsTable";
import { ReviewsTable } from "@/components/open-source/ReviewsTable";
import { useI18n } from "@/i18n/i18n";
import { useOssSummary } from "@/hooks/useOpenSource";

function detectErrorKind(error: unknown): "not_connected" | "rate_limited" | null {
  if (!error) return null;
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes("github_not_connected")) return "not_connected";
  if (message.includes("github_rate_limited") || message.includes("rate limit")) return "rate_limited";
  return null;
}

export function OpenSourcePage() {
  const { t } = useI18n();
  const { data: summary, isLoading, error } = useOssSummary();

  const errorKind = detectErrorKind(error);
  if (errorKind === "not_connected") return <GithubNotConnectedState />;
  if (errorKind === "rate_limited") return <GithubRateLimitedState />;

  return (
    <PageLayout>
      <OpenSourceHeader summary={summary} />

      <div className="flex items-center justify-between">
        <OpenSourceFilters />
      </div>

      {isLoading || !summary ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {Array.from({ length: 8 }).map((_, i) => (
            <Skeleton key={i} className="h-24 w-full" />
          ))}
        </div>
      ) : (
        <ContributionStatsCards summary={summary} />
      )}

      <ContributionCalendar />

      <Tabs defaultValue="overview" className="w-full">
        <TabsList>
          <TabsTrigger value="overview">{t("openSource.tabs.overview")}</TabsTrigger>
          <TabsTrigger value="repos">{t("openSource.tabs.repos")}</TabsTrigger>
          <TabsTrigger value="prs">{t("openSource.tabs.prs")}</TabsTrigger>
          <TabsTrigger value="merged">{t("openSource.tabs.merged")}</TabsTrigger>
          <TabsTrigger value="issues">{t("openSource.tabs.issues")}</TabsTrigger>
          <TabsTrigger value="reviews">{t("openSource.tabs.reviews")}</TabsTrigger>
        </TabsList>
        <TabsContent value="overview">
          <ContributionTimeline />
        </TabsContent>
        <TabsContent value="repos">
          <ContributedRepositoriesTable />
        </TabsContent>
        <TabsContent value="prs">
          <PullRequestsTable />
        </TabsContent>
        <TabsContent value="merged">
          <PullRequestsTable onlyMerged />
        </TabsContent>
        <TabsContent value="issues">
          <IssuesTable />
        </TabsContent>
        <TabsContent value="reviews">
          <ReviewsTable />
        </TabsContent>
      </Tabs>
    </PageLayout>
  );
}
