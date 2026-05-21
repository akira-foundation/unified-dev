import { useEffect, useMemo, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";

import type { VisibilityFilterValue } from "@/components/organizations/repo-selection-table";
import { cache } from "@/config/cache";
import { useOrganizations } from "@/hooks/useOrganizations";
import { useNavigation } from "@/hooks/useNavigation";
import { useSearchStore } from "@/stores/search-store";
import { useImportViewStore } from "@/stores/import-view-store";
import { providerService } from "@/services/providerService";
import { repositorySelectionService } from "@/services/repositorySelectionService";
import { queryKeys } from "@/lib/query-keys";
import { useI18n } from "@/i18n/i18n";
import { useBrowserHandoffToast } from "@/hooks/use-browser-handoff-toast";
import type { ProviderRepo } from "@/types/organization";
import type { ProviderOrg } from "@/types/provider";

const repoKey = (repo: ProviderRepo) => `${repo.owner}/${repo.name}`;

export function useImportRepositories() {
  const { t } = useI18n();
  const { activeOrganizationId, navigateTo } = useNavigation("dashboard");
  const { organizations, isLoading: isOrganizationsLoading } = useOrganizations();
  const queryClient = useQueryClient();
  const browserHandoffToast = useBrowserHandoffToast();

  const organization = useMemo(
    () => organizations.find((item) => item.id === activeOrganizationId) ?? null,
    [organizations, activeOrganizationId],
  );

  const selectedOrg = useImportViewStore((s) => s.selectedOrg);
  const setSelectedOrg = useImportViewStore((s) => s.setSelectedOrg);
  const registerSearch = useSearchStore((s) => s.registerProvider);
  const [selectedKeys, setSelectedKeys] = useState<Set<string>>(new Set());
  const [visibility, setVisibility] = useState<VisibilityFilterValue>("all");
  const [filterOpen, setFilterOpen] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [syncingOrgId, setSyncingOrgId] = useState<string | null>(null);
  const [orgToRemove, setOrgToRemove] = useState<ProviderOrg | null>(null);
  const [isRemovingOrg, setIsRemovingOrg] = useState(false);

  const { data: importedRepos = [] } = useQuery({
    queryKey: queryKeys.selectedRepositories(organization?.id ?? ""),
    queryFn: () => repositorySelectionService.listSelectedRepositories(organization!.id),
    enabled: !!organization,
  });
  const importedRepoKeys = useMemo(
    () => new Set(importedRepos.map((r) => `${r.owner}/${r.repo_name}`)),
    [importedRepos],
  );

  const { data: providerOrgs = [], isLoading: isLoadingOrgs, error: orgsError } = useQuery({
    queryKey: queryKeys.providerOrganizations(organization?.provider_id ?? ""),
    queryFn: () => providerService.listProviderOrganizations(organization!.provider_id!),
    enabled: !!organization?.provider_id,
  });

  useEffect(() => {
    setSelectedOrg(null);
    return () => setSelectedOrg(null);
  }, [activeOrganizationId, setSelectedOrg]);

  useEffect(() => {
    setSelectedKeys(new Set());
    if (!selectedOrg) setFilterOpen(false);
  }, [selectedOrg]);

  const scope = selectedOrg?.kind === "personal" ? "personal" : "organization";
  const orgLogin = selectedOrg?.kind === "organization" ? selectedOrg.login : undefined;

  const { data: repos = [], isLoading: isLoadingRepos, error: reposError } = useQuery({
    queryKey: queryKeys.providerRepositories(organization?.provider_id ?? "", scope, orgLogin),
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

  const availableRepos = useMemo(
    () => repos.filter((repo) => !importedRepoKeys.has(repoKey(repo))),
    [repos, importedRepoKeys],
  );

  const visCounts = useMemo(() => {
    const priv = availableRepos.filter((r) => r.visibility === "private").length;
    return { all: availableRepos.length, public: availableRepos.length - priv, private: priv };
  }, [availableRepos]);

  const toggleRepo = (repo: ProviderRepo) => {
    const key = repoKey(repo);
    setSelectedKeys((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  };

  useEffect(() => {
    if (!selectedOrg) {
      registerSearch(null);
      return;
    }
    registerSearch({
      placeholder: t("filters.search.placeholder"),
      items: availableRepos.map((repo) => ({
        id: repoKey(repo),
        title: repo.name,
        subtitle: repo.owner,
        onSelect: () => toggleRepo(repo),
      })),
    });
    return () => registerSearch(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedOrg, availableRepos]);

  const importMutation = useMutation({
    mutationFn: (payload: Parameters<typeof repositorySelectionService.saveSelectedRepositories>[1]) =>
      repositorySelectionService.saveSelectedRepositories(organization!.id, payload),
    onSuccess: (_, payload) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.selectedRepositories(organization!.id) });
      queryClient.invalidateQueries({ queryKey: queryKeys.allRepositories() });
      toast.success(t("pages.importRepos.importedCount").replace("{count}", String(payload.length)));
      setSelectedKeys(new Set());
    },
    onError: () => toast.error(t("pages.importRepos.importFailed")),
  });

  const importRepos = async (selection: ProviderRepo[]) => {
    if (!organization) return;
    const payload = selection.map((repo) => ({
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
    } finally {
      toast.dismiss(toastId);
    }
  };

  const handleImportSelected = () => importRepos(repos.filter((repo) => selectedKeys.has(repoKey(repo))));
  const handleImportAll = () => importRepos(availableRepos);

  const handleRefreshRepos = async () => {
    if (!organization?.provider_id) return;
    setIsRefreshing(true);
    const loadingToast = toast.loading(t("agents.sidebar.toast.syncingAll"));
    try {
      await queryClient.invalidateQueries({ queryKey: ["provider-repos", organization.provider_id], refetchType: "all" });
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
    const login = org.kind === "organization" ? org.login : undefined;
    const orgName = org.kind === "personal" ? t("pages.importRepos.personal") : org.login;
    const loadingToast = toast.loading(t("pages.importRepos.syncingOrg").replace("{name}", orgName));
    try {
      await queryClient.invalidateQueries({
        queryKey: queryKeys.providerRepositories(organization.provider_id, orgScope, login),
        refetchType: "all",
      });
      toast.success(t("pages.importRepos.syncedOrg").replace("{name}", orgName), { id: loadingToast });
    } catch {
      toast.error(t("pages.importRepos.importFailed"), { id: loadingToast });
    } finally {
      setSyncingOrgId(null);
    }
  };

  const handleRemoveOrg = async () => {
    if (!organization?.provider_id || !orgToRemove) return;
    setIsRemovingOrg(true);
    const orgName = orgToRemove.kind === "personal" ? t("pages.importRepos.personal") : orgToRemove.login;
    const toastId = toast.loading(`Removing ${orgName}...`);
    try {
      await providerService.uninstallGithubApp(organization.provider_id, orgToRemove.login);
      await queryClient.invalidateQueries({ queryKey: queryKeys.providerOrganizations(organization.provider_id) });
      await queryClient.invalidateQueries({ queryKey: queryKeys.providerRepositories(organization.provider_id, "organization", orgToRemove.login) });
      await queryClient.invalidateQueries({ queryKey: queryKeys.providerRepositories(organization.provider_id, "personal") });
      if (selectedOrg?.id === orgToRemove.id) setSelectedOrg(null);
      toast.success(`${orgName} removed`, { id: toastId });
      setOrgToRemove(null);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : String(error), { id: toastId });
    } finally {
      setIsRemovingOrg(false);
    }
  };

  const handleInstallMoreOrganizations = async () => {
    const handoff = browserHandoffToast();
    try {
      await providerService.installGithubApp();
      if (organization?.provider_id) {
        await queryClient.invalidateQueries({ queryKey: queryKeys.providerOrganizations(organization.provider_id) });
      }
      await queryClient.invalidateQueries({ queryKey: queryKeys.organizations() });
      await queryClient.invalidateQueries({ queryKey: queryKeys.allRepositories() });
      handoff.success("GitHub App installation flow completed");
    } catch (error) {
      handoff.error(error, "Failed to open GitHub App installation");
    }
  };

  return {
    t,
    navigateTo,
    organization,
    activeOrganizationId,
    isOrganizationsLoading,
    selectedOrg,
    setSelectedOrg,
    providerOrgs,
    isLoadingOrgs,
    orgsErrorMessage: orgsError instanceof Error ? orgsError.message : orgsError ? String(orgsError) : null,
    repos,
    availableRepos,
    isLoadingRepos,
    reposErrorMessage: reposError instanceof Error ? reposError.message : reposError ? String(reposError) : null,
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
    importPending: importMutation.isPending,
    handleImportSelected,
    handleImportAll,
    handleRefreshRepos,
    handleSyncOrg,
    handleRemoveOrg,
    handleInstallMoreOrganizations,
  };
}
