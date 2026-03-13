import { Plus } from "lucide-react";
import { useMemo } from "react";

import { useOrganizations } from "../hooks/useOrganizations";
import { OrganizationList } from "../components/organizations/organization-list";
import { AddOrganizationDialog } from "../components/organizations/add-organization-dialog";
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
import { Button } from "../components/ui/button";
import { Skeleton } from "../components/ui/skeleton";

export function OrganizationsPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { organizations, isLoading, isDialogOpen, setIsDialogOpen, createOrganization, removeOrganization } = useOrganizations();
  const { providers } = useProviders();
  const providerNameById = useMemo(
    () => Object.fromEntries(providers.map((provider) => [provider.id, provider.name])),
    [providers],
  );
  const { setActiveOrganizationId, navigateTo } = useNavigation("dashboard");

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
            New Organization
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
            title="No organizations yet"
            description="Add an organization to start importing repositories and tracking pull requests."
          />
        ) : (
          <OrganizationList
            organizations={organizations}
            onRemove={removeOrganization}
            onImportRepositories={(organizationId) => {
              setActiveOrganizationId(organizationId);
              navigateTo("import-repositories");
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
    </PageLayout>
  );
}
