import { useState } from "react";
import { Building2, Eye, FolderDown, MoreVertical, Pencil, RefreshCw, Settings2, Trash2 } from "lucide-react";
import { useI18n } from "../../i18n/i18n";

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
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "../ui/dropdown-menu";

interface OrganizationItemProps {
  organization: OrganizationSummary;
  onRemove: (id: string) => void;
  isActive?: boolean;
  isSyncing?: boolean;
  onSelect?: (id: string) => void;
  onImportRepositories?: (id: string) => void;
  onConfigureSync?: (id: string) => void;
  onSync?: (id: string) => void;
  onEdit?: (id: string) => void;
  providerName?: string | null;
}

function formatRelativeTime(dateStr: string, locale: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60_000);
  if (mins < 60) return new Intl.RelativeTimeFormat(locale, { numeric: "auto" }).format(-mins, "minute");
  const hours = Math.floor(mins / 60);
  if (hours < 24) return new Intl.RelativeTimeFormat(locale, { numeric: "auto" }).format(-hours, "hour");
  const days = Math.floor(hours / 24);
  return new Intl.RelativeTimeFormat(locale, { numeric: "auto" }).format(-days, "day");
}

export function OrganizationItem({
  organization,
  onRemove,
  isSyncing = false,
  onSelect,
  onImportRepositories,
  onConfigureSync,
  onSync,
  onEdit,
  providerName,
}: OrganizationItemProps) {
  const { t, locale } = useI18n();
  const [isConfirmOpen, setIsConfirmOpen] = useState(false);

  return (
    <div
      onClick={() => onSelect?.(organization.id)}
      className="group flex h-10 cursor-pointer items-center gap-2.5 rounded-md pl-3 pr-2 transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.03]"
    >
      <Building2 className="h-4 w-4 shrink-0 text-zinc-400" />
      <span className="truncate text-[13px] font-medium text-zinc-800 dark:text-zinc-100">{organization.name}</span>

      <div className="ml-auto flex shrink-0 items-center gap-2">
        {providerName && (
          <Badge variant="secondary" className="text-[10px] uppercase">{providerName}</Badge>
        )}
        <span className="text-[11px] text-zinc-500 dark:text-zinc-400">
          {organization.selected_repos_count > 0
            ? `${organization.selected_repos_count} ${t("components.orgItem.repos")}`
            : t("components.orgItem.noRepos")}
        </span>
        <span className="hidden items-center gap-1.5 text-[11px] text-zinc-400 dark:text-zinc-500 md:flex">
          <RefreshCw className={`h-3 w-3 shrink-0 ${isSyncing ? "animate-spin text-purple-400" : ""}`} />
          {organization.last_synced_at
            ? formatRelativeTime(organization.last_synced_at, locale)
            : t("components.orgItem.neverSynced")}
        </span>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              onClick={(e) => e.stopPropagation()}
              className="flex h-6 w-6 items-center justify-center rounded text-zinc-400 transition-colors hover:bg-zinc-200 hover:text-zinc-700 dark:hover:bg-zinc-700 dark:hover:text-zinc-200"
            >
              <MoreVertical className="h-4 w-4" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuLabel className="text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">{t("common.open")}</DropdownMenuLabel>
            <DropdownMenuItem onSelect={() => onSelect?.(organization.id)}>
              <Eye className="mr-2 h-4 w-4" />
              {t("common.viewOrganization")}
            </DropdownMenuItem>
            <DropdownMenuItem onSelect={() => onImportRepositories?.(organization.id)}>
              <FolderDown className="mr-2 h-4 w-4" />
              {t("common.importRepositories")}
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuLabel className="text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">{t("common.manage")}</DropdownMenuLabel>
            <DropdownMenuItem onSelect={() => onSync?.(organization.id)} disabled={isSyncing}>
              <RefreshCw className={`mr-2 h-4 w-4 ${isSyncing ? "animate-spin" : ""}`} />
              {t("common.syncNow")}
            </DropdownMenuItem>
            <DropdownMenuItem onSelect={() => onConfigureSync?.(organization.id)}>
              <Settings2 className="mr-2 h-4 w-4" />
              {t("common.configureSync")}
            </DropdownMenuItem>
            <DropdownMenuItem onSelect={() => onEdit?.(organization.id)}>
              <Pencil className="mr-2 h-4 w-4" />
              {t("common.editOrganization")}
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuLabel className="text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">{t("common.dangerZone")}</DropdownMenuLabel>
            <DropdownMenuItem onSelect={() => setIsConfirmOpen(true)} className="text-red-500">
              <Trash2 className="mr-2 h-4 w-4" />
              {t("common.removeOrganization")}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      <AlertDialog open={isConfirmOpen} onOpenChange={setIsConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("components.orgItem.remove.title")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("components.orgItem.remove.description")}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("common.cancel")}</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              onClick={() => {
                onRemove(organization.id);
                setIsConfirmOpen(false);
              }}
            >
              {t("common.remove")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
