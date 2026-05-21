import { Building2, ChevronRight, RotateCw, Trash2 } from "lucide-react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { Skeleton } from "../ui/skeleton";
import { EmptyState } from "../ui/empty-state";
import type { ProviderOrg } from "@/types/provider";

interface ImportOrgListProps {
  orgs: ProviderOrg[];
  isLoading: boolean;
  errorMessage: string | null;
  syncingOrgId: string | null;
  onSelect: (org: ProviderOrg) => void;
  onSync: (org: ProviderOrg) => void;
  onRemove: (org: ProviderOrg) => void;
}

export function ImportOrgList({ orgs, isLoading, errorMessage, syncingOrgId, onSelect, onSync, onRemove }: ImportOrgListProps) {
  const { t } = useI18n();

  if (isLoading) {
    return (
      <div className="space-y-2">
        <Skeleton className="h-10 w-full" />
        <Skeleton className="h-10 w-full" />
        <Skeleton className="h-10 w-full" />
      </div>
    );
  }

  if (errorMessage) {
    return <EmptyState title={t("pages.importRepos.failedOrgs.title")} description={errorMessage} />;
  }

  if (orgs.length === 0) {
    return <EmptyState title={t("pages.importRepos.noOrgs.title")} description={t("pages.importRepos.noOrgs.description")} />;
  }

  return (
    <div className="flex flex-col">
      {orgs.map((org) => (
        <div
          key={org.id}
          onClick={() => onSelect(org)}
          className="group flex h-11 cursor-pointer items-center gap-2.5 rounded-md pl-3 pr-2 transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.03]"
        >
          <Building2 className="h-4 w-4 shrink-0 text-zinc-400" />
          <span className="truncate text-[13px] font-medium text-zinc-800 dark:text-zinc-100">
            {org.kind === "personal" ? t("pages.importRepos.personal") : org.login}
          </span>
          <div className="ml-auto flex shrink-0 items-center gap-1">
            <button
              onClick={(e) => { e.stopPropagation(); onSync(org); }}
              disabled={syncingOrgId === org.id}
              className="hidden h-6 w-6 items-center justify-center rounded text-zinc-400 transition-colors hover:bg-zinc-200 hover:text-zinc-700 group-hover:flex dark:hover:bg-zinc-700 dark:hover:text-zinc-200 disabled:opacity-50"
              title={t("common.sync")}
            >
              <RotateCw className={cn("h-3.5 w-3.5", syncingOrgId === org.id && "animate-spin")} />
            </button>
            {org.kind === "organization" && (
              <button
                onClick={(e) => { e.stopPropagation(); onRemove(org); }}
                className="hidden h-6 w-6 items-center justify-center rounded text-zinc-400 transition-colors hover:bg-red-500/10 hover:text-red-500 group-hover:flex"
                title={t("common.remove")}
              >
                <Trash2 className="h-3.5 w-3.5" />
              </button>
            )}
            <ChevronRight className="h-4 w-4 text-zinc-300 dark:text-zinc-600" />
          </div>
        </div>
      ))}
    </div>
  );
}
