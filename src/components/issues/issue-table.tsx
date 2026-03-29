import {
  flexRender,
  getCoreRowModel,
  getFilteredRowModel,
  getSortedRowModel,
  useReactTable,
  type ColumnDef,
  type SortingState,
} from "@tanstack/react-table";
import { ChevronDown, ChevronUp, ArrowUpDown, Bot, CircleDot, ExternalLink, Filter, MoreVertical, RefreshCw, Trash2 } from "lucide-react";
import { useMemo, useState } from "react";
import { toast } from "sonner";

import { useFiltersStore } from "../../stores/filters-store";
import { useI18n } from "../../i18n/i18n";
import {
  FilterPopover,
  FilterPopoverContent,
  FilterPopoverTrigger,
} from "../filters/filter-popover";
import {
  FilterPopoverHeader,
  FilterSectionDivider,
} from "../filters/filter-popover-section";
import { Button } from "../ui/button";
import { Card, CardContent } from "../ui/card";
import { Tooltip, TooltipContent, TooltipTrigger } from "../ui/tooltip";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "../ui/dropdown-menu";
import { MultiSelectFilterSection } from "../filters/multi-select-filter-section";
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
import { useDelegateIssue } from "../../hooks/useDelegateIssue";
import type { IssueDto } from "../../types/issue";

