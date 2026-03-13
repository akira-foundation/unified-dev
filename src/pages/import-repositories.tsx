import { useCallback, useEffect, useMemo, useState } from "react";

import { RepoSelectionTable } from "../components/organizations/repo-selection-table";
import { SearchInput } from "../components/organizations/search-input";
import { VisibilityFilter } from "../components/organizations/visibility-filter";
import { PageHeader, PageHeaderMeta, PageHeaderTitle } from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { Badge } from "../components/ui/badge";
import { Button } from "../components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/card";
import { Skeleton } from "../components/ui/skeleton";
import { Building2, ExternalLink, TriangleAlert } from "lucide-react";
import { useDateLabel } from "../hooks/use-date-label";
import { useOrganizations } from "../hooks/useOrganizations";
import { useNavigation } from "../hooks/useNavigation";
import { providerService } from "../services/providerService";
import { repositorySelectionService } from "../services/repositorySelectionService";
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

  const organization = useMemo(
    () => organizations.find((item) => item.id === activeOrganizationId) ?? null,
    [organizations, activeOrganizationId],
  );

  const [providerOrgs, setProviderOrgs] = useState<ProviderOrg[]>([]);
  const [selectedOrg, setSelectedOrg] = useState<ProviderOrg | null>(null);
  const [repos, setRepos] = useState<ProviderRepo[]>([]);
  const [selectedKeys, setSelectedKeys] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState("");
  const [visibility, setVisibility] = useState<"all" | "public" | "private">("all");
  const [isLoadingOrgs, setIsLoadingOrgs] = useState(false);
  const [isLoadingRepos, setIsLoadingRepos] = useState(false);
  const [orgsError, setOrgsError] = useState<string | null>(null);
  const [reposError, setReposError] = useState<string | null>(null);

  const loadProviderOrgs = useCallback(async () => {
    if (!organization) {
      setProviderOrgs([]);
      setSelectedOrg(null);
      return;
    }

    setIsLoadingOrgs(true);
    setOrgsError(null);
    try {
      const orgs = await providerService.listProviderOrganizations(organization.provider_id);
      setProviderOrgs(orgs);
      setSelectedOrg(null);
      setRepos([]);
      setSelectedKeys(new Set());
      setReposError(null);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Failed to load organizations";
      setOrgsError(message);
      toast.error(message);
    } finally {
      setIsLoadingOrgs(false);
    }
  }, [organization]);

  useEffect(() => {
    void loadProviderOrgs();
  }, [loadProviderOrgs]);

  const loadRepos = useCallback(async () => {
    if (!organization || !selectedOrg) {
      setRepos([]);
      return;
    }

    setIsLoadingRepos(true);
    setReposError(null);
    try {
      const scope = selectedOrg.kind === "personal" ? "personal" : "organization";
      const reposList = await providerService.listProviderRepositories({
        providerId: organization.provider_id,
        scope,
        organizationLogin: selectedOrg.kind === "organization" ? selectedOrg.login : undefined,
      });
      setRepos(reposList);
      setSelectedKeys(new Set());
    } catch (error) {
      const message = error instanceof Error ? error.message : "Failed to load repositories";
      setReposError(message);
      toast.error(message);
    } finally {
      setIsLoadingRepos(false);
    }
  }, [organization, selectedOrg]);

  useEffect(() => {
    void loadRepos();
  }, [loadRepos]);

  const filteredRepos = useMemo(() => {
    return repos.filter((repo) => {
      const matchesSearch =
        repo.name.toLowerCase().includes(search.toLowerCase()) ||
        repo.owner.toLowerCase().includes(search.toLowerCase());
      const matchesVisibility = visibility === "all" || repo.visibility === visibility;
      return matchesSearch && matchesVisibility;
    });
  }, [repos, search, visibility]);

  const selectedCount = selectedKeys.size;
  const visibleSelectedCount = filteredRepos.filter((repo) => selectedKeys.has(repoKey(repo))).length;
  const selectAllState: boolean | "indeterminate" = filteredRepos.length === 0
    ? false
    : visibleSelectedCount === filteredRepos.length
      ? true
      : visibleSelectedCount > 0
        ? "indeterminate"
    : false;

  const handleImportSelected = useCallback(async () => {
    if (!organization) {
      return;
    }

    const payload = repos
      .filter((repo) => selectedKeys.has(repoKey(repo)))
      .map((repo) => ({
        owner: repo.owner,
        repo_name: repo.name,
        visibility: repo.visibility,
        is_selected: true,
        auto_sync: true,
      }));

    if (payload.length === 0) {
      return;
    }
    const toastId = toast.loading("Importing repositories...");
    try {
      await repositorySelectionService.saveSelectedRepositories(organization.id, payload);
      toast.success(`Imported ${payload.length} repositories`, { id: toastId });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Failed to import repositories";
      toast.error(message, { id: toastId });
      throw error;
    }
  }, [organization, repos, selectedKeys]);

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>Import repositories</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        {organization && (
          <Button variant="outline" size="sm" className="gap-2" onClick={() => navigateTo("organization")}>
            <ExternalLink className="h-3.5 w-3.5" />
            View organization
          </Button>
        )}
      </PageHeader>
      {!organization && (
        <Card>
          <CardContent className="p-6 text-sm text-gray-500 dark:text-gray-400">
            {isOrganizationsLoading
              ? "Loading organization..."
              : activeOrganizationId
                ? "Organization not found."
                : "Select an organization first."}
          </CardContent>
        </Card>
      )}
      {organization && (
        <div className="grid gap-6 lg:grid-cols-[260px_1fr]">
          <Card className="h-[calc(100vh-20rem)]">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Building2 className="h-4 w-4 text-muted-foreground" />
                GitHub organizations
              </CardTitle>
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
              {!isLoadingOrgs && orgsError && (
                <div className="flex h-full flex-col items-center justify-center gap-3 text-center text-sm text-gray-500 dark:text-gray-400">
                  <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-500/10 text-amber-500">
                    <TriangleAlert className="h-5 w-5" />
                  </div>
                  <div className="space-y-1">
                    <div className="text-sm font-semibold text-gray-900 dark:text-white">
                      Failed to load organizations
                    </div>
                    <div className="text-xs text-gray-500 dark:text-gray-400">{orgsError}</div>
                  </div>
                </div>
              )}
              {!isLoadingOrgs && !orgsError && providerOrgs.length === 0 && (
                <div className="flex h-full flex-col items-center justify-center gap-3 text-center text-sm text-gray-500 dark:text-gray-400">
                  <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-500/10 text-amber-500">
                    <TriangleAlert className="h-5 w-5" />
                  </div>
                  <div className="space-y-1">
                    <div className="text-sm font-semibold text-gray-900 dark:text-white">
                      No organizations found
                    </div>
                    <div className="text-xs text-gray-500 dark:text-gray-400">
                      Add a provider or check permissions.
                    </div>
                  </div>
                  <div className="w-full max-w-[220px] space-y-2 opacity-60">
                    <Skeleton className="h-9 w-full rounded-full" />
                    <Skeleton className="h-9 w-[90%] rounded-full" />
                    <Skeleton className="h-9 w-[85%] rounded-full" />
                  </div>
                </div>
              )}
              {!isLoadingOrgs && !orgsError &&
                providerOrgs.map((org) => (
                  <Button
                    key={org.id}
                    variant={selectedOrg?.id === org.id ? "secondary" : "ghost"}
                    className="justify-start gap-2"
                    onClick={() => setSelectedOrg(org)}
                  >
                    <span className="truncate">
                      {org.kind === "personal" ? "Personal" : org.login}
                    </span>
                    {selectedOrg?.id === org.id ? (
                      repos.length > 0 ? (
                        <Badge variant="secondary" className="ml-auto text-[10px] uppercase">
                          {repos.length} repos
                        </Badge>
                      ) : null
                    ) : (
                      <Badge variant="secondary" className="ml-auto text-[10px] uppercase">
                        {org.kind === "personal" ? "You" : "Org"}
                      </Badge>
                    )}
                  </Button>
                ))}
            </CardContent>
          </Card>
          <div className="flex flex-col gap-4">
            <Card>
              <CardContent className="flex flex-col gap-4 p-4 lg:flex-row lg:items-center lg:justify-between">
                <div className="flex flex-1 flex-col gap-3 lg:flex-row lg:items-center">
                  <div className="w-full lg:max-w-xs">
                    <SearchInput value={search} onChange={setSearch} />
                  </div>
                  <VisibilityFilter value={visibility} onChange={setVisibility} />
                </div>
                <div className="text-sm text-gray-500 dark:text-gray-400">
                  {selectedCount} repositories selected
                </div>
              </CardContent>
            </Card>
            <div className="h-[calc(100vh-26rem)]">
              {isLoadingRepos && (
                <div className="space-y-3">
                  <Skeleton className="h-12 w-full" />
                  <Skeleton className="h-12 w-full" />
                  <Skeleton className="h-12 w-full" />
                  <Skeleton className="h-12 w-full" />
                  <Skeleton className="h-12 w-full" />
                </div>
              )}
              {!isLoadingRepos && reposError && (
                <Card className="h-full">
                  <CardContent className="flex h-full flex-col items-center justify-center gap-3 p-6 text-center text-sm text-gray-500 dark:text-gray-400">
                    <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-500/10 text-amber-500">
                      <TriangleAlert className="h-5 w-5" />
                    </div>
                    <div className="space-y-1">
                      <div className="text-sm font-semibold text-gray-900 dark:text-white">
                        Failed to load repositories
                      </div>
                      <div className="text-xs text-gray-500 dark:text-gray-400">{reposError}</div>
                    </div>
                  </CardContent>
                </Card>
              )}
              {!isLoadingRepos && !reposError && !selectedOrg && (
                <Card className="h-full">
                  <CardContent className="relative flex h-full flex-col items-center justify-center gap-6 p-10 text-center">
                    <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-amber-500/10 text-amber-500">
                      <TriangleAlert className="h-6 w-6" />
                    </div>
                    <div className="flex flex-col gap-2">
                      <span className="text-base font-semibold text-gray-900 dark:text-white">
                        Select an organization
                      </span>
                      <span className="text-sm text-gray-500 dark:text-gray-400">
                        Choose an org on the left to load repositories.
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
              {!isLoadingRepos && !reposError && selectedOrg && filteredRepos.length === 0 && (
                <Card className="h-full">
                  <CardContent className="flex h-full items-center justify-center p-6 text-sm text-gray-500 dark:text-gray-400">
                    No repositories found for this selection.
                  </CardContent>
                </Card>
              )}
              {!isLoadingRepos && !reposError && selectedOrg && filteredRepos.length > 0 && (
                <RepoSelectionTable
                  className="h-full"
                  repos={filteredRepos}
                  selectedKeys={selectedKeys}
                  selectAllState={selectAllState}
                  onSelectAll={() => {
                    setSelectedKeys((prev) => {
                      const next = new Set(prev);
                      filteredRepos.forEach((repo) => next.add(repoKey(repo)));
                      return next;
                    });
                  }}
                  onClearAll={() => {
                    setSelectedKeys((prev) => {
                      const next = new Set(prev);
                      filteredRepos.forEach((repo) => next.delete(repoKey(repo)));
                      return next;
                    });
                  }}
                  onToggleRepo={(repo) => {
                    setSelectedKeys((prev) => {
                      const next = new Set(prev);
                      const key = repoKey(repo);
                      if (next.has(key)) {
                        next.delete(key);
                      } else {
                        next.add(key);
                      }
                      return next;
                    });
                  }}
                  onImportSelected={handleImportSelected}
                />
              )}
            </div>
          </div>
        </div>
      )}
    </PageLayout>
  );
}
