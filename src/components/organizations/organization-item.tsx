import { useState } from "react";
import { Eye, FolderDown, MoreVertical, Settings2, Trash2 } from "lucide-react";

import type { OrganizationSummary } from "../../types/organization";
import { Badge } from "../ui/badge";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "../ui/alert-dialog";
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
  onImportRepositories?: (id: string) => void;
  onConfigureSync?: (id: string) => void;
  providerName?: string | null;
}

export function OrganizationItem({
  organization,
  onRemove,
  onSelect,
  onImportRepositories,
  onConfigureSync,
  providerName,
}: OrganizationItemProps) {
  const [isConfirmOpen, setIsConfirmOpen] = useState(false);
  return (
    <div className="flex items-center justify-between rounded-md border px-4 py-3 shadow-sm transition">
      <div className="flex flex-col gap-1">
        <div className="text-sm font-semibold text-gray-900 dark:text-white">{organization.name}</div>
        <div className="text-xs text-gray-500 dark:text-gray-400">
          Added {new Date(organization.created_at).toLocaleString()}
        </div>
        {providerName && (
          <div className="mt-1">
            <Badge variant="secondary" className="text-[10px] uppercase">
              {providerName}
            </Badge>
          </div>
        )}
      </div>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon">
            <MoreVertical className="h-4 w-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onSelect={() => onSelect?.(organization.id)}>
            <Eye className="mr-2 h-4 w-4" />
            View organization
          </DropdownMenuItem>
          <DropdownMenuItem onSelect={() => onImportRepositories?.(organization.id)}>
            <FolderDown className="mr-2 h-4 w-4" />
            Import repositories
          </DropdownMenuItem>
          <DropdownMenuItem onSelect={() => onConfigureSync?.(organization.id)}>
            <Settings2 className="mr-2 h-4 w-4" />
            Configure sync
          </DropdownMenuItem>
          <DropdownMenuItem onSelect={() => setIsConfirmOpen(true)} className="text-red-500">
            <Trash2 className="mr-2 h-4 w-4" />
            Remove organization
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <AlertDialog open={isConfirmOpen} onOpenChange={setIsConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove organization</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently delete the organization and its imported repositories.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              onClick={() => {
                onRemove(organization.id);
                setIsConfirmOpen(false);
              }}
            >
              Remove
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
