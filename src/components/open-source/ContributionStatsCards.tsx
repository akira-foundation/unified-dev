import {
  BookOpen,
  Building2,
  Calendar,
  Code2,
  Flame,
  GitMerge,
  GitPullRequest,
  History,
  MessageSquare,
  Star,
  Trophy,
} from "lucide-react";

import { useI18n } from "@/i18n/i18n";
import type { ContributionSummary } from "@/types/openSource";

import { StatCard } from "./StatCard";

interface ContributionStatsCardsProps {
  summary: ContributionSummary;
}

export function ContributionStatsCards({ summary }: ContributionStatsCardsProps) {
  const { t } = useI18n();
  const totals = summary.totals;

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
      <StatCard
        label={t("openSource.stats.repositories")}
        value={totals.repositories.toLocaleString()}
        icon={BookOpen}
      />
      <StatCard
        label={t("openSource.stats.pullRequests")}
        value={totals.pullRequests.toLocaleString()}
        icon={GitPullRequest}
      />
      <StatCard
        label={t("openSource.stats.mergedPullRequests")}
        value={totals.mergedPullRequests.toLocaleString()}
        icon={GitMerge}
      />
      <StatCard
        label={t("openSource.stats.commits")}
        value={totals.commits.toLocaleString()}
        icon={History}
      />
      <StatCard
        label={t("openSource.stats.issues")}
        value={totals.issues.toLocaleString()}
        icon={MessageSquare}
      />
      <StatCard
        label={t("openSource.stats.reviews")}
        value={totals.reviews.toLocaleString()}
        icon={Star}
      />
      <StatCard
        label={t("openSource.stats.organizations")}
        value={totals.organizations.toLocaleString()}
        icon={Building2}
      />
      <StatCard
        label={t("openSource.stats.currentStreak")}
        value={`${summary.streaks.current}d`}
        icon={Flame}
        hint={t("openSource.stats.bestStreak") + `: ${summary.streaks.best}d`}
      />
      <StatCard
        label={t("openSource.stats.bestStreak")}
        value={`${summary.streaks.best}d`}
        icon={Trophy}
      />
      <StatCard
        label={t("openSource.stats.language")}
        value={summary.mostActiveLanguage ?? "—"}
        icon={Code2}
      />
      <StatCard
        label={t("openSource.stats.topRepo")}
        value={summary.mostActiveRepo ?? "—"}
        icon={Calendar}
      />
    </div>
  );
}
