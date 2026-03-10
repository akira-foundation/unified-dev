import type { OrganizationSummary } from "../../types/organization";
import type { ProviderSummary } from "../../types/provider";
import { Badge } from "../ui/badge";
import { SidebarOrganizationItem } from "./sidebar-organization-item";

interface SidebarProviderSectionProps {
  provider: ProviderSummary;
  organizations: OrganizationSummary[];
  activeOrganizationId: string | null;
  onSelectOrganization: (organizationId: string) => void;
}

const kindLabel = (kind: string) => {
  switch (kind) {
    case "github":
      return "GitHub";
    case "gitlab":
      return "GitLab";
    case "bitbucket":
      return "Bitbucket";
    default:
      return kind;
  }
};

export function SidebarProviderSection({
  provider,
  organizations,
  activeOrganizationId,
  onSelectOrganization,
}: SidebarProviderSectionProps) {
  return (
    <div>
      <div className="flex items-center justify-between gap-2 px-3 py-2">
        <span className="truncate text-xs font-semibold text-foreground">{provider.name}</span>
        <Badge variant="secondary" className="hidden text-[10px] uppercase lg:inline-flex">
          {kindLabel(provider.kind)}
        </Badge>
      </div>
      <div className="mt-2 flex flex-col gap-1">
        {organizations.length === 0 ? (
          <div className="px-3 py-2 text-xs text-muted-foreground">No organizations</div>
        ) : (
          organizations.map((organization) => (
            <SidebarOrganizationItem
              key={organization.id}
              organization={organization}
              isActive={activeOrganizationId === organization.id}
              onSelect={onSelectOrganization}
            />
          ))
        )}
      </div>
    </div>
  );
}
