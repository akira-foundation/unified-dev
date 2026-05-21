import { Plus, RefreshCcw } from "lucide-react";

import { AddOrganizationDialog } from "../components/organizations/add-organization-dialog";
import { OrganizationList } from "../components/organizations/organization-list";
import { AddProviderDialog } from "../components/providers/add-provider-dialog";
import { ProviderList } from "../components/providers/provider-list";
import { UpdateProviderDialog } from "../components/providers/update-provider-dialog";
import { PageHeader, PageHeaderMeta, PageHeaderTitle } from "../components/layout/page-header";
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
    createProvider,
    removeProvider,
    updateProviderAuth,
  } = useProviders();
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [providerToUpdate, setProviderToUpdate] = useState<typeof providers[number] | null>(null);
  const {
    organizations,
    isLoading: organizationsLoading,
    createOrganization,
    removeOrganization,
  } = useOrganizations();
  const [organizationDialogOpen, setOrganizationDialogOpen] = useState(false);
  const providerNameById = useMemo(
    () => Object.fromEntries(providers.map((provider) => [provider.id, provider.name])),
    [providers],
  );
  const { setActiveOrganizationId, navigateTo } = useNavigation("dashboard");

  return (
    <PageLayout scroll>
      <PageHeader className="mx-auto w-full max-w-6xl">
        <div className="flex items-center justify-between w-full">
          <div>
            <PageHeaderTitle>{t("pages.providers.title")}</PageHeaderTitle>
            <PageHeaderMeta>
              <span>{t("app.name")}</span>
              <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
              <span>{dateLabel}</span>
            </PageHeaderMeta>
          </div>

          <div className="flex items-center gap-3">
            <Button variant="ghost" className="text-zinc-400 hover:text-white hover:bg-white/5 font-medium text-xs">
              <RefreshCcw className="mr-2 h-3.5 w-3.5" />
              {t("common.refresh")}
            </Button>
            <Button
              onClick={() => setIsDialogOpen(true)}
              className="gap-1.5"
            >
              <Plus className="h-3.5 w-3.5" />
              {t("pages.providers.addProvider")}
            </Button>
          </div>
        </div>
      </PageHeader>

      <div className="mx-auto w-full max-w-6xl pb-6 flex flex-col gap-6">
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
              onRemove={(id) => removeProvider(id, false)}
              onUpdateToken={(provider) => setProviderToUpdate(provider)}
            />
          )}
          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between px-1">
              <span className="text-[13px] font-semibold text-zinc-700 dark:text-zinc-200">{t("components.orgList.title")}</span>
              <Button size="sm" onClick={() => setOrganizationDialogOpen(true)} className="gap-1.5">
                <Plus className="h-3.5 w-3.5" />
                {t("common.newOrganization")}
              </Button>
            </div>
            {organizationsLoading ? (
              <div className="space-y-3">
                <Skeleton className="h-16 w-full" />
                <Skeleton className="h-16 w-full" />
              </div>
            ) : (
              <OrganizationList
                organizations={organizations}
                onRemove={removeOrganization}
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
          </div>
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
      </div>
    </PageLayout>
  );
}
