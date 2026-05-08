import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "@/components/layout/page-header";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { useI18n } from "@/i18n/i18n";
import type { ContributionSummary } from "@/types/openSource";

function formatRelative(iso: string, locale: string): string {
  const then = new Date(iso).getTime();
  const now = Date.now();
  const diffSec = Math.round((then - now) / 1000);
  const rtf = new Intl.RelativeTimeFormat(locale, { numeric: "auto" });
  const abs = Math.abs(diffSec);
  if (abs < 60) return rtf.format(diffSec, "second");
  if (abs < 3600) return rtf.format(Math.round(diffSec / 60), "minute");
  if (abs < 86400) return rtf.format(Math.round(diffSec / 3600), "hour");
  return rtf.format(Math.round(diffSec / 86400), "day");
}

import { OpenSourceSyncButton } from "./OpenSourceSyncButton";

interface OpenSourceHeaderProps {
  summary?: ContributionSummary;
}

export function OpenSourceHeader({ summary }: OpenSourceHeaderProps) {
  const { t, locale } = useI18n();

  const lastSyncedLabel = summary?.lastSyncedAt
    ? t("openSource.sync.last", { value: formatRelative(summary.lastSyncedAt, locale) })
    : t("openSource.sync.never");

  return (
    <PageHeader>
      <div className="flex items-center gap-4">
        {summary?.profile.avatarUrl ? (
          <Avatar className="h-12 w-12">
            <AvatarImage src={summary.profile.avatarUrl} alt={summary.profile.login} />
            <AvatarFallback>{summary.profile.login.slice(0, 2).toUpperCase()}</AvatarFallback>
          </Avatar>
        ) : null}
        <div>
          <PageHeaderTitle>{t("openSource.title")}</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{summary?.profile.name ?? summary?.profile.login ?? t("openSource.subtitle")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{lastSyncedLabel}</span>
          </PageHeaderMeta>
        </div>
      </div>
      <PageHeaderActions>
        <OpenSourceSyncButton />
      </PageHeaderActions>
    </PageHeader>
  );
}
