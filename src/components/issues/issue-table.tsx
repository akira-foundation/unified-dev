import { ChevronDown, ChevronRight } from "lucide-react";
import { useMemo, useState, type ReactNode } from "react";
import { toast } from "sonner";

import { useFiltersStore } from "../../stores/filters-store";
import { useI18n } from "../../i18n/i18n";
import { AppbarActions } from "@/components/layout/appbar-actions";
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
import { IssueToolbar } from "./issue-toolbar";
import { IssueRow } from "./issue-row";
import { COLUMN_LABEL, GROUP_ORDER, StatusIcon } from "./issue-status";
import { useDelegateIssue } from "../../hooks/useDelegateIssue";
import { issueToColumn, type IssueColumnId, type IssueDto } from "../../types/issue";

interface IssueTableProps {
  issues: IssueDto[];
  filterNamespace?: string;
  actionsInAppbar?: boolean;
  onSelect?: (issue: IssueDto) => void;
  onNavigateToPrs?: (repoName: string, orgId: string, prNumber?: number) => void;
  onNavigateToRepo?: (repoName: string, orgId: string) => void;
  onSync?: () => void;
  syncOptions?: Array<{ label: string; onSelect: () => void }>;
  isSyncing?: boolean;
  disableSync?: boolean;
  onOpenUrl?: (url: string) => void;
  onDelete?: (issue: IssueDto) => Promise<void>;
  onAssignToMe?: (issue: IssueDto) => Promise<void> | void;
}

function ToolbarActions({ inAppbar, children }: { inAppbar: boolean; children: ReactNode }) {
  return inAppbar ? <AppbarActions>{children}</AppbarActions> : <>{children}</>;
}

export function IssueTable({
  issues,
  filterNamespace = "issues",
  actionsInAppbar = false,
  onSelect,
  onNavigateToPrs,
  onNavigateToRepo,
  onSync,
  syncOptions,
  isSyncing,
  disableSync,
  onOpenUrl,
  onDelete,
  onAssignToMe,
}: IssueTableProps) {
  const { t } = useI18n();
  const [issueToDelete, setIssueToDelete] = useState<IssueDto | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);
  const [collapsed, setCollapsed] = useState<Set<IssueColumnId>>(new Set());
  const { delegateIssue } = useDelegateIssue();

  const storeFilters = useFiltersStore((s) => s.filters[filterNamespace]);
  const filters = useMemo(
    () => ({
      statuses: storeFilters?.statuses ?? [],
      sources: storeFilters?.sources ?? [],
      labels: storeFilters?.labels ?? [],
      assignees: storeFilters?.assignees ?? [],
      repos: storeFilters?.repos ?? [],
    }),
    [storeFilters],
  );

  const filteredIssues = useMemo(() => {
    return issues.filter((issue) => {
      if (filters.statuses.length > 0 && !filters.statuses.includes(issue.status)) return false;
      if (filters.sources.length > 0 && !filters.sources.includes(issue.syncWithProvider ? "synced" : "local")) return false;
      if (filters.labels.length > 0 && !filters.labels.some((l) => issue.labels.includes(l))) return false;
      if (filters.assignees.length > 0 && !filters.assignees.some((a) => issue.assignees.includes(a))) return false;
      if (filters.repos.length > 0 && !filters.repos.includes(issue.repoName)) return false;
      return true;
    });
  }, [issues, filters]);

  const grouped = useMemo(() => {
    const map: Record<IssueColumnId, IssueDto[]> = { backlog: [], todo: [], in_progress: [], done: [] };
    filteredIssues.forEach((issue) => map[issueToColumn(issue)].push(issue));
    GROUP_ORDER.forEach((col) => map[col].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)));
    return map;
  }, [filteredIssues]);

  const toggleGroup = (col: IssueColumnId) =>
    setCollapsed((prev) => {
      const next = new Set(prev);
      if (next.has(col)) next.delete(col);
      else next.add(col);
      return next;
    });

  const handleConfirmDelete = async () => {
    if (!issueToDelete || !onDelete) return;
    const issue = issueToDelete;
    setIssueToDelete(null);
    setIsDeleting(true);
    const id = toast.loading(t("issues.table.toast.deleting"));
    try {
      await onDelete(issue);
      toast.success(t("issues.table.toast.deleted"), { id });
    } catch (error) {
      toast.error(error instanceof Error ? error.message : String(error), { id });
    } finally {
      setIsDeleting(false);
    }
  };

  return (
    <>
      <ToolbarActions inAppbar={actionsInAppbar}>
        <IssueToolbar
          filterNamespace={filterNamespace}
          onSync={onSync}
          syncOptions={syncOptions}
          isSyncing={isSyncing}
          disableSync={disableSync}
        />
      </ToolbarActions>

      {filteredIssues.length === 0 ? (
        <p className="px-3 py-16 text-center text-sm text-zinc-500 dark:text-zinc-600">{t("issues.table.empty")}</p>
      ) : (
        <div className="flex flex-col">
          {GROUP_ORDER.map((col) => {
            const rows = grouped[col];
            if (rows.length === 0) return null;
            const isCollapsed = collapsed.has(col);
            return (
              <section key={col}>
                <button
                  onClick={() => toggleGroup(col)}
                  className="flex w-full items-center gap-2 px-3 py-1.5 text-left"
                >
                  {isCollapsed ? (
                    <ChevronRight className="h-3.5 w-3.5 text-zinc-500" />
                  ) : (
                    <ChevronDown className="h-3.5 w-3.5 text-zinc-500" />
                  )}
                  <StatusIcon column={col} />
                  <span className="text-[13px] font-semibold text-zinc-700 dark:text-zinc-200">{COLUMN_LABEL[col]}</span>
                  <span className="text-[12px] font-medium text-zinc-500">{rows.length}</span>
                </button>

                {!isCollapsed &&
                  rows.map((issue) => (
                    <IssueRow
                      key={issue.id}
                      issue={issue}
                      column={col}
                      onSelect={onSelect}
                      onNavigateToPrs={onNavigateToPrs}
                      onNavigateToRepo={onNavigateToRepo}
                      onOpenUrl={onOpenUrl}
                      onDelete={onDelete}
                      onAssignToMe={onAssignToMe}
                      delegateIssue={delegateIssue}
                      t={t}
                      setIssueToDelete={setIssueToDelete}
                    />
                  ))}
              </section>
            );
          })}
        </div>
      )}

      <AlertDialog open={!!issueToDelete} onOpenChange={(open) => { if (!open) setIssueToDelete(null); }}>
        <AlertDialogContent className="max-w-[420px]">
          <AlertDialogHeader>
            <AlertDialogTitle>{t("issues.table.confirm.title")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("issues.table.confirm.description").replace("{title}", issueToDelete?.title ?? "")}
            </AlertDialogDescription>
          </AlertDialogHeader>

          <div className="px-5 py-4">
            <ul className="list-disc space-y-1 pl-4 text-sm text-muted-foreground">
              <li>{t("issues.table.confirm.bullet1")}</li>
              <li>{t("issues.table.confirm.bullet2")}</li>
              <li>{t("issues.table.confirm.bullet3")}</li>
            </ul>
          </div>

          <AlertDialogFooter>
            <AlertDialogCancel size="sm">{t("common.cancel")}</AlertDialogCancel>
            <AlertDialogAction
              size="sm"
              className="flex-1 bg-red-500 text-white hover:bg-red-600"
              disabled={isDeleting}
              onClick={() => void handleConfirmDelete()}
            >
              {t("issues.table.confirm.action")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
