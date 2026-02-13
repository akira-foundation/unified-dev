import { MoreHorizontal } from "lucide-react";

import type { OrganizationSummary } from "../../types/organization";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "../ui/dropdown-menu";
import { Button } from "../ui/button";

interface OrganizationItemProps {
  organization: OrganizationSummary;
  onRemove: (id: string) => void;
  isActive?: boolean;
  onSelect?: (id: string) => void;
}

export function OrganizationItem({ organization, onRemove, isActive = false, onSelect }: OrganizationItemProps) {
  return (
    <div
      className={
        "flex items-center justify-between rounded-xl border px-4 py-3 shadow-sm transition " +
        (isActive
          ? "border-blue-500/60 bg-blue-50/60 dark:border-blue-400/40 dark:bg-blue-500/10"
          : "border-gray-100 bg-white dark:border-gray-800 dark:bg-gray-900")
      }
      onClick={() => onSelect?.(organization.id)}
      role={onSelect ? "button" : undefined}
      tabIndex={onSelect ? 0 : undefined}
      onKeyDown={(event) => {
        if (!onSelect) {
          return;
        }
        if (event.key === "Enter" || event.key === " ") {
          onSelect(organization.id);
        }
      }}
    >
      <div className="flex flex-col gap-1">
        <div className="text-sm font-semibold text-gray-900 dark:text-white">{organization.name}</div>
        <div className="text-xs text-gray-500 dark:text-gray-400">
          Added {new Date(organization.created_at).toLocaleString()}
        </div>
      </div>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon">
            <MoreHorizontal className="h-4 w-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onClick={() => onRemove(organization.id)} className="text-red-500">
            Remove organization
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}
