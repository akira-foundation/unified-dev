import type { OrganizationSummary } from "../../types/organization";
import { Button } from "../ui/button";
import { cn } from "../../lib/utils";

interface SidebarOrganizationItemProps {
  organization: OrganizationSummary;
  isActive: boolean;
  onSelect: (organizationId: string) => void;
}

export function SidebarOrganizationItem({ organization, isActive, onSelect }: SidebarOrganizationItemProps) {
  return (
    <Button
      variant="ghost"
      className={cn(
        "w-full justify-start gap-2 rounded-lg px-3 py-2 text-xs",
        isActive
          ? "bg-zinc-100 text-zinc-900 dark:bg-zinc-900 dark:text-white"
          : "text-muted-foreground hover:bg-zinc-100/60 dark:hover:bg-zinc-900/60",
      )}
      onClick={() => onSelect(organization.id)}
    >
      <span className="truncate">{organization.name}</span>
    </Button>
  );
}
