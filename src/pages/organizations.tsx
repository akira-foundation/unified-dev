import { useOrganizations } from "../hooks/useOrganizations";
import { AddOrganizationDialog } from "../components/organizations/add-organization-dialog";
import { OrganizationList } from "../components/organizations/organization-list";

export function OrganizationsPage() {
  const { organizations, isLoading, isDialogOpen, setIsDialogOpen, createOrganization, removeOrganization } =
    useOrganizations();

  return (
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
  );
}
