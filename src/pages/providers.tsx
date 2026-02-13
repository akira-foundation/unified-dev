import { Plus } from "lucide-react";

import { AddOrganizationDialog } from "../components/organizations/add-organization-dialog";
import { OrganizationList } from "../components/organizations/organization-list";
import { AddProviderDialog } from "../components/providers/add-provider-dialog";
import { ProviderList } from "../components/providers/provider-list";
import { PageHeader, PageHeaderActions, PageHeaderMeta, PageHeaderTitle } from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { Button } from "../components/ui/button";
import { useDateLabel } from "../hooks/use-date-label";
import { useProviders } from "../hooks/useProviders";
import { useOrganizations } from "../hooks/useOrganizations";
import { useNavigation } from "../hooks/useNavigation";
import { useI18n } from "../i18n/i18n";

export function ProvidersPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { providers, isLoading, isDialogOpen, setIsDialogOpen, createProvider, removeProvider } = useProviders();
  const {
    organizations,
    isLoading: organizationsLoading,
    isDialogOpen: organizationDialogOpen,
    setIsDialogOpen: setOrganizationDialogOpen,
    createOrganization,
    removeOrganization,
  } = useOrganizations();
  const { setActiveOrganizationId, setCurrentPage } = useNavigation("dashboard");

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
        <ProviderList
          providers={providers}
          onRemove={removeProvider}
        />
        <OrganizationList
          organizations={organizations}
          onRemove={removeOrganization}
          onCreate={() => setOrganizationDialogOpen(true)}
          onSelect={(organizationId) => {
            setActiveOrganizationId(organizationId);
            setCurrentPage("organization");
          }}
        />
        {(isLoading || organizationsLoading) && (
          <div className="flex items-center justify-center p-8 text-sm text-zinc-500">
            Loading...
          </div>
        )}
        <AddProviderDialog
          open={isDialogOpen}
          onOpenChange={setIsDialogOpen}
          onSubmit={createProvider}
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
