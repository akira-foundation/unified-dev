import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "@/components/layout/page-header";
import { useI18n } from "@/i18n/i18n";
import { useDateLabel } from "@/hooks/use-date-label";
import type { ContributionSummary } from "@/types/openSource";

import { OpenSourceSyncButton } from "./OpenSourceSyncButton";

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

interface OpenSourceHeaderProps {
  summary?: ContributionSummary;
}

export function OpenSourceHeader({ summary }: OpenSourceHeaderProps) {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);

  const lastSyncedLabel = summary?.lastSyncedAt
    ? t("openSource.sync.last", { value: formatRelative(summary.lastSyncedAt, locale) })
    : t("openSource.sync.never");

  return (
    <PageHeader>
      <div>
        <PageHeaderTitle>{t("openSource.title")}</PageHeaderTitle>
        <PageHeaderMeta>
          <span>{t("app.name")}</span>
          <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
          <span>{dateLabel}</span>
          <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
          <span>{lastSyncedLabel}</span>
        </PageHeaderMeta>
      </div>
      <PageHeaderActions>
        <OpenSourceSyncButton />
      </PageHeaderActions>
    </PageHeader>
  );
}
