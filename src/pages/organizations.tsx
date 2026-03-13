import { useOrganizations } from "../hooks/useOrganizations";
import { OrganizationList } from "../components/organizations/organization-list";
import {
  PageHeader,
  PageHeaderMeta,
  PageHeaderTitle,
} from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { useI18n } from "../i18n/i18n";
import { useDateLabel } from "../hooks/use-date-label";
import { useProviders } from "../hooks/useProviders";
import { useNavigation } from "../hooks/useNavigation";
import { Skeleton } from "../components/ui/skeleton";
import { useMemo } from "react";

export function OrganizationsPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { organizations, isLoading, removeOrganization } = useOrganizations();
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
      </PageHeader>
      <div className="flex flex-col gap-6">
        {isLoading ? (
          <div className="space-y-3">
            <Skeleton className="h-24 w-full" />
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
          </div>
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
    </PageLayout>
  );
}
