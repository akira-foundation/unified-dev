import { Plus } from "lucide-react";
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
import { Button } from "@/components/ui/button.tsx";
import { useProviders } from "../hooks/useProviders";

export function OrganizationsPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { organizations, isLoading, isDialogOpen, setIsDialogOpen, createOrganization, removeOrganization } =
    useOrganizations();
  const { providers } = useProviders();

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
          <Button
            onClick={() => setIsDialogOpen(true)}
          >
            <Plus size={18} />
            {t("dashboard.header.newOrg") ?? "New Organization"}
          </Button>
        </PageHeaderActions>
      </PageHeader>
      <div className="flex flex-col gap-6">
        <OrganizationList
          organizations={organizations}
          onRemove={removeOrganization}
        />
        {isLoading && (
          <div className="rounded-xl  bg-white px-4 py-3 text-sm text-gray-500 shadow-sm dark:bg-gray-900 dark:text-gray-400">
            Loading organizations...
          </div>
        )}
        <AddOrganizationDialog
          open={isDialogOpen}
          onOpenChange={setIsDialogOpen}
          providers={providers}
          onSubmit={createOrganization}
        />
      </div>
    </PageLayout>
  );
}
