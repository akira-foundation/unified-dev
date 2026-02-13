import { useOrganizations } from "../hooks/useOrganizations";
import { AddOrganizationDialog } from "../components/organizations/add-organization-dialog";
import { OrganizationList } from "../components/organizations/organization-list";
import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { NotificationButton } from "../components/layout/notification-button";
import { useI18n } from "../i18n/i18n";
import { useDateLabel } from "../hooks/use-date-label";

export function OrganizationsPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { organizations, isLoading, isDialogOpen, setIsDialogOpen, createOrganization, removeOrganization } =
    useOrganizations();

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>{t("nav.organizations")}</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span className="text-zinc-500">{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        <PageHeaderActions>
          <NotificationButton />
        </PageHeaderActions>
      </PageHeader>
      <div className="flex flex-col gap-6">
          <OrganizationList
            organizations={organizations}
            onRemove={removeOrganization}
            onAdd={() => setIsDialogOpen(true)}
          />
          {isLoading && (
            <div className="rounded-xl border border-gray-100 bg-white px-4 py-3 text-sm text-gray-500 shadow-sm dark:border-gray-800 dark:bg-gray-900 dark:text-gray-400">
              Loading organizations...
            </div>
          )}
          <AddOrganizationDialog
            open={isDialogOpen}
            onOpenChange={setIsDialogOpen}
            onSubmit={createOrganization}
          />
      </div>
    </PageLayout>
  );
}
