import { useState } from "react";
import { Eye, FolderDown, MoreVertical, Pencil, RefreshCw, Settings2, Trash2 } from "lucide-react";
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
import { Button } from "../ui/button";

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
    <div className="flex flex-col gap-2 rounded-lg border border-zinc-200 dark:border-zinc-800 px-4 py-3 bg-zinc-50/50 dark:bg-zinc-800/30">
      <div className="flex items-center justify-between gap-2">
        <button
          className="text-sm font-semibold text-zinc-900 dark:text-white text-left hover:text-purple-600 dark:hover:text-purple-400 transition-colors cursor-pointer truncate"
          onClick={() => onSelect?.(organization.id)}
        >
          {organization.name}
        </button>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon" className="h-6 w-6 shrink-0 -mr-1">
              <MoreVertical className="h-3.5 w-3.5" />
            </Button>
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

      <div className="flex items-center gap-2 flex-wrap">
        {providerName && (
          <Badge variant="secondary" className="text-[10px] uppercase">
            {providerName}
          </Badge>
        )}
        <span className="text-[11px] text-zinc-500 dark:text-zinc-400">
          {organization.selected_repos_count > 0
            ? `${organization.selected_repos_count} ${t("components.orgItem.repos")}`
            : t("components.orgItem.noRepos")}
        </span>
      </div>

      <div className="flex items-center gap-1.5 text-[11px] text-zinc-400 dark:text-zinc-500">
        <RefreshCw className={`h-3 w-3 shrink-0 ${isSyncing ? "animate-spin text-purple-400" : ""}`} />
        {organization.last_synced_at
          ? `${t("components.orgItem.lastSync")} ${formatRelativeTime(organization.last_synced_at, locale)}`
          : t("components.orgItem.neverSynced")}
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
