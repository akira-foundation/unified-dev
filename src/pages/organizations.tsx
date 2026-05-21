import { Plus } from "lucide-react";
import { useMemo, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { useQueryClient } from "@tanstack/react-query";

import { useOrganizations } from "../hooks/useOrganizations";
import type { OrganizationSummary } from "../types/organization";
import { useHotkey } from "@/hooks/useHotkey";
import { OrganizationList } from "../components/organizations/organization-list";
import { AddOrganizationDialog } from "../components/organizations/add-organization-dialog";
import { EditOrganizationDialog } from "../components/organizations/edit-organization-dialog";
import { OrgSyncSheet } from "../components/organizations/org-sync-sheet";
import { EmptyState } from "../components/ui/empty-state";
import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { useI18n } from "../i18n/i18n";
import { useDateLabel } from "../hooks/use-date-label";
import { useProviders } from "../hooks/useProviders";
import { useNavigation } from "../hooks/useNavigation";
import { useSettingsStore } from "../stores/settings-store";
import { repositorySelectionService } from "../services/repositorySelectionService";
import { resolveCurrentLogin } from "../lib/work-visibility";
import { queryKeys } from "../lib/query-keys";
import { Button } from "../components/ui/button";
import { Skeleton } from "../components/ui/skeleton";

export function OrganizationsPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const queryClient = useQueryClient();
  const { organizations, isLoading, syncingIds, createOrganization, updateOrganization, removeOrganization } = useOrganizations();
  const { providers } = useProviders();
  const { resolveIssueScope, resolvePrScope } = useSettingsStore();
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  useHotkey("n", () => setIsDialogOpen(true));
  const [editOrganization, setEditOrganization] = useState<OrganizationSummary | null>(null);
  const [syncOrganization, setSyncOrganization] = useState<OrganizationSummary | null>(null);
  const [manualSyncingIds, setManualSyncingIds] = useState<Set<string>>(new Set());
  const providerNameById = useMemo(
    () => Object.fromEntries(providers.map((provider) => [provider.id, provider.name])),
    [providers],
  );
  const { setActiveOrganizationId, navigateTo } = useNavigation("dashboard");

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

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>{t("nav.organizations")}</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        <PageHeaderActions>
          <Button onClick={() => setIsDialogOpen(true)}>
            <Plus size={18} />
            {t("pages.organizations.newOrganization")}
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
        ) : organizations.length === 0 ? (
          <EmptyState
            title={t("pages.organizations.empty.title")}
            description={t("pages.organizations.empty.description")}
          />
        ) : (
          <OrganizationList
            organizations={organizations}
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
