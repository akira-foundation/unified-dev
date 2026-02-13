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
}

export function OrganizationItem({ organization, onRemove }: OrganizationItemProps) {
  return (
    <div className="flex items-center justify-between rounded-xl border border-gray-100 bg-white px-4 py-3 shadow-sm dark:border-gray-800 dark:bg-gray-900">
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
