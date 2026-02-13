import { useMemo } from "react";

import { PageHeader, PageHeaderMeta, PageHeaderTitle } from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/card";
import { useDateLabel } from "../hooks/use-date-label";
import { useOrganizations } from "../hooks/useOrganizations";
import { useNavigationStore } from "../stores/navigation-store";
import { useI18n } from "../i18n/i18n";

export function OrganizationPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { organizations } = useOrganizations();
  const { activeOrganizationId } = useNavigationStore();

  const organization = useMemo(
    () => organizations.find((item) => item.id === activeOrganizationId) ?? null,
    [organizations, activeOrganizationId],
  );

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>Organization</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
      </PageHeader>
      <div className="flex flex-col gap-6">
        {!organization && (
          <Card>
            <CardContent className="p-6 text-sm text-gray-500 dark:text-gray-400">
              Select an organization from the sidebar.
            </CardContent>
          </Card>
        )}
        {organization && (
          <Card>
            <CardHeader>
              <CardTitle>{organization.name}</CardTitle>
            </CardHeader>
            <CardContent className="text-sm text-gray-500 dark:text-gray-400">
              Linked provider ID: {organization.provider_id}
            </CardContent>
          </Card>
        )}
      </div>
    </PageLayout>
  );
}
