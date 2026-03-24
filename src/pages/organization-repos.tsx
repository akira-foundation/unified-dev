import { useMemo } from "react";
import { EmptyState } from "../components/ui/empty-state";

import { OrganizationList } from "../components/organizations/organization-list";
import { RepoSelectionTable } from "../components/organizations/repo-selection-table";
import { PageHeader, PageHeaderMeta, PageHeaderTitle } from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { Button } from "../components/ui/button";
import { Card, CardContent } from "../components/ui/card";
import { useDateLabel } from "../hooks/use-date-label";
import { useOrganizationRepoSelection } from "../hooks/use-organization-repo-selection";
import { useOrganizations } from "../hooks/useOrganizations";
import { useNavigationStore } from "../stores/navigation-store";
import { useI18n } from "../i18n/i18n";

export function OrganizationReposPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { organizations, isLoading: organizationsLoading, removeOrganization } = useOrganizations();
  const { activeOrganizationId, setActiveOrganizationId } = useNavigationStore();

  const activeOrganization = useMemo(
    () => organizations.find((org) => org.id === activeOrganizationId) ?? null,
    [organizations, activeOrganizationId],
  );

  const {
    repos,
    selectedKeys,
    isLoading,
    isSaving,
    setSelectedKeys,
    saveSelection,
  } = useOrganizationRepoSelection(activeOrganizationId);

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>{t("repositories.selectTitle") ?? "Select repositories"}</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
      </PageHeader>
      <div className="grid gap-6 lg:grid-cols-[280px_1fr]">
        <div className="flex flex-col gap-4">
          <OrganizationList
            organizations={organizations}
            onRemove={removeOrganization}
            activeId={activeOrganizationId}
            onSelect={setActiveOrganizationId}
          />
          {organizationsLoading && (
            <Card>
              <CardContent className="p-4 text-sm text-gray-500 dark:text-gray-400">{t("pages.organizationRepos.loadingOrgs")}</CardContent>
            </Card>
          )}
        </div>
        <div className="flex flex-col gap-4">
          {!activeOrganizationId && (
            <EmptyState
              title={t("pages.organizationRepos.selectOrg.title")}
              description={t("pages.organizationRepos.selectOrg.description")}
            />
          )}
          {activeOrganizationId && isLoading && (
            <Card>
              <CardContent className="p-6 text-sm text-gray-500 dark:text-gray-400">{t("pages.organizationRepos.loadingRepos")}</CardContent>
            </Card>
          )}
          {activeOrganizationId && !isLoading && repos.length === 0 && (
            <EmptyState
              title={t("pages.organizationRepos.noRepos.title")}
              description={activeOrganization ? `${activeOrganization.name} has no repositories matching your filters.` : t("pages.organizationRepos.noRepos.description")}
            />
          )}
          {activeOrganizationId && !isLoading && repos.length > 0 && (
            <RepoSelectionTable
              repos={repos}
              selectedKeys={selectedKeys}
              onSelectionChange={setSelectedKeys}
              action={
                <Button
                  size="sm"
                  disabled={selectedKeys.size === 0 || isSaving}
                  onClick={() => void saveSelection()}
                >
                  {isSaving ? t("common.saving") : t("toolbar.saveSelection")}
                </Button>
              }
            />
          )}
        </div>
      </div>
    </PageLayout>
  );
}
