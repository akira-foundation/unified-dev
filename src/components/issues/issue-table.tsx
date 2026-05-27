import { ChevronDown, ChevronRight } from "lucide-react";
import { useMemo, useRef, useState, type ReactNode } from "react";
import { useVirtualizer } from "@tanstack/react-virtual";
import { EmptyState } from "../ui/empty-state";
import { toast } from "sonner";

import { useFilteredIssues } from "@/hooks/useFilteredIssues";
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
  showToolbar?: boolean;
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
  onAssignSource?: (issue: IssueDto) => void;
}

function ToolbarActions({ inAppbar, children }: { inAppbar: boolean; children: ReactNode }) {
  return inAppbar ? <AppbarActions>{children}</AppbarActions> : <>{children}</>;
}

export function IssueTable({
  issues,
  filterNamespace = "issues",
  actionsInAppbar = false,
  showToolbar = true,
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
  onAssignSource,
}: IssueTableProps) {
  const { t } = useI18n();
  const parentRef = useRef<HTMLDivElement>(null);
  const [issueToDelete, setIssueToDelete] = useState<IssueDto | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);
  const [collapsed, setCollapsed] = useState<Set<IssueColumnId>>(new Set());
  const [scrollTop, setScrollTop] = useState(0);
  const { delegateIssue } = useDelegateIssue();

  const filteredIssues = useFilteredIssues(issues, filterNamespace);

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

  type FlatItem =
    | { kind: "header"; col: IssueColumnId; count: number }
    | { kind: "row"; issue: IssueDto; col: IssueColumnId };

  const flatItems = useMemo(() => {
    const out: FlatItem[] = [];
    GROUP_ORDER.forEach((col) => {
      const rows = grouped[col];
      if (rows.length === 0) return;
      out.push({ kind: "header", col, count: rows.length });
      if (!collapsed.has(col)) rows.forEach((issue) => out.push({ kind: "row", issue, col }));
    });
    return out;
  }, [grouped, collapsed]);

  const virtualizer = useVirtualizer({
    count: flatItems.length,
    getScrollElement: () => parentRef.current,
    estimateSize: (index) => (flatItems[index].kind === "header" ? 34 : 36),
    overscan: 12,
  });

  const virtualItems = virtualizer.getVirtualItems();

  const activeCol = useMemo<IssueColumnId | null>(() => {
    let col: IssueColumnId | null = flatItems[0]?.col ?? null;
    for (const vi of virtualItems) {
      if (vi.start <= scrollTop + 1) col = flatItems[vi.index].col;
      else break;
    }
    return col;
  }, [virtualItems, flatItems, scrollTop]);

  const renderGroupHeader = (col: IssueColumnId, count: number) => (
    <button
      onClick={() => toggleGroup(col)}
      className="flex w-full items-center gap-2 bg-background px-3 py-1.5 text-left"
    >
      <StatusIcon column={col} />
      <span className="text-[13px] font-semibold text-zinc-700 dark:text-zinc-200">{COLUMN_LABEL[col]}</span>
      <span className="text-[12px] font-medium text-zinc-500">{count}</span>
      {collapsed.has(col) ? (
        <ChevronRight className="ml-auto h-3.5 w-3.5 text-zinc-500" />
      ) : (
        <ChevronDown className="ml-auto h-3.5 w-3.5 text-zinc-500" />
      )}
    </button>
  );

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
      {showToolbar && (
        <ToolbarActions inAppbar={actionsInAppbar}>
          <IssueToolbar
            filterNamespace={filterNamespace}
            onSync={onSync}
            syncOptions={syncOptions}
            isSyncing={isSyncing}
            disableSync={disableSync}
          />
        </ToolbarActions>
      )}

      <div
        ref={parentRef}
        onScroll={(e) => setScrollTop(e.currentTarget.scrollTop)}
        className="h-full overflow-y-auto custom-scrollbar px-4 pb-4 md:px-6 md:pb-6"
      >
      {filteredIssues.length === 0 ? (
        <EmptyState title={t("issues.table.empty")} />
      ) : (
        <>
        {activeCol && (
          <div className="sticky top-0 z-20 -mb-[34px]">
            {renderGroupHeader(activeCol, grouped[activeCol].length)}
          </div>
        )}
        <div style={{ height: virtualizer.getTotalSize(), position: "relative" }}>
          {virtualizer.getVirtualItems().map((virtualItem) => {
            const item = flatItems[virtualItem.index];
            return (
              <div
                key={virtualItem.key}
                data-index={virtualItem.index}
                ref={virtualizer.measureElement}
                style={{
                  position: "absolute",
                  top: 0,
                  left: 0,
                  width: "100%",
                  transform: `translateY(${virtualItem.start}px)`,
                }}
              >
                {item.kind === "header" ? (
                  renderGroupHeader(item.col, item.count)
                ) : (
                  <IssueRow
                    issue={item.issue}
                    column={item.col}
                    onSelect={onSelect}
                    onNavigateToPrs={onNavigateToPrs}
                    onNavigateToRepo={onNavigateToRepo}
                    onOpenUrl={onOpenUrl}
                    onDelete={onDelete}
                    onAssignToMe={onAssignToMe}
                    onAssignSource={onAssignSource}
                    delegateIssue={delegateIssue}
                    t={t}
                    setIssueToDelete={setIssueToDelete}
                  />
                )}
              </div>
            );
          })}
        </div>
        </>
      )}
      </div>

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
