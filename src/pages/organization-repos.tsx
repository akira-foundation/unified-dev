import { useMemo } from "react";

import { OrganizationList } from "../components/organizations/organization-list";
import { RepoSelectionTable } from "../components/organizations/repo-selection-table";
import { RepoSelectionToolbar } from "../components/organizations/repo-selection-toolbar";
import { PageHeader, PageHeaderMeta, PageHeaderTitle } from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { Card, CardContent } from "../components/ui/card";
import { useDateLabel } from "../hooks/use-date-label";
import { useOrganizationRepoSelection } from "../hooks/use-organization-repo-selection";
import { useOrganizations } from "../hooks/useOrganizations";
import { useNavigationStore } from "../stores/navigation-store";
import { useI18n } from "../i18n/i18n";

const repoKey = (repo: { owner: string; name: string }) => `${repo.owner}/${repo.name}`;

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
    filteredRepos,
    selectedKeys,
    search,
    visibility,
    isLoading,
    isSaving,
    selectedCount,
    setSearch,
    setVisibility,
    toggleRepo,
    selectAllVisible,
    clearAllVisible,
    saveSelection,
  } = useOrganizationRepoSelection(activeOrganizationId);

  const visibleSelectedCount = filteredRepos.filter((repo) => selectedKeys.has(repoKey(repo))).length;
  const selectAllState: boolean | "indeterminate" = filteredRepos.length === 0
    ? false
    : visibleSelectedCount === filteredRepos.length
      ? true
      : visibleSelectedCount > 0
        ? "indeterminate"
        : false;

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
              <CardContent className="p-4 text-sm text-gray-500 dark:text-gray-400">Loading organizations...</CardContent>
            </Card>
          )}
        </div>
        <div className="flex flex-col gap-4">
          <RepoSelectionToolbar
            search={search}
            visibility={visibility}
            selectedCount={selectedCount}
            isSaving={isSaving}
            onSearchChange={setSearch}
            onVisibilityChange={setVisibility}
            onSave={saveSelection}
            onSync={saveSelection}
          />
          {!activeOrganizationId && (
            <Card>
              <CardContent className="p-6 text-sm text-gray-500 dark:text-gray-400">
                Select an organization to view repositories.
              </CardContent>
            </Card>
          )}
          {activeOrganizationId && isLoading && (
            <Card>
              <CardContent className="p-6 text-sm text-gray-500 dark:text-gray-400">Loading repositories...</CardContent>
            </Card>
          )}
          {activeOrganizationId && !isLoading && filteredRepos.length === 0 && (
            <Card>
              <CardContent className="p-6 text-sm text-gray-500 dark:text-gray-400">
                {activeOrganization
                  ? `No repositories found for ${activeOrganization.name}.`
                  : "No repositories found."}
              </CardContent>
            </Card>
          )}
          {activeOrganizationId && !isLoading && filteredRepos.length > 0 && (
            <RepoSelectionTable
              repos={filteredRepos}
              selectedKeys={selectedKeys}
              selectAllState={selectAllState}
              onSelectAll={selectAllVisible}
              onClearAll={clearAllVisible}
              onToggleRepo={toggleRepo}
            />
          )}
        </div>
      </div>
    </PageLayout>
  );
}
