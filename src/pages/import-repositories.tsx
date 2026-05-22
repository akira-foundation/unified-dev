import { ExternalLink, Eye, Filter, RefreshCw } from "lucide-react";

import { RepoSelectionTable } from "../components/organizations/repo-selection-table";
import { ImportOrgList } from "../components/organizations/import-org-list";
import { ImportFilterPanel } from "../components/organizations/import-filter-panel";
import { AppbarActions } from "../components/layout/appbar-actions";
import { EmptyState } from "../components/ui/empty-state";
import { PageLayout } from "../components/layout/page-layout";
import { Button } from "../components/ui/button";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "../components/ui/alert-dialog";
import { Skeleton } from "../components/ui/skeleton";
import { cn } from "../lib/utils";
import { useImportRepositories } from "../hooks/useImportRepositories";

export function ImportRepositoriesPage() {
  const {
    t,
    navigateTo,
    organization,
    activeOrganizationId,
    isOrganizationsLoading,
    selectedOrg,
    setSelectedOrg,
    providerOrgs,
    isLoadingOrgs,
    orgsErrorMessage,
    repos,
    availableRepos,
    isLoadingRepos,
    reposErrorMessage,
    visCounts,
    selectedKeys,
    setSelectedKeys,
    visibility,
    setVisibility,
    filterOpen,
    setFilterOpen,
    isRefreshing,
    syncingOrgId,
    orgToRemove,
    setOrgToRemove,
    isRemovingOrg,
    importPending,
    handleImportSelected,
    handleImportAll,
    handleRefreshRepos,
    handleSyncOrg,
    handleRemoveOrg,
    handleInstallMoreOrganizations,
  } = useImportRepositories();

  return (
    <PageLayout className="!p-0 !space-y-0 h-[calc(100vh-4rem)] overflow-hidden">
      {organization && (
        <AppbarActions>
          {selectedOrg ? (
            <>
              <Button onClick={() => void handleImportSelected()} disabled={selectedKeys.size === 0 || importPending}>
                {t("common.importSelected")}
              </Button>
              <Button variant="outline" onClick={() => void handleImportAll()} disabled={availableRepos.length === 0 || importPending}>
                {t("pages.importRepos.importAll")}
              </Button>
              <Button
                variant="outline"
                size="icon-sm"
                onClick={() => setFilterOpen((v) => !v)}
                className={cn("relative", filterOpen && "bg-zinc-100 text-zinc-900 dark:bg-zinc-800 dark:text-zinc-100")}
                title={t("repos.table.filter")}
              >
                <Filter className="h-4 w-4" />
                {visibility !== "all" && (
                  <span className="absolute -top-1.5 -right-1.5 h-4 w-4 rounded-full bg-purple-500 text-[10px] font-bold text-white flex items-center justify-center">1</span>
                )}
              </Button>
            </>
          ) : (
            <>
              <Button onClick={() => navigateTo("organization")} title={t("pages.importRepos.viewOrganization")}>
                <Eye size={18} />
                <span className="hidden xl:inline">{t("pages.importRepos.viewOrganization")}</span>
              </Button>
              <Button variant="outline" onClick={() => void handleInstallMoreOrganizations()} title={t("pages.importRepos.addOrgs")}>
                <ExternalLink size={18} />
                <span className="hidden xl:inline">{t("pages.importRepos.addOrgs")}</span>
              </Button>
              <Button variant="outline" size="icon-sm" onClick={handleRefreshRepos} disabled={isRefreshing || isLoadingOrgs} title={t("pages.importRepos.refresh")}>
                <RefreshCw className={cn("h-4 w-4", isRefreshing && "animate-spin")} />
              </Button>
            </>
          )}
        </AppbarActions>
      )}

      <div className="flex h-full min-h-0 flex-col p-4 md:p-6">
        {!organization ? (
          <EmptyState
            title={t("pages.importRepos.title")}
            description={isOrganizationsLoading ? t("pages.importRepos.loadingOrg") : activeOrganizationId ? t("pages.importRepos.orgNotFound") : t("pages.importRepos.selectOrgFirst")}
          />
        ) : !selectedOrg ? (
          <div className="min-h-0 flex-1 overflow-y-auto custom-scrollbar">
            <ImportOrgList
              orgs={providerOrgs}
              isLoading={isLoadingOrgs}
              errorMessage={orgsErrorMessage}
              syncingOrgId={syncingOrgId}
              onSelect={(org) => setSelectedOrg(org)}
              onSync={(org) => void handleSyncOrg(org)}
              onRemove={(org) => setOrgToRemove(org)}
            />
          </div>
        ) : (
          <div className="flex min-h-0 flex-1 gap-4">
            <div className="min-w-0 flex-1">
              {isLoadingRepos ? (
                <div className="space-y-3">
                  <Skeleton className="h-12 w-full" />
                  <Skeleton className="h-12 w-full" />
                  <Skeleton className="h-12 w-full" />
                </div>
              ) : reposErrorMessage ? (
                <EmptyState title={t("pages.importRepos.failedRepos.title")} description={reposErrorMessage} />
              ) : availableRepos.length === 0 ? (
                <EmptyState title={repos.length > 0 ? t("pages.importRepos.allImported") : t("pages.importRepos.noRepos")} />
              ) : (
                <RepoSelectionTable
                  className="h-full"
                  repos={availableRepos}
                  visibility={visibility}
                  selectedKeys={selectedKeys}
                  onSelectionChange={setSelectedKeys}
                />
              )}
            </div>
            {filterOpen && <ImportFilterPanel visibility={visibility} onChange={setVisibility} counts={visCounts} />}
          </div>
        )}
      </div>

      <AlertDialog open={!!orgToRemove} onOpenChange={(open) => !open && setOrgToRemove(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("pages.importRepos.removeOrg.title")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("pages.importRepos.removeOrg.description").replace("{login}", orgToRemove?.login ?? "")}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isRemovingOrg}>{t("common.cancel")}</AlertDialogCancel>
            <AlertDialogAction onClick={() => void handleRemoveOrg()} disabled={isRemovingOrg}>
              {isRemovingOrg ? t("pages.importRepos.removeOrg.removing") : t("common.remove")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </PageLayout>
  );
}
