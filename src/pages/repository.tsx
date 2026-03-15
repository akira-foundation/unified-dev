import { Plus } from "lucide-react";
import { useEffect, useState } from "react";

import { RepoMetricsTable } from "../components/repos/repo-metrics-table";
import { EmptyState } from "../components/ui/empty-state";
import type { OrganizationRepoSummary } from "../types/organization";
import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { useI18n } from "../i18n/i18n";
import { useDateLabel } from "../hooks/use-date-label";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "../components/ui/skeleton";
import { repositorySelectionService } from "../services/repositorySelectionService";
import { useNavigationStore } from "../stores/navigation-store";

export function RepositoryPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { activeOrganizationId } = useNavigationStore();
  const [repos, setRepos] = useState<OrganizationRepoSummary[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    if (!activeOrganizationId) {
      setRepos([]);
      return;
    }

    let isMounted = true;
    setIsLoading(true);
    repositorySelectionService
      .listSelectedRepositories(activeOrganizationId)
      .then((data) => {
        if (isMounted) {
          setRepos(data);
        }
      })
      .finally(() => {
        if (isMounted) {
          setIsLoading(false);
        }
      });

    return () => {
      isMounted = false;
    };
  }, [activeOrganizationId]);

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>{t("nav.repositories")}</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        <PageHeaderActions>
          <Button>
            <Plus size={18} />
            {t("dashboard.quick.newRepo")}
          </Button>
        </PageHeaderActions>
      </PageHeader>
      <div className="flex flex-col gap-6">
        {isLoading ? (
          <div className="space-y-3">
            <Skeleton className="h-24 w-full" />
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
          </div>
        ) : repos.length === 0 ? (
          <EmptyState
            title={t("pages.repository.empty.title")}
            description={t("pages.repository.empty.description")}
          />
        ) : (
          <RepoMetricsTable repos={repos} />
        )}
      </div>
    </PageLayout>
  );
}
