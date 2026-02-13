import { RepoList } from "../components/repos/repo-list";
import type { OrganizationRepoSummary } from "../types/organization";
import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { NotificationButton } from "../components/layout/notification-button";
import { useI18n } from "../i18n/i18n";
import { useDateLabel } from "../hooks/use-date-label";

const repos: OrganizationRepoSummary[] = [];

export function RepositoryPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>{t("nav.repositories")}</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span className="text-zinc-500">{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        <PageHeaderActions>
          <NotificationButton />
        </PageHeaderActions>
      </PageHeader>
      <div className="flex flex-col gap-6">
          <RepoList repos={repos} />
      </div>
    </PageLayout>
  );
}
