import { Plus } from "lucide-react";

import { AddOrganizationDialog } from "../components/organizations/add-organization-dialog";
import { OrganizationList } from "../components/organizations/organization-list";
import { AddProviderDialog } from "../components/providers/add-provider-dialog";
import { ProviderList } from "../components/providers/provider-list";
import { UpdateProviderDialog } from "../components/providers/update-provider-dialog";
import { PageHeader, PageHeaderActions, PageHeaderMeta, PageHeaderTitle } from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { Button } from "../components/ui/button";
import { Skeleton } from "../components/ui/skeleton";
import { useDateLabel } from "../hooks/use-date-label";
import { useProviders } from "../hooks/useProviders";
import { useOrganizations } from "../hooks/useOrganizations";
import { useNavigation } from "../hooks/useNavigation";
import { useI18n } from "../i18n/i18n";
import { useMemo, useState } from "react";

export function ProvidersPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const {
    providers,
    isLoading,
    isDialogOpen,
    setIsDialogOpen,
    createProvider,
    removeProvider,
    updateProviderAuth,
  } = useProviders();
  const [providerToUpdate, setProviderToUpdate] = useState<typeof providers[number] | null>(null);
  const {
    organizations,
    isLoading: organizationsLoading,
    isDialogOpen: organizationDialogOpen,
    setIsDialogOpen: setOrganizationDialogOpen,
    createOrganization,
    removeOrganization,
  } = useOrganizations();
  const providerNameById = useMemo(
    () => Object.fromEntries(providers.map((provider) => [provider.id, provider.name])),
    [providers],
  );
  const { setActiveOrganizationId, navigateTo } = useNavigation("dashboard");

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>Providers</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        <PageHeaderActions>
          <Button onClick={() => setIsDialogOpen(true)}>
            <Plus size={18} />
            New Provider
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
        ) : (
          <ProviderList
            providers={providers}
            onRemove={removeProvider}
            onUpdateToken={(provider) => setProviderToUpdate(provider)}
          />
        )}
        {organizationsLoading ? (
          <div className="space-y-3">
            <Skeleton className="h-24 w-full" />
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
          </div>
        ) : (
          <OrganizationList
            organizations={organizations}
            onRemove={removeOrganization}
            onCreate={() => setOrganizationDialogOpen(true)}
            onSelect={(organizationId) => {
              setActiveOrganizationId(organizationId);
              navigateTo("organization");
            }}
            onImportRepositories={(organizationId) => {
              setActiveOrganizationId(organizationId);
              navigateTo("import-repositories");
            }}
            providerNameById={providerNameById}
          />
        )}
        <AddProviderDialog
          open={isDialogOpen}
          onOpenChange={setIsDialogOpen}
          onSubmit={createProvider}
        />
        <UpdateProviderDialog
          provider={providerToUpdate}
          open={Boolean(providerToUpdate)}
          onOpenChange={(open) => {
            if (!open) {
              setProviderToUpdate(null);
            }
          }}
          onSubmit={updateProviderAuth}
        />
        <AddOrganizationDialog
          open={organizationDialogOpen}
          onOpenChange={setOrganizationDialogOpen}
          providers={providers}
          onSubmit={createOrganization}
        />
      </div>
    </PageLayout>
  );
}
