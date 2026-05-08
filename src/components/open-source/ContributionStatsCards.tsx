import {
  Code2,
  Flame,
  FolderGit2,
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
    <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
      <StatCard
        label={t("openSource.stats.repositories")}
        value={totals.repositories}
        sub="contributed to"
        icon={FolderGit2}
        color="text-indigo-500"
        bg="bg-indigo-500/10"
      />
      <StatCard
        label={t("openSource.stats.issues")}
        value={totals.issues}
        sub="issues opened"
        icon={MessageSquare}
        color="text-amber-500"
        bg="bg-amber-500/10"
      />
      <StatCard
        label={t("openSource.stats.reviews")}
        value={totals.reviews}
        sub="reviews submitted"
        icon={Star}
        color="text-yellow-500"
        bg="bg-yellow-500/10"
      />
      <StatCard
        label={t("openSource.stats.currentStreak")}
        value={`${summary.streaks.current}d`}
        sub={`best ${summary.streaks.best}d`}
        icon={Flame}
        color="text-rose-500"
        bg="bg-rose-500/10"
      />
      <StatCard
        label={t("openSource.stats.bestStreak")}
        value={`${summary.streaks.best}d`}
        sub="longest run"
        icon={Trophy}
        color="text-emerald-500"
        bg="bg-emerald-500/10"
      />
      <StatCard
        label={t("openSource.stats.language")}
        value={summary.mostActiveLanguage ?? "—"}
        sub="top language"
        icon={Code2}
        color="text-purple-500"
        bg="bg-purple-500/10"
      />
    </div>
  );
}

export function ContributionStatsCardsSkeleton() {
  return (
    <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
      {Array.from({ length: 7 }).map((_, i) => (
        <StatCard
          key={i}
          label="—"
          value={0}
          sub="—"
          icon={Trophy}
          color="text-zinc-500"
          bg="bg-zinc-500/10"
          loading
        />
      ))}
    </div>
  );
}
