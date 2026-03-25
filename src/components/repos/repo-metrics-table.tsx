import {
  type ColumnDef,
  type SortingState,
  getCoreRowModel,
  getSortedRowModel,
  useReactTable,
  flexRender,
} from "@tanstack/react-table";
import { useMemo, useState } from "react";
import type { OrganizationRepoWithOrg } from "../../types/organization";
import { ArrowUpDown, ChevronDown, ChevronUp, Eye, Filter, FolderGit2, GitPullRequest, MoreVertical, Plus, RefreshCw, RotateCw } from "lucide-react";
import { useI18n } from "../../i18n/i18n";
import { cn } from "@/lib/utils";
import { useRepoActions } from "../../hooks/useRepoActions";
import { useFiltersStore } from "../../stores/filters-store";

import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent } from "../ui/card";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../ui/dropdown-menu";
import { Popover, PopoverContent, PopoverTrigger } from "../ui/popover";
import { Switch } from "../ui/switch";
import {
  Combobox,
  ComboboxChips,
  ComboboxChip,
  ComboboxChipsInput,
  ComboboxContent,
  ComboboxEmpty,
  ComboboxItem,
  ComboboxList,
  ComboboxValue,
} from "../ui/combobox";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";
import { Tooltip, TooltipContent, TooltipTrigger } from "../ui/tooltip";

interface RepoMetricsTableProps {
  repos: OrganizationRepoWithOrg[];
  title?: string;
  filterNamespace?: string;
  onCreate?: () => void;
  onSync?: () => void;
  onSyncRepo?: (repo: OrganizationRepoWithOrg) => void;
  onOrganizationClick?: (repo: OrganizationRepoWithOrg) => void;
  isSyncing?: boolean;
  syncingRepoId?: string;
  hideOrganization?: boolean;
}

function SortIcon({ sorted }: { sorted: false | "asc" | "desc" }) {
  if (sorted === "asc") return <ChevronUp className="ml-1 inline h-3.5 w-3.5" />;
  if (sorted === "desc") return <ChevronDown className="ml-1 inline h-3.5 w-3.5" />;
  return <ArrowUpDown className="ml-1 inline h-3.5 w-3.5 opacity-40" />;
}

function toggleItem(arr: string[], item: string): string[] {
  return arr.includes(item) ? arr.filter((x) => x !== item) : [...arr, item];
}

