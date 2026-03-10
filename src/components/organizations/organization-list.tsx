import { Plus } from "lucide-react";
import type { OrganizationSummary } from "../../types/organization";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../ui/card";
import { Button } from "../ui/button";
import { OrganizationItem } from "./organization-item";

interface OrganizationListProps {
  organizations: OrganizationSummary[];
  onRemove: (id: string) => void;
  activeId?: string | null;
  onSelect?: (id: string) => void;
  onImportRepositories?: (id: string) => void;
  onConfigureSync?: (id: string) => void;
  onCreate?: () => void;
  providerNameById?: Record<string, string>;
}

export function OrganizationList({
  organizations,
  onRemove,
  activeId,
  onSelect,
  onImportRepositories,
  onConfigureSync,
  onCreate,
  providerNameById,
}: OrganizationListProps) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <div>
          <CardTitle>Organizations</CardTitle>
          <CardDescription>Connect GitHub organizations and manage sync settings.</CardDescription>
        </div>
        {onCreate && (
          <Button variant="outline" size="sm" onClick={onCreate} className="gap-2">
            <Plus className="h-4 w-4" />
            New Organization
          </Button>
        )}
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {organizations.length === 0 ? (
          <div className="rounded-xl  px-4 py-6 text-sm text-gray-500  dark:text-gray-400">
            No organizations configured yet.
          </div>
        ) : (
          organizations.map((organization) => (
            <OrganizationItem
              key={organization.id}
              organization={organization}
              onRemove={onRemove}
              isActive={activeId === organization.id}
              onSelect={onSelect}
              onImportRepositories={onImportRepositories}
              onConfigureSync={onConfigureSync}
              providerName={providerNameById?.[organization.provider_id]}
            />
          ))
        )}
      </CardContent>
    </Card>
  );
}
