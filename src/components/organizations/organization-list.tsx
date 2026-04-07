import { Building2, Plus } from "lucide-react";
import type { OrganizationSummary } from "../../types/organization";
import { Card, CardDescription, CardTitle } from "../ui/card";
import { Button } from "../ui/button";
import { OrganizationItem } from "./organization-item";
import { useI18n } from "../../i18n/i18n";

interface OrganizationListProps {
  organizations: OrganizationSummary[];
  onRemove: (id: string) => void;
  activeId?: string | null;
  syncingIds?: Set<string>;
  onSelect?: (id: string) => void;
  onImportRepositories?: (id: string) => void;
  onConfigureSync?: (id: string) => void;
  onSync?: (id: string) => void;
  onEdit?: (id: string) => void;
  onCreate?: () => void;
  providerNameById?: Record<string, string>;
}

export function OrganizationList({
  organizations,
  onRemove,
  activeId,
  syncingIds,
  onSelect,
  onImportRepositories,
  onConfigureSync,
  onSync,
  onEdit,
  onCreate,
  providerNameById,
}: OrganizationListProps) {
  const { t } = useI18n();

  return (
    <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
      <div className="flex flex-row items-center justify-between px-6 py-6">
        <div className="flex flex-row items-center gap-4">
          <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
            <Building2 size={22} strokeWidth={2} />
          </div>
          <div className="flex flex-col gap-1">
            <CardTitle className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">
              {t("components.orgList.title")}
            </CardTitle>
            <CardDescription className="text-[13px] font-medium text-zinc-500/80 leading-none">
              {t("components.orgList.description")}
            </CardDescription>
          </div>
        </div>
        {onCreate && (
          <Button onClick={onCreate}>
            <Plus size={18} />
            {t("common.newOrganization")}
          </Button>
        )}
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 px-6 pb-6">
        {organizations.map((organization) => (
          <OrganizationItem
            key={organization.id}
            organization={organization}
            onRemove={onRemove}
            isSyncing={syncingIds?.has(organization.id) ?? false}
            isActive={activeId === organization.id}
            onSelect={onSelect}
            onImportRepositories={onImportRepositories}
            onConfigureSync={onConfigureSync}
            onSync={onSync}
            onEdit={onEdit}
            providerName={organization.provider_id ? providerNameById?.[organization.provider_id] : undefined}
          />
        ))}
      </div>
    </Card>
  );
}
