import { ChevronDown } from "lucide-react";

import type { OrganizationSummary } from "../../types/organization";
import type { ProviderSummary } from "../../types/provider";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "../ui/collapsible";
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
    <Collapsible defaultOpen>
      <div className="flex items-center justify-between gap-2">
        <CollapsibleTrigger asChild>
          <Button variant="ghost" className="w-full justify-between px-3 py-2 text-xs font-semibold">
            <span className="truncate">{provider.name}</span>
            <ChevronDown className="h-4 w-4 text-muted-foreground" />
          </Button>
        </CollapsibleTrigger>
        <Badge variant="secondary" className="hidden text-[10px] uppercase lg:inline-flex">
          {kindLabel(provider.kind)}
        </Badge>
      </div>
      <CollapsibleContent className="mt-2 flex flex-col gap-1">
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
      </CollapsibleContent>
    </Collapsible>
  );
}
