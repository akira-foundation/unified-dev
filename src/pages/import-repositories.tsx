import { useMemo, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";

import { RepoSelectionTable } from "../components/organizations/repo-selection-table";
import { PageHeader, PageHeaderMeta, PageHeaderTitle } from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { Badge } from "../components/ui/badge";
import { Button } from "../components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/card";
import { Building2, ExternalLink, RefreshCw, RotateCw, TriangleAlert } from "lucide-react";
import { cache } from "../config/cache";
import { Skeleton } from "../components/ui/skeleton";
import { useDateLabel } from "../hooks/use-date-label";
import { useOrganizations } from "../hooks/useOrganizations";
import { useNavigation } from "../hooks/useNavigation";
import { providerService } from "../services/providerService";
import { repositorySelectionService } from "../services/repositorySelectionService";
import { queryKeys } from "../lib/query-keys";
import type { ProviderRepo } from "../types/organization";
import type { ProviderOrg } from "../types/provider";
import { useI18n } from "../i18n/i18n";
import { toast } from "sonner";

const repoKey = (repo: ProviderRepo) => `${repo.owner}/${repo.name}`;

export function ImportRepositoriesPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { activeOrganizationId, navigateTo } = useNavigation("dashboard");
  const { organizations, isLoading: isOrganizationsLoading } = useOrganizations();
  const queryClient = useQueryClient();

  const organization = useMemo(
    () => organizations.find((item) => item.id === activeOrganizationId) ?? null,
    [organizations, activeOrganizationId],
  );

  const [selectedOrg, setSelectedOrg] = useState<ProviderOrg | null>(null);
  const [selectedKeys, setSelectedKeys] = useState<Set<string>>(new Set());
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [syncingOrgId, setSyncingOrgId] = useState<string | null>(null);

  // Query 1: imported repos (to filter out already-imported ones)
  const { data: importedRepos = [] } = useQuery({
    queryKey: queryKeys.selectedRepositories(organization?.id ?? ""),
    queryFn: () => repositorySelectionService.listSelectedRepositories(organization!.id),
    enabled: !!organization,
  });
  const importedRepoKeys = useMemo(
    () => new Set(importedRepos.map((r) => `${r.owner}/${r.repo_name}`)),
    [importedRepos],
  );

  // Query 2: provider orgs for this organization's provider
  const {
    data: providerOrgs = [],
    isLoading: isLoadingOrgs,
    error: orgsError,
  } = useQuery({
    queryKey: queryKeys.providerOrganizations(organization?.provider_id ?? ""),
    queryFn: () => providerService.listProviderOrganizations(organization!.provider_id!),
    enabled: !!organization?.provider_id,
  });

  // Reset selectedOrg when provider changes
  useMemo(() => {
    setSelectedOrg(null);
    setSelectedKeys(new Set());
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [organization?.provider_id]);

  // Query 3: repos for the selected org
  const scope = selectedOrg?.kind === "personal" ? "personal" : "organization";
  const orgLogin = selectedOrg?.kind === "organization" ? selectedOrg.login : undefined;

  const {
    data: repos = [],
    isLoading: isLoadingRepos,
    error: reposError,
  } = useQuery({
    queryKey: queryKeys.providerRepositories(
      organization?.provider_id ?? "",
      scope,
      orgLogin,
    ),
    queryFn: () =>
      providerService.listProviderRepositories({
        providerId: organization!.provider_id!,
        scope,
        organizationLogin: orgLogin,
      }),
    enabled: !!organization?.provider_id && !!selectedOrg,
    staleTime: cache.staleTime.long,
    gcTime: cache.gcTime.long,
  });

  // Strip already-imported repos before passing to the table
  const availableRepos = useMemo(
    () => repos.filter((repo) => !importedRepoKeys.has(repoKey(repo))),
    [repos, importedRepoKeys],
  );

  const handleRefreshRepos = async () => {
    if (!organization?.provider_id) return;
    setIsRefreshing(true);
    const loadingToast = toast.loading(t("agents.sidebar.toast.syncingAll"));
    try {
      await queryClient.invalidateQueries({
        queryKey: ["provider-repos", organization.provider_id],
        refetchType: "all",
      });
      toast.success(t("agents.sidebar.toast.syncAllDone"), { id: loadingToast });
    } catch {
      toast.error(t("pages.importRepos.importFailed"), { id: loadingToast });
    } finally {
      setIsRefreshing(false);
    }
  };

  const handleSyncOrg = async (org: ProviderOrg) => {
    if (!organization?.provider_id) return;
    setSyncingOrgId(org.id);
    const orgScope = org.kind === "personal" ? "personal" : "organization";
    const orgLogin = org.kind === "organization" ? org.login : undefined;
    const orgName = org.kind === "personal" ? t("pages.importRepos.personal") : org.login;
    const loadingToast = toast.loading(t("pages.importRepos.syncingOrg").replace("{name}", orgName));
    try {
      await queryClient.invalidateQueries({
        queryKey: queryKeys.providerRepositories(organization.provider_id, orgScope, orgLogin),
        refetchType: "all",
      });
      toast.success(t("pages.importRepos.syncedOrg").replace("{name}", orgName), { id: loadingToast });
    } catch {
      toast.error(t("pages.importRepos.importFailed"), { id: loadingToast });
    } finally {
      setSyncingOrgId(null);
    }
  };

  const importMutation = useMutation({
    mutationFn: (payload: Parameters<typeof repositorySelectionService.saveSelectedRepositories>[1]) =>
      repositorySelectionService.saveSelectedRepositories(organization!.id, payload),
    onSuccess: (_, payload) => {
      queryClient.invalidateQueries({
        queryKey: queryKeys.selectedRepositories(organization!.id),
      });
      toast.success(t("pages.importRepos.importedCount").replace("{count}", String(payload.length)));
      setSelectedKeys(new Set());
    },
    onError: () => {
      toast.error(t("pages.importRepos.importFailed"));
    },
  });

  const handleImportSelected = async () => {
    if (!organization) return;

    const payload = repos
      .filter((repo) => selectedKeys.has(repoKey(repo)))
      .map((repo) => ({
        owner: repo.owner,
        repo_name: repo.name,
        visibility: repo.visibility,
        is_selected: true,
        auto_sync: true,
      }));

    if (payload.length === 0) return;

    const toastId = toast.loading(t("pages.importRepos.importingCount"));
    try {
      await importMutation.mutateAsync(payload);
      toast.dismiss(toastId);
    } catch {
      toast.dismiss(toastId);
    }
  };

  const orgsErrorMessage = orgsError instanceof Error ? orgsError.message : orgsError ? String(orgsError) : null;
  const reposErrorMessage = reposError instanceof Error ? reposError.message : reposError ? String(reposError) : null;

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>{t("pages.importRepos.title")}</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        {organization && (
          <Button onClick={() => navigateTo("organization")}>
            <ExternalLink size={18} />
            {t("pages.importRepos.viewOrganization")}
          </Button>
        )}
      </PageHeader>
      {!organization && (
        <Card>
          <CardContent className="p-6 text-sm text-gray-500 dark:text-gray-400">
            {isOrganizationsLoading
              ? t("pages.importRepos.loadingOrg")
              : activeOrganizationId
                ? t("pages.importRepos.orgNotFound")
                : t("pages.importRepos.selectOrgFirst")}
          </CardContent>
        </Card>
      )}
      {organization && (
        <div className="grid gap-6 lg:grid-cols-[260px_1fr]">
          <Card className="h-[calc(100vh-20rem)]">
            <CardHeader className="flex flex-row items-center justify-between">
              <CardTitle className="flex items-center gap-2">
                <Building2 className="h-4 w-4 text-muted-foreground" />
                {t("pages.importRepos.githubOrgs")}
              </CardTitle>
              <button
                onClick={handleRefreshRepos}
                disabled={isRefreshing || isLoadingOrgs}
                className="p-1 rounded text-zinc-400 dark:text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300 hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors disabled:opacity-40 disabled:pointer-events-none cursor-pointer"
                title={t("pages.importRepos.refresh")}
              >
                <RefreshCw className={`h-3.5 w-3.5 ${isRefreshing ? "animate-spin" : ""}`} />
              </button>
            </CardHeader>
            <CardContent className="flex flex-col p-2 gap-2 overflow-y-hidden custom-scrollbar h-[calc(100vh-20rem)]">
              {isLoadingOrgs && (
                <div className="space-y-2 opacity-70">
                  <Skeleton className="h-10 w-full rounded-full" />
                  <Skeleton className="h-10 w-full rounded-full" />
                  <Skeleton className="h-10 w-full rounded-full" />
                  <Skeleton className="h-10 w-full rounded-full" />
                </div>
              )}
              {!isLoadingOrgs && orgsErrorMessage && (
                <div className="flex h-full flex-col items-center justify-center gap-3 text-center text-sm text-gray-500 dark:text-gray-400">
                  <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-500/10 text-amber-500">
                    <TriangleAlert className="h-5 w-5" />
                  </div>
                  <div className="space-y-1">
                    <div className="text-sm font-semibold text-gray-900 dark:text-white">
                      {t("pages.importRepos.failedOrgs.title")}
                    </div>
                    <div className="text-xs text-gray-500 dark:text-gray-400">{orgsErrorMessage}</div>
                  </div>
                </div>
              )}
              {!isLoadingOrgs && !orgsErrorMessage && providerOrgs.length === 0 && (
                <div className="flex h-full flex-col items-center justify-center gap-3 text-center text-sm text-gray-500 dark:text-gray-400">
                  <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-500/10 text-amber-500">
                    <TriangleAlert className="h-5 w-5" />
                  </div>
                  <div className="space-y-1">
                    <div className="text-sm font-semibold text-gray-900 dark:text-white">
                      {t("pages.importRepos.noOrgs.title")}
                    </div>
                    <div className="text-xs text-gray-500 dark:text-gray-400">
                      {t("pages.importRepos.noOrgs.description")}
                    </div>
                  </div>
                  <div className="w-full max-w-[220px] space-y-2 opacity-60">
                    <Skeleton className="h-9 w-full rounded-full" />
                    <Skeleton className="h-9 w-[90%] rounded-full" />
                    <Skeleton className="h-9 w-[85%] rounded-full" />
                  </div>
                </div>
              )}
              {!isLoadingOrgs && !orgsErrorMessage &&
                providerOrgs.map((org) => (
                  <div
                    key={org.id}
                    className="group/org relative"
                  >
                    <Button
                      variant={selectedOrg?.id === org.id ? "secondary" : "ghost"}
                      className="w-full justify-start gap-2 pr-8"
                      onClick={() => { setSelectedOrg(org); setSelectedKeys(new Set()); }}
                    >
                      <span className="truncate">
                        {org.kind === "personal" ? t("pages.importRepos.personal") : org.login}
                      </span>
                      {selectedOrg?.id === org.id ? (
                        repos.length > 0 ? (
                          <Badge variant="secondary" className="ml-auto text-[10px] uppercase">
                            {repos.length} {t("pages.importRepos.reposCount")}
                          </Badge>
                        ) : null
                      ) : (
                        <Badge variant="secondary" className="ml-auto text-[10px] uppercase">
                          {org.kind === "personal" ? t("pages.importRepos.scopeYou") : t("pages.importRepos.scopeOrg")}
                        </Badge>
                      )}
                    </Button>
                    <button
                      onClick={(e) => { e.stopPropagation(); void handleSyncOrg(org); }}
                      disabled={syncingOrgId === org.id}
                      className="hidden group-hover/org:flex absolute right-1.5 top-1/2 -translate-y-1/2 items-center justify-center p-1 rounded hover:bg-zinc-200/60 dark:hover:bg-zinc-700/60 text-zinc-400 dark:text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300 transition-colors disabled:opacity-50 disabled:pointer-events-none"
                      title={t("common.sync")}
                    >
                      <RotateCw className={`h-3 w-3 ${syncingOrgId === org.id ? "animate-spin" : ""}`} />
                    </button>
                  </div>
                ))}
            </CardContent>
          </Card>
          <div className="h-[calc(100vh-16rem)]">
            {isLoadingRepos && (
              <div className="space-y-3">
                <Skeleton className="h-12 w-full" />
                <Skeleton className="h-12 w-full" />
                <Skeleton className="h-12 w-full" />
                <Skeleton className="h-12 w-full" />
                <Skeleton className="h-12 w-full" />
              </div>
            )}
            {!isLoadingRepos && reposErrorMessage && (
              <Card className="h-full">
                <CardContent className="flex h-full flex-col items-center justify-center gap-3 p-6 text-center text-sm text-gray-500 dark:text-gray-400">
                  <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-500/10 text-amber-500">
                    <TriangleAlert className="h-5 w-5" />
                  </div>
                  <div className="space-y-1">
                    <div className="text-sm font-semibold text-gray-900 dark:text-white">
                      {t("pages.importRepos.failedRepos.title")}
                    </div>
                    <div className="text-xs text-gray-500 dark:text-gray-400">{reposErrorMessage}</div>
                  </div>
                </CardContent>
              </Card>
            )}
            {!isLoadingRepos && !reposErrorMessage && !selectedOrg && (
              <Card className="h-full">
                <CardContent className="relative flex h-full flex-col items-center justify-center gap-6 p-10 text-center">
                  <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-amber-500/10 text-amber-500">
                    <TriangleAlert className="h-6 w-6" />
                  </div>
                  <div className="flex flex-col gap-2">
                    <span className="text-base font-semibold text-gray-900 dark:text-white">
                      {t("pages.importRepos.selectOrg.title")}
                    </span>
                    <span className="text-sm text-gray-500 dark:text-gray-400">
                      {t("pages.importRepos.selectOrg.description")}
                    </span>
                  </div>
                  <div className="w-full max-w-2xl space-y-3 opacity-60">
                    <Skeleton className="h-10 w-full" />
                    <Skeleton className="h-10 w-[90%]" />
                    <Skeleton className="h-10 w-[85%]" />
                    <Skeleton className="h-10 w-[80%]" />
                  </div>
                </CardContent>
              </Card>
            )}
            {!isLoadingRepos && !reposErrorMessage && selectedOrg && (
              <RepoSelectionTable
                className="h-full"
                repos={availableRepos}
                selectedKeys={selectedKeys}
                onSelectionChange={setSelectedKeys}
                action={
                  <Button
                    size="sm"
                    disabled={selectedKeys.size === 0 || importMutation.isPending}
                    onClick={handleImportSelected}
                  >
                    {t("common.importSelected")}
                  </Button>
                }
              />
            )}
          </div>
        </div>
      )}
    </PageLayout>
  );
}