interface IssueTableProps {
  issues: IssueDto[];
  filterNamespace?: string;
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

function SortIcon({ sorted }: { sorted: false | "asc" | "desc" }) {
  if (sorted === "asc") return <ChevronUp className="ml-1 inline h-3.5 w-3.5" />;
  if (sorted === "desc") return <ChevronDown className="ml-1 inline h-3.5 w-3.5" />;
  return <ArrowUpDown className="ml-1 inline h-3.5 w-3.5 opacity-40" />;
}

function IssueActionsMenu({
  issue,
  onSelect,
  onOpenUrl,
  onAssignToMe,
  onDelete,
  delegateIssue,
  t,
  setIssueToDelete,
}: {
  issue: IssueDto;
  onSelect?: (issue: IssueDto) => void;
  onOpenUrl?: (url: string) => void;
  onAssignToMe?: (issue: IssueDto) => Promise<void> | void;
  onDelete?: (issue: IssueDto) => Promise<void>;
  delegateIssue: (issue: IssueDto) => Promise<void>;
  t: (key: string) => string;
  setIssueToDelete: (issue: IssueDto | null) => void;
}) {
  const [open, setOpen] = useState(false);

  return (
    <div className="flex justify-end" onClick={(e) => e.stopPropagation()} onPointerDown={(e) => e.stopPropagation()}>
      <DropdownMenu open={open} onOpenChange={setOpen} modal={false}>
        <DropdownMenuTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7 text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200"
            onClick={(e) => e.stopPropagation()}
            onPointerDown={(e) => e.stopPropagation()}
          >
            <MoreVertical className="h-4 w-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent
          align="end"
          onCloseAutoFocus={(e) => e.preventDefault()}
          onPointerDown={(e) => e.stopPropagation()}
        >
          <DropdownMenuLabel className="text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">
            {t("common.open")}
          </DropdownMenuLabel>
          {onSelect && (
            <DropdownMenuItem onSelect={() => onSelect(issue)}>
              <CircleDot className="mr-2 h-4 w-4" />
              {t("issues.table.viewIssue")}
            </DropdownMenuItem>
          )}
          {onOpenUrl && issue.url && (
            <DropdownMenuItem onSelect={() => onOpenUrl(issue.url)}>
              <ExternalLink className="mr-2 h-4 w-4" />
              {t("issues.table.openInBrowser")}
            </DropdownMenuItem>
          )}
          <DropdownMenuSeparator />
          <DropdownMenuLabel className="text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">
            {t("common.manage")}
          </DropdownMenuLabel>
          <DropdownMenuItem onSelect={() => void delegateIssue(issue)}>
            <Bot className="mr-2 h-4 w-4" />
            {t("issues.detail.delegate")}
          </DropdownMenuItem>
          {onAssignToMe && issue.status === "open" && (
            <DropdownMenuItem onSelect={() => void onAssignToMe(issue)}>
              <CircleDot className="mr-2 h-4 w-4" />
              {t("issues.table.assignToMe")}
            </DropdownMenuItem>
          )}
          {onDelete && issue.status === "open" && (
            <>
              <DropdownMenuSeparator />
              <DropdownMenuLabel className="text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">
                {t("common.dangerZone")}
              </DropdownMenuLabel>
              <DropdownMenuItem
                onSelect={() => setIssueToDelete(issue)}
                className="text-red-500 focus:text-red-500 focus:bg-red-500/10"
              >
                <Trash2 className="mr-2 h-4 w-4" />
                {t("issues.table.deleteIssue")}
              </DropdownMenuItem>
            </>
          )}
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}

export function IssueTable({
  issues,
  filterNamespace = "issues",
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
  const [sorting, setSorting] = useState<SortingState>([]);
  const [issueToDelete, setIssueToDelete] = useState<IssueDto | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);
  const { delegateIssue } = useDelegateIssue();

  const setFilter = useFiltersStore((s) => s.setFilter);
  const clearFilters = useFiltersStore((s) => s.clearFilters);
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

  const allLabels = useMemo(() => {
    const set = new Set<string>();
    issues.forEach((i) => i.labels.forEach((l) => set.add(l)));
    return Array.from(set).sort();
  }, [issues]);

  const allAssignees = useMemo(() => {
    const set = new Set<string>();
    issues.forEach((i) => i.assignees.forEach((a) => set.add(a)));
    return Array.from(set).sort();
  }, [issues]);

  const allRepos = useMemo(() => {
    const set = new Set<string>();
    issues.forEach((i) => set.add(i.repoName));
    return Array.from(set).sort();
  }, [issues]);

  const duplicateIssueTitleKeys = useMemo(() => {
    const counts = new Map<string, number>();

    issues.forEach((issue) => {
      const key = `${issue.repoName}::${issue.title.trim().toLowerCase()}`;
      counts.set(key, (counts.get(key) ?? 0) + 1);
    });

    return new Set(
      Array.from(counts.entries())
        .filter(([, count]) => count > 1)
        .map(([key]) => key),
    );
  }, [issues]);

  const activeFilterCount =
    filters.statuses.length + filters.sources.length + filters.labels.length + filters.assignees.length + filters.repos.length;

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
          (() => {
            const issue = row.original;
            const duplicateKey = `${issue.repoName}::${issue.title.trim().toLowerCase()}`;
            const isDuplicate = duplicateIssueTitleKeys.has(duplicateKey);
            const disambiguator = `#${issue.number}`;

            return (
              <div
                className="flex flex-col gap-0.5 min-w-0 cursor-pointer"
                onClick={() => onSelect?.(issue)}
              >
                <div className="flex items-center gap-2 min-w-0">
                  <span className="truncate text-sm font-semibold text-gray-900 dark:text-white leading-snug hover:underline">
                    {issue.title}
                  </span>
                  <span
                    className={`shrink-0 rounded-[6px] px-1.5 py-0.5 text-[10px] font-medium ${
                      issue.syncWithProvider
                        ? "bg-emerald-500/10 text-emerald-400"
                        : "bg-zinc-500/10 text-zinc-400"
                    }`}
                  >
                    {issue.syncWithProvider ? "sync" : "local"}
                  </span>
                </div>
                <div className="flex items-center gap-1.5 flex-wrap text-xs text-zinc-500 dark:text-zinc-400">
                  <span>{issue.repoName}</span>
                  {isDuplicate ? (
                    <>
                      <span className="text-zinc-300 dark:text-zinc-600">•</span>
                      <span>{disambiguator}</span>
                    </>
                  ) : null}
                </div>
                {issue.labels.length > 0 && (
                  <div className="flex items-center gap-1 flex-wrap">
                    {issue.labels.slice(0, 3).map((label) => (
                      <LabelBadge key={label} name={label} />
                    ))}
                  </div>
                )}
              </div>
            );
          })()
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
          <IssueActionsMenu
            issue={row.original}
            onSelect={onSelect}
            onOpenUrl={onOpenUrl}
            onAssignToMe={onAssignToMe}
            onDelete={onDelete}
            delegateIssue={delegateIssue}
            t={t}
            setIssueToDelete={setIssueToDelete}
          />
        ),
      },
    ],
    [t, onSelect, onNavigateToPrs, onNavigateToRepo, onOpenUrl, onDelete, onAssignToMe, delegateIssue, duplicateIssueTitleKeys],
  );

  const table = useReactTable({
    data: filteredIssues,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
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
                {filteredIssues.length} {t("issues.page.total")}
              </span>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {onSync && (
              syncOptions && syncOptions.length > 0 ? (
                <DropdownMenu>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <DropdownMenuTrigger asChild>
                        <Button variant="outline" size="icon" disabled={isSyncing || disableSync}>
                          <RefreshCw className={`h-4 w-4 ${isSyncing ? "animate-spin" : ""}`} />
                        </Button>
                      </DropdownMenuTrigger>
                    </TooltipTrigger>
                    <TooltipContent>{t("issues.table.syncIssues")}</TooltipContent>
                  </Tooltip>
                  <DropdownMenuContent align="end">
                    {syncOptions.map((option) => (
                      <DropdownMenuItem key={option.label} onSelect={option.onSelect}>
                        {option.label}
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuContent>
                </DropdownMenu>
              ) : (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button variant="outline" size="icon" onClick={onSync} disabled={isSyncing || disableSync}>
                      <RefreshCw className={`h-4 w-4 ${isSyncing ? "animate-spin" : ""}`} />
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent>{t("issues.table.syncIssues")}</TooltipContent>
                </Tooltip>
              )
            )}

            <FilterPopover>
              <FilterPopoverTrigger asChild>
                <Button variant="outline" size="icon" className="relative">
                  <Filter className="h-4 w-4" />
                  {activeFilterCount > 0 && (
                    <span className="absolute -top-1.5 -right-1.5 h-4 w-4 rounded-full bg-purple-500 text-[10px] font-bold text-white flex items-center justify-center">
                      {activeFilterCount}
                    </span>
                  )}
                </Button>
              </FilterPopoverTrigger>
              <FilterPopoverContent>
                <FilterPopoverHeader
                  title={t("issues.table.filter")}
                  clearLabel={t("issues.table.filter.clear")}
                  canClear={activeFilterCount > 0}
                  onClear={() => clearFilters(filterNamespace)}
                />
                <FilterSectionDivider />

                <MultiSelectFilterSection
                  label={t("issues.table.filter.status")}
                  placeholder={t("issues.table.filter.status")}
                  items={(["open", "closed"] as const).map((status) => t(`issues.table.filter.${status}`))}
                  value={filters.statuses.map((status) => t(`issues.table.filter.${status}`))}
                  onValueChange={(values) => {
                    const next = values.map((value) => {
                      if (value === t("issues.table.filter.open")) return "open";
                      if (value === t("issues.table.filter.closed")) return "closed";
                      return value;
                    });
                    setFilter(filterNamespace, "statuses", next);
                  }}
                />

                <FilterSectionDivider />

                <MultiSelectFilterSection
                  label="Source"
                  placeholder="Source"
                  items={["Synced", "Local"]}
                  value={filters.sources.map((source) => source === "synced" ? "Synced" : "Local")}
                  onValueChange={(values) => {
                    const next = values.map((value) => value === "Synced" ? "synced" : "local");
                    setFilter(filterNamespace, "sources", next);
                  }}
                />

                {/* Repositories */}
                {allRepos.length > 1 && (
                  <>
                    <FilterSectionDivider />
                    <MultiSelectFilterSection
                      label={t("issues.table.filter.repositories")}
                      placeholder={t("issues.table.filter.repoSearch")}
                      items={allRepos}
                      value={filters.repos}
                      onValueChange={(value) => setFilter(filterNamespace, "repos", value)}
                    />
                  </>
                )}

                {/* Labels */}
                {allLabels.length > 0 && (
                  <>
                    <FilterSectionDivider />
                    <MultiSelectFilterSection
                      label={t("issues.table.filter.labels")}
                      placeholder={t("issues.table.filter.labelSearch")}
                      items={allLabels}
                      value={filters.labels}
                      onValueChange={(value) => setFilter(filterNamespace, "labels", value)}
                    />
                  </>
                )}

                {/* Assignees */}
                {allAssignees.length > 0 && (
                  <>
                    <FilterSectionDivider />
                    <MultiSelectFilterSection
                      label={t("issues.table.filter.assignees")}
                      placeholder={t("issues.table.filter.assigneeSearch")}
                      items={allAssignees}
                      value={filters.assignees}
                      onValueChange={(value) => setFilter(filterNamespace, "assignees", value)}
                    />
                  </>
                )}
              </FilterPopoverContent>
            </FilterPopover>
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
