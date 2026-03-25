import {
  flexRender,
  getCoreRowModel,
  getFilteredRowModel,
  getSortedRowModel,
  useReactTable,
  type ColumnDef,
  type SortingState,
} from "@tanstack/react-table";
import { ChevronDown, ChevronUp, ArrowUpDown, CircleDot, ExternalLink, RefreshCw, Trash2 } from "lucide-react";
import { useMemo, useState } from "react";
import { toast } from "sonner";

import { useI18n } from "../../i18n/i18n";
import { Button } from "../ui/button";
import { Card, CardContent } from "../ui/card";
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
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "../ui/table";
import { formatRelativeDate } from "../repos/pr-item";
import { LabelBadge } from "./label-badge";
import type { IssueDto } from "../../types/issue";

interface IssueTableProps {
  issues: IssueDto[];
  onSelect?: (issue: IssueDto) => void;
  onNavigateToPrs?: (repoName: string, orgId: string, prNumber?: number) => void;
  onNavigateToRepo?: (repoName: string, orgId: string) => void;
  onSync?: () => void;
  isSyncing?: boolean;
  disableSync?: boolean;
  onOpenUrl?: (url: string) => void;
  onDelete?: (issue: IssueDto) => Promise<void>;
}

function SortIcon({ sorted }: { sorted: false | "asc" | "desc" }) {
  if (sorted === "asc") return <ChevronUp className="ml-1 inline h-3.5 w-3.5" />;
  if (sorted === "desc") return <ChevronDown className="ml-1 inline h-3.5 w-3.5" />;
  return <ArrowUpDown className="ml-1 inline h-3.5 w-3.5 opacity-40" />;
}