export function RepoMetricsTable({
  repos,
  title = "Repositories",
  filterNamespace = "repos",
  onCreate,
  onSync,
  onSyncRepo,
  onOrganizationClick,
  isSyncing,
  syncingRepoId,
  hideOrganization,
}: RepoMetricsTableProps) {
  const { t } = useI18n();
  const { handleViewRepo, handleViewPrs, handleNewTask } = useRepoActions();
  const [sorting, setSorting] = useState<SortingState>([]);

  const setFilter = useFiltersStore((s) => s.setFilter);
  const clearFilters = useFiltersStore((s) => s.clearFilters);
  const storeFilters = useFiltersStore((s) => s.filters[filterNamespace]);

  const filters = useMemo(
    () => ({
      visibility: storeFilters?.visibility ?? [],
      organizations: storeFilters?.organizations ?? [],
      hasOpenPrs: storeFilters?.hasOpenPrs ?? [],
      defaultBranch: storeFilters?.defaultBranch ?? [],
    }),
    [storeFilters],
  );

  const allOrganizations = useMemo(() => {
    const set = new Set<string>();
    repos.forEach((r) => set.add(r.organization_name));
    return Array.from(set).sort();
  }, [repos]);

  const allBranches = useMemo(() => {
    const set = new Set<string>();
    repos.forEach((r) => set.add(r.default_branch));
    return Array.from(set).sort();
  }, [repos]);

  const showHasOpenPrsFilter = filters.hasOpenPrs.includes("true");

  const activeFilterCount =
    filters.visibility.length +
    filters.organizations.length +
    filters.hasOpenPrs.length +
    filters.defaultBranch.length;

  const filteredRepos = useMemo(() => {
    return repos.filter((repo) => {
      if (filters.visibility.length > 0 && !filters.visibility.includes(repo.visibility)) return false;
      if (filters.organizations.length > 0 && !filters.organizations.includes(repo.organization_name)) return false;
      if (showHasOpenPrsFilter && repo.open_prs_count === 0) return false;
      if (filters.defaultBranch.length > 0 && !filters.defaultBranch.includes(repo.default_branch)) return false;
      return true;
    });
  }, [repos, filters, showHasOpenPrsFilter]);

  const columns = useMemo<ColumnDef<OrganizationRepoWithOrg>[]>(() => {
    const cols: ColumnDef<OrganizationRepoWithOrg>[] = [
      {
        id: "name",
        accessorFn: (row) => row.repo_name,
        header: ({ column }) => (
          <button
            className="flex items-center cursor-pointer"
            onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
          >
            {t("tables.header.name")}
            <SortIcon sorted={column.getIsSorted()} />
          </button>
        ),
        cell: ({ row }) => (
          <div className="flex flex-col">
            <button
              className="text-sm font-semibold text-gray-900 dark:text-white text-left hover:text-purple-600 dark:hover:text-purple-400 transition-colors cursor-pointer"
              onClick={() => handleViewRepo(row.original)}
            >
              {row.original.repo_name}
            </button>
            <span className="text-xs text-gray-500 dark:text-gray-400">{row.original.owner}</span>
          </div>
        ),
      },
    ];

    if (!hideOrganization) {
      cols.push({
        id: "organization",
        accessorFn: (row) => row.organization_name,
        header: t("tables.header.organization"),
        cell: ({ row }) =>
          onOrganizationClick ? (
            <button onClick={() => onOrganizationClick(row.original)} className="cursor-pointer">
              <Badge variant="secondary" className="hover:bg-zinc-200 dark:hover:bg-zinc-700 transition-colors">
                {row.original.organization_name}
              </Badge>
            </button>
          ) : (
            <Badge variant="secondary">{row.original.organization_name}</Badge>
          ),
      });
    }

    cols.push(
      {
        id: "open_prs_count",
        accessorFn: (row) => row.open_prs_count,
        header: ({ column }) => (
          <div className="flex justify-center">
            <button
              className="flex items-center cursor-pointer"
              onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
            >
              {t("tables.header.prs")}
              <SortIcon sorted={column.getIsSorted()} />
            </button>
          </div>
        ),
        cell: ({ row }) =>
          row.original.open_prs_count > 0 ? (
            <button
              onClick={() => handleViewPrs(row.original)}
              className="font-semibold tabular-nums text-purple-600 dark:text-purple-400 hover:text-purple-700 dark:hover:text-purple-300 underline-offset-2 hover:underline cursor-pointer w-full text-center block"
            >
              {row.original.open_prs_count}
            </button>
          ) : (
            <span className="block text-center">—</span>
          ),
      },
      {
        id: "default_branch",
        accessorFn: (row) => row.default_branch,
        header: t("tables.header.default"),
        cell: ({ row }) => (
          <div className="flex justify-end items-center gap-2">
            <Badge variant="secondary">{row.original.default_branch}</Badge>
          </div>
        ),
      },
      {
        id: "visibility",
        accessorFn: (row) => row.visibility,
        header: ({ column }) => (
          <div className="flex justify-end">
            <button
              className="flex items-center cursor-pointer"
              onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
            >
              {t("tables.header.visibility")}
              <SortIcon sorted={column.getIsSorted()} />
            </button>
          </div>
        ),
        cell: ({ row }) => (
          <Badge variant={row.original.visibility === "private" ? "warning" : "secondary"}>
            {row.original.visibility}
          </Badge>
        ),
      },
      {
        id: "actions",
        header: "",
        cell: ({ row }) => (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon">
                <MoreVertical className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onSelect={() => void handleNewTask(row.original)}>
                <Plus className="mr-2 h-4 w-4" />
                {t("common.newTask")}
              </DropdownMenuItem>
              <DropdownMenuItem onSelect={() => handleViewRepo(row.original)}>
                <Eye className="mr-2 h-4 w-4" />
                {t("common.viewRepo")}
              </DropdownMenuItem>
              <DropdownMenuItem onSelect={() => handleViewPrs(row.original)}>
                <GitPullRequest className="mr-2 h-4 w-4" />
                {t("tables.header.prs")}
              </DropdownMenuItem>
              {onSyncRepo && (
                <DropdownMenuItem
                  onSelect={() => onSyncRepo(row.original)}
                  disabled={syncingRepoId === String(row.original.id)}
                >
                  <RotateCw className={cn("mr-2 h-4 w-4", syncingRepoId === String(row.original.id) && "animate-spin")} />
                  {t("common.sync")}
                </DropdownMenuItem>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        ),
        enableSorting: false,
      },
    );

    return cols;
  }, [t, hideOrganization, onOrganizationClick, onSyncRepo, syncingRepoId, handleViewRepo, handleViewPrs, handleNewTask]);

  const table = useReactTable({
    data: filteredRepos,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
  });

  return (
    <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
      <div className="flex flex-row items-center justify-between px-6 py-6 pb-6">
        <div className="flex flex-row items-center gap-4">
          <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
            <FolderGit2 size={22} strokeWidth={2} />
          </div>
          <div className="flex flex-col gap-1">
            <span className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">{title}</span>
            <span className="text-[13px] font-medium text-zinc-500/80 leading-none">
              {t("components.repoTable.description")}
            </span>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {onSync && (
            <Tooltip>
              <TooltipTrigger asChild>
                <Button variant="outline" size="icon" onClick={onSync} disabled={isSyncing}>
                  <RefreshCw className={cn("h-4 w-4", isSyncing && "animate-spin")} />
                </Button>
              </TooltipTrigger>
              <TooltipContent>{t("common.syncAll")}</TooltipContent>
            </Tooltip>
          )}
          {onCreate && (
            <Button onClick={onCreate}>
              <Plus size={18} />
              {t("common.newRepository")}
            </Button>
          )}

          <Popover>
            <PopoverTrigger asChild>
              <Button variant="outline" size="icon" className="relative">
                <Filter className="h-4 w-4" />
                {activeFilterCount > 0 && (
                  <span className="absolute -top-1.5 -right-1.5 h-4 w-4 rounded-full bg-purple-500 text-[10px] font-bold text-white flex items-center justify-center">
                    {activeFilterCount}
                  </span>
                )}
              </Button>
            </PopoverTrigger>
            <PopoverContent align="end" className="w-64 p-0">
              <div className="flex items-center justify-between px-3 py-2">
                <span className="text-sm font-semibold">{t("repos.table.filter")}</span>
                {activeFilterCount > 0 && (
                  <button
                    type="button"
                    onClick={() => clearFilters(filterNamespace)}
                    className="text-xs text-zinc-400 hover:text-zinc-200"
                  >
                    {t("repos.table.filter.clear")}
                  </button>
                )}
              </div>
              <div className="border-t border-border" />

              {/* Visibility */}
              <div className="px-3 py-2 space-y-2">
                <p className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
                  {t("repos.table.filter.visibility")}
                </p>
                {(["public", "private"] as const).map((v) => (
                  <div key={v} className="flex items-center justify-between">
                    <span className="text-sm capitalize">{t(`repos.table.filter.${v}`)}</span>
                    <Switch
                      checked={filters.visibility.includes(v)}
                      onCheckedChange={() =>
                        setFilter(filterNamespace, "visibility", toggleItem(filters.visibility, v))
                      }
                    />
                  </div>
                ))}
              </div>

              {/* Has open PRs */}
              <div className="border-t border-border" />
              <div className="px-3 py-2 space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-sm">{t("repos.table.filter.hasOpenPrs")}</span>
                  <Switch
                    checked={showHasOpenPrsFilter}
                    onCheckedChange={(checked) =>
                      setFilter(filterNamespace, "hasOpenPrs", checked ? ["true"] : [])
                    }
                  />
                </div>
              </div>

              {/* Organization (only when not hidden and there are multiple orgs) */}
              {!hideOrganization && allOrganizations.length > 1 && (
                <>
                  <div className="border-t border-border" />
                  <div className="px-3 py-2 space-y-1.5">
                    <p className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
                      {t("repos.table.filter.organization")}
                    </p>
                    <Combobox items={allOrganizations} multiple value={filters.organizations} onValueChange={(v) => setFilter(filterNamespace, "organizations", v as string[])}>
                      <ComboboxChips className="min-h-8 text-xs">
                        <ComboboxValue>
                          {filters.organizations.map((item) => (
                            <ComboboxChip key={item} className="text-[11px]">{item}</ComboboxChip>
                          ))}
                        </ComboboxValue>
                        <ComboboxChipsInput placeholder={t("repos.table.filter.orgSearch")} className="text-xs" />
                      </ComboboxChips>
                      <ComboboxContent>
                        <ComboboxEmpty>No results.</ComboboxEmpty>
                        <ComboboxList>
                          {(item: string) => <ComboboxItem key={item} value={item}>{item}</ComboboxItem>}
                        </ComboboxList>
                      </ComboboxContent>
                    </Combobox>
                  </div>
                </>
              )}

              {/* Default branch */}
              {allBranches.length > 1 && (
                <>
                  <div className="border-t border-border" />
                  <div className="px-3 py-2 space-y-1.5">
                    <p className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
                      {t("repos.table.filter.defaultBranch")}
                    </p>
                    <Combobox items={allBranches} multiple value={filters.defaultBranch} onValueChange={(v) => setFilter(filterNamespace, "defaultBranch", v as string[])}>
                      <ComboboxChips className="min-h-8 text-xs">
                        <ComboboxValue>
                          {filters.defaultBranch.map((item) => (
                            <ComboboxChip key={item} className="text-[11px]">{item}</ComboboxChip>
                          ))}
                        </ComboboxValue>
                        <ComboboxChipsInput placeholder={t("repos.table.filter.branchSearch")} className="text-xs" />
                      </ComboboxChips>
                      <ComboboxContent>
                        <ComboboxEmpty>No results.</ComboboxEmpty>
                        <ComboboxList>
                          {(item: string) => <ComboboxItem key={item} value={item}>{item}</ComboboxItem>}
                        </ComboboxList>
                      </ComboboxContent>
                    </Combobox>
                  </div>
                </>
              )}
            </PopoverContent>
          </Popover>
        </div>
      </div>
      <CardContent className="p-0 border-t border-zinc-100 dark:border-zinc-800/50 px-0">
        <div className="overflow-hidden rounded-xl">
          <Table>
            <TableHeader>
              {table.getHeaderGroups().map((headerGroup) => (
                <TableRow key={headerGroup.id}>
                  {headerGroup.headers.map((header) => (
                    <TableHead
                      key={header.id}
                      className={cn(
                        header.id === "open_prs_count" && "text-center",
                        ["default_branch", "visibility", "actions"].includes(header.id) && "text-right",
                      )}
                    >
                      {header.isPlaceholder
                        ? null
                        : flexRender(header.column.columnDef.header, header.getContext())}
                    </TableHead>
                  ))}
                </TableRow>
              ))}
            </TableHeader>
            <TableBody>
              {table.getRowModel().rows.map((row) => (
                <TableRow key={row.id}>
                  {row.getVisibleCells().map((cell) => (
                    <TableCell
                      key={cell.id}
                      className={cn(
                        cell.column.id === "open_prs_count" && "text-center",
                        ["default_branch", "visibility", "actions"].includes(cell.column.id) && "text-right",
                      )}
                    >
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      </CardContent>
    </Card>
  );
}
