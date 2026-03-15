import { PageHeader, PageHeaderMeta, PageHeaderTitle } from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { Button } from "../components/ui/button";
import { Card, CardContent, CardDescription, CardHeader } from "../components/ui/card";
import { RepoMetricsTable } from "../components/repos/repo-metrics-table";
import { useDateLabel } from "../hooks/use-date-label";
import { useOrganizations } from "../hooks/useOrganizations";
import { useNavigationStore } from "../stores/navigation-store";
import { useI18n } from "../i18n/i18n";
import { repositorySelectionService } from "../services/repositorySelectionService";
import { useEffect, useMemo, useState } from "react";
import { Activity, Download, Globe2, Lock } from "lucide-react";
import type { OrganizationRepoSummary } from "../types/organization";
import { EmptyState } from "../components/ui/empty-state";

export function OrganizationPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { organizations } = useOrganizations();
  const { activeOrganizationId, navigateTo } = useNavigationStore();
  const [repos, setRepos] = useState<OrganizationRepoSummary[]>([]);
  const [isLoadingRepos, setIsLoadingRepos] = useState(false);

  const organization = useMemo(
    () => organizations.find((item) => item.id === activeOrganizationId) ?? null,
    [organizations, activeOrganizationId],
  );

  const stats = useMemo(() => {
    const total = repos.length;
    const publicCount = repos.filter((repo) => repo.visibility === "public").length;
    const privateCount = repos.filter((repo) => repo.visibility === "private").length;
    const lastImported = repos[0]?.created_at ?? null;

    return {
      total,
      publicCount,
      privateCount,
      lastImported,
    };
  }, [repos]);

  useEffect(() => {
    if (!organization) {
      setRepos([]);
      return;
    }

    let isMounted = true;
    setIsLoadingRepos(true);
    repositorySelectionService
      .listSelectedRepositories(organization.id)
      .then((data) => {
        if (isMounted) {
          setRepos(data);
        }
      })
      .finally(() => {
        if (isMounted) {
          setIsLoadingRepos(false);
        }
      });

    return () => {
      isMounted = false;
    };
  }, [organization]);

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>
            {t("pages.organization.title")}
            {organization && (
              <span className="ml-3 text-sm font-medium text-gray-500 dark:text-gray-400">
                / {organization.name} / <span className="font-mono text-xs">{organization.id}</span>
              </span>
            )}
          </PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        {organization && (
          <Button onClick={() => navigateTo("import-repositories")}>
            <Download size={18} />
            {t("pages.organization.importRepositories")}
          </Button>
        )}
      </PageHeader>
      <div className="flex flex-col gap-6">
        {!organization && (
          <EmptyState
            title={t("pages.organization.empty.title")}
            description={t("pages.organization.empty.description")}
          />
        )}
        {organization && (
          <div className="flex flex-col gap-6">
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <Card>
                <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
                  <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
                    {t("pages.organization.stats.imported")}
                  </CardDescription>
                  <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-blue-500/10 text-blue-500">
                    <Activity size={16} />
                  </div>
                </CardHeader>
                <CardContent className="p-4 pt-4">
                  <div className="text-2xl font-black tracking-tight text-zinc-900 dark:text-white leading-none">
                    {stats.total}
                  </div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
                  <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
                    {t("pages.organization.stats.public")}
                  </CardDescription>
                  <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-emerald-500/10 text-emerald-500">
                    <Globe2 size={16} />
                  </div>
                </CardHeader>
                <CardContent className="p-4 pt-4">
                  <div className="text-2xl font-black tracking-tight text-zinc-900 dark:text-white leading-none">
                    {stats.publicCount}
                  </div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
                  <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
                    {t("pages.organization.stats.private")}
                  </CardDescription>
                  <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-amber-500/10 text-amber-500">
                    <Lock size={16} />
                  </div>
                </CardHeader>
                <CardContent className="p-4 pt-4">
                  <div className="text-2xl font-black tracking-tight text-zinc-900 dark:text-white leading-none">
                    {stats.privateCount}
                  </div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
                  <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
                    {t("pages.organization.stats.lastImport")}
                  </CardDescription>
                  <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-purple-500/10 text-purple-500">
                    <Activity size={16} />
                  </div>
                </CardHeader>
                <CardContent className="p-4 pt-4">
                  <div className="text-md font-semibold text-zinc-900 dark:text-white">
                    {stats.lastImported ? new Date(stats.lastImported).toLocaleString() : "—"}
                  </div>
                </CardContent>
              </Card>
            </div>
            {!isLoadingRepos && repos.length > 0 && <RepoMetricsTable repos={repos} />}

          </div>
        )}
      </div>
    </PageLayout>
  );
}