export function IssueTable({
  issues,
  onSelect,
  onNavigateToPrs,
  onNavigateToRepo,
  onSync,
  isSyncing,
  disableSync,
  onOpenUrl,
  onDelete,
}: IssueTableProps) {
  const { t } = useI18n();
  const [sorting, setSorting] = useState<SortingState>([]);
  const [globalFilter, setGlobalFilter] = useState("");
  const [issueToDelete, setIssueToDelete] = useState<IssueDto | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  const columns = useMemo<ColumnDef<IssueDto>[]>(
    () => [
      {
        accessorKey: "title",
        header: ({ column }) => (
          <button
            className="flex items-center cursor-pointer"
            onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
          >
            {t("tables.header.issue")}
            <SortIcon sorted={column.getIsSorted()} />
          </button>
        ),
        cell: ({ row }) => (
          <div
            className="flex flex-col gap-0.5 min-w-0 cursor-pointer"
            onClick={() => onSelect?.(row.original)}
          >
            <span className="text-sm font-semibold text-gray-900 dark:text-white leading-snug hover:underline">
              {row.original.title}
            </span>
            {row.original.labels.length > 0 && (
              <div className="flex items-center gap-1 flex-wrap">
                {row.original.labels.slice(0, 3).map((label) => (
                  <LabelBadge
                    key={label}
                    name={label}
                  />
                ))}
              </div>
            )}
          </div>
        ),
      },
      {
        accessorKey: "number",
        header: ({ column }) => (
          <button
            className="flex items-center cursor-pointer"
            onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
          >
            PR
            <SortIcon sorted={column.getIsSorted()} />
          </button>
        ),
        cell: ({ row }) => {
          const prNumber = row.original.linkedPrNumbers[0];
          if (prNumber === undefined) {
            return <span className="text-sm text-zinc-500 font-medium">—</span>;
          }
          return (
            <span
              className="text-sm text-purple-500 hover:underline cursor-pointer font-medium"
              onClick={() =>
                onNavigateToPrs?.(
                  row.original.repoName,
                  row.original.orgId,
                  prNumber,
                )
              }
            >
              #{prNumber}
            </span>
          );
        },
      },
      {
        accessorKey: "repoName",
        header: ({ column }) => (
          <button
            className="flex items-center cursor-pointer"
            onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
          >
            {t("tables.header.repository")}
            <SortIcon sorted={column.getIsSorted()} />
          </button>
        ),
        cell: ({ row }) => (
          <span
            className="text-sm text-zinc-400 hover:text-zinc-200 hover:underline cursor-pointer transition-colors"
            onClick={() => onNavigateToRepo?.(row.original.repoName, row.original.orgId)}
          >
            {row.original.repoName}
          </span>
        ),
      },
      {
        id: "assignees",
        accessorFn: (row) => row.assignees.join(", "),
        header: t("issues.table.assignees"),
        cell: ({ row }) => (
          <span className="text-sm text-gray-500 dark:text-gray-400">
            {row.original.assignees.length > 0 ? row.original.assignees.join(", ") : "—"}
          </span>
        ),
      },
      {
        id: "statusBadge",
        accessorKey: "status",
        header: ({ column }) => (
          <button
            className="flex items-center cursor-pointer"
            onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
          >
            {t("tables.header.status")}
            <SortIcon sorted={column.getIsSorted()} />
          </button>
        ),
        cell: ({ row }) => {
          const isOpen = row.original.status === "open";
          return (
            <span
              className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] font-medium ${
                isOpen
                  ? "bg-emerald-500/10 border-emerald-500/30 text-emerald-600 dark:text-emerald-400"
                  : "bg-zinc-500/10 border-zinc-500/30 text-zinc-500 dark:text-zinc-400"
              }`}
            >
              {row.original.status}
            </span>
          );
        },
      },
      {
        accessorKey: "updatedAt",
        header: ({ column }) => (
          <button
            className="flex items-center cursor-pointer"
            onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
          >
            {t("tables.header.updated")}
            <SortIcon sorted={column.getIsSorted()} />
          </button>
        ),
        cell: ({ row }) => (
          <span className="text-sm text-gray-500 dark:text-gray-400">
            {formatRelativeDate(row.original.updatedAt)}
          </span>
        ),
      },
      {
        id: "actions",
        header: "",
        cell: ({ row }) => (
          <div className="flex items-center gap-1 justify-end">
            {onOpenUrl && row.original.url && (
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7 text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200"
                onClick={(e) => { e.stopPropagation(); onOpenUrl(row.original.url); }}
                title={t("issues.table.openInBrowser")}
              >
                <ExternalLink className="h-3.5 w-3.5" />
              </Button>
            )}
            {onDelete && row.original.status === "open" && (
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7 text-zinc-400 hover:text-red-500 hover:bg-red-500/10"
                onClick={(e) => { e.stopPropagation(); setIssueToDelete(row.original); }}
                title={t("issues.table.deleteIssue")}
              >
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            )}
          </div>
        ),
      },
    ],
    [t, onSelect, onNavigateToPrs, onNavigateToRepo, onOpenUrl, onDelete],
  );

  const table = useReactTable({
    data: issues,
    columns,
    state: { sorting, globalFilter },
    onSortingChange: setSorting,
    onGlobalFilterChange: setGlobalFilter,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
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
      <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
        <div className="flex flex-row items-center justify-between px-6 py-6">
          <div className="flex flex-row items-center gap-4">
            <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
              <CircleDot size={22} strokeWidth={2} />
            </div>
            <div className="flex flex-col gap-1">
              <span className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">
                {t("issues.page.title")}
              </span>
              <span className="text-[13px] font-medium text-zinc-500/80 leading-none">
                {table.getFilteredRowModel().rows.length} {t("issues.page.total")}
              </span>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {onSync && (
              <Button variant="outline" onClick={onSync} disabled={isSyncing || disableSync}>
                <RefreshCw className={`h-4 w-4 ${isSyncing ? "animate-spin" : ""}`} />
                {t("issues.table.syncIssues")}
              </Button>
            )}
          </div>
        </div>

        <CardContent className="p-0 border-t border-zinc-100 dark:border-zinc-800/50 px-0">
          <div className="overflow-hidden rounded-xl">
            <Table>
              <TableHeader>
                {table.getHeaderGroups().map((headerGroup) => (
                  <TableRow key={headerGroup.id}>
                    {headerGroup.headers.map((header) => (
                      <TableHead key={header.id}>
                        {header.isPlaceholder
                          ? null
                          : flexRender(header.column.columnDef.header, header.getContext())}
                      </TableHead>
                    ))}
                  </TableRow>
                ))}
              </TableHeader>
              <TableBody>
                {table.getRowModel().rows.length === 0 ? (
                  <TableRow>
                    <TableCell
                      colSpan={columns.length}
                      className="py-10 text-center text-sm text-gray-500 dark:text-zinc-600 italic"
                    >
                      {t("issues.table.empty")}
                    </TableCell>
                  </TableRow>
                ) : (
                  table.getRowModel().rows.map((row) => (
                    <TableRow key={row.id}>
                      {row.getVisibleCells().map((cell) => (
                        <TableCell key={cell.id}>
                          {flexRender(cell.column.columnDef.cell, cell.getContext())}
                        </TableCell>
                      ))}
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      <AlertDialog open={!!issueToDelete} onOpenChange={(open) => { if (!open) setIssueToDelete(null); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("issues.table.confirm.title")}</AlertDialogTitle>
            <AlertDialogDescription asChild>
              <div>
                <p className="mb-2">{t("issues.table.confirm.description").replace("{title}", issueToDelete?.title ?? "")}</p>
                <ul className="list-disc pl-4 space-y-1 text-sm">
                  <li>{t("issues.table.confirm.bullet1")}</li>
                  <li>{t("issues.table.confirm.bullet2")}</li>
                  <li>{t("issues.table.confirm.bullet3")}</li>
                </ul>
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("common.cancel")}</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
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
