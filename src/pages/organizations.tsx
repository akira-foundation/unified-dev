import { Building2, Plus } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { useQueryClient } from "@tanstack/react-query";

import { useOrganizations } from "../hooks/useOrganizations";
import type { OrganizationSummary } from "../types/organization";
import { useHotkey } from "@/hooks/useHotkey";
import { useFilteredOrgs } from "@/hooks/useFilteredOrgs";
import { OrganizationList } from "../components/organizations/organization-list";
import { OrgToolbar } from "../components/organizations/org-toolbar";
import { OrgInsightsPanel } from "../components/organizations/org-insights-panel";
import { AddOrganizationDialog } from "../components/organizations/add-organization-dialog";
import { EditOrganizationDialog } from "../components/organizations/edit-organization-dialog";
import { OrgSyncSheet } from "../components/organizations/org-sync-sheet";
import { EmptyState } from "../components/ui/empty-state";
import { AppbarActions } from "../components/layout/appbar-actions";
import { PageLayout } from "../components/layout/page-layout";
import { useI18n } from "../i18n/i18n";
import { useProviders } from "../hooks/useProviders";
import { useNavigation } from "../hooks/useNavigation";
import { useSearchStore } from "../stores/search-store";
import { useOrgViewStore } from "../stores/org-view-store";
import { useSettingsStore } from "../stores/settings-store";
import { repositorySelectionService } from "../services/repositorySelectionService";
import { resolveCurrentLogin } from "../lib/work-visibility";
import { queryKeys } from "../lib/query-keys";
import { Button } from "../components/ui/button";
import { Skeleton } from "../components/ui/skeleton";

export function OrganizationsPage() {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const { organizations, isLoading, syncingIds, createOrganization, updateOrganization, removeOrganization } = useOrganizations();
  const { providers } = useProviders();
  const { resolveIssueScope, resolvePrScope } = useSettingsStore();
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const insightsOpen = useOrgViewStore((s) => s.insightsOpen);
  const toggleInsights = useOrgViewStore((s) => s.toggleInsights);
  useHotkey("n", () => setIsDialogOpen(true));
  useHotkey("f", toggleInsights);
  const [editOrganization, setEditOrganization] = useState<OrganizationSummary | null>(null);
  const [syncOrganization, setSyncOrganization] = useState<OrganizationSummary | null>(null);
  const [manualSyncingIds, setManualSyncingIds] = useState<Set<string>>(new Set());
  const providerNameById = useMemo(
    () => Object.fromEntries(providers.map((provider) => [provider.id, provider.name])),
    [providers],
  );
  const { setActiveOrganizationId, navigateTo } = useNavigation("dashboard");
  const filteredOrgs = useFilteredOrgs(organizations, providerNameById);

  const registerSearch = useSearchStore((s) => s.registerProvider);
  useEffect(() => {
    registerSearch({
      placeholder: t("pages.organizations.search"),
      items: organizations.map((org) => ({
        id: org.id,
        title: org.name,
        subtitle: org.selected_repos_count > 0 ? `${org.selected_repos_count} ${t("components.orgItem.repos")}` : undefined,
        icon: <Building2 className="h-3.5 w-3.5 text-zinc-400" />,
        onSelect: () => { setActiveOrganizationId(org.id); navigateTo("organization"); },
      })),
    });
    return () => registerSearch(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [organizations]);

  async function handleSync(orgId: string) {
    setManualSyncingIds((prev) => new Set(prev).add(orgId));
    const toastId = toast.loading(t("common.syncing"));
    try {
      const repos = await repositorySelectionService.listSelectedRepositories(orgId);
      const currentLogin = resolveCurrentLogin(orgId, organizations, providers);

      await Promise.allSettled(
        repos.map((repo) =>
          Promise.allSettled([
            invoke("sync_issues", {
              orgId,
              owner: repo.owner,
              repoName: repo.repo_name,
              scope: resolveIssueScope(orgId, repo.repo_name),
              currentLogin,
            }),
            invoke("sync_pull_requests", {
              organizationId: orgId,
              repoName: repo.repo_name,
              scope: resolvePrScope(orgId, repo.repo_name),
              currentLogin,
            }),
          ]),
        ),
      );

      await invoke("sync_repository_stats", { organizationId: orgId });
      await invoke("touch_org_synced_at", { orgId });

      queryClient.invalidateQueries({ queryKey: queryKeys.selectedRepositories(orgId) });
      toast.success(t("common.syncDone"), { id: toastId });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : String(err), { id: toastId });
    } finally {
      setManualSyncingIds((prev) => {
        const next = new Set(prev);
        next.delete(orgId);
        return next;
      });
    }
  }

  const anySyncing = manualSyncingIds.size > 0 || syncingIds.size > 0;
  async function syncAll() {
    await Promise.allSettled(organizations.map((o) => handleSync(o.id)));
  }

  return (
    <PageLayout className="!p-0 !space-y-0 h-[calc(100vh-4rem)] overflow-hidden">
      <AppbarActions>
        <Button onClick={() => setIsDialogOpen(true)} title={t("pages.organizations.newOrganization")}>
          <Plus size={18} />
          <span className="hidden xl:inline">{t("pages.organizations.newOrganization")}</span>
        </Button>
        <OrgToolbar onSync={() => void syncAll()} isSyncing={anySyncing} />
      </AppbarActions>

      <div className="flex h-full min-h-0">
        <div className="min-w-0 flex-1 overflow-y-auto custom-scrollbar p-4 md:p-6">
          {isLoading ? (
            <div className="space-y-3">
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
            </div>
          ) : organizations.length === 0 ? (
            <EmptyState
              title={t("pages.organizations.empty.title")}
              description={t("pages.organizations.empty.description")}
            />
          ) : (
            <OrganizationList
              organizations={filteredOrgs}
              syncingIds={new Set([...syncingIds, ...manualSyncingIds])}
              onRemove={removeOrganization}
              onSync={(orgId) => void handleSync(orgId)}
              onSelect={(organizationId) => {
                setActiveOrganizationId(organizationId);
                navigateTo("organization");
              }}
              onImportRepositories={(organizationId) => {
                setActiveOrganizationId(organizationId);
                navigateTo("import-repositories");
              }}
              onEdit={(organizationId) => {
                const org = organizations.find((o) => o.id === organizationId) ?? null;
                setEditOrganization(org);
              }}
              onConfigureSync={(organizationId) => {
                const org = organizations.find((o) => o.id === organizationId) ?? null;
                setSyncOrganization(org);
              }}
              providerNameById={providerNameById}
            />
          )}
        </div>

        {insightsOpen && (
          <OrgInsightsPanel orgs={organizations} providerNameById={providerNameById} className="w-72 shrink-0" />
        )}
      </div>

      <AddOrganizationDialog
        open={isDialogOpen}
        onOpenChange={setIsDialogOpen}
        providers={providers}
        onSubmit={createOrganization}
      />
      <EditOrganizationDialog
        open={editOrganization !== null}
        onOpenChange={(open) => { if (!open) setEditOrganization(null); }}
        organization={editOrganization}
        providers={providers}
        onSubmit={updateOrganization}
      />
      <OrgSyncSheet
        organization={syncOrganization}
        open={syncOrganization !== null}
        onOpenChange={(open) => { if (!open) setSyncOrganization(null); }}
      />
    </PageLayout>
  );
}
