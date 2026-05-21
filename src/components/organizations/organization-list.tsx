import type { OrganizationSummary } from "../../types/organization";
import { OrganizationItem } from "./organization-item";

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
  providerNameById,
}: OrganizationListProps) {
  return (
    <div className="flex flex-col">
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
  );
}
