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
import { ArrowUpDown, ChevronDown, ChevronUp, Eye, Filter, FolderGit2, GitPullRequest, MoreVertical, Plus, RefreshCw, RotateCw, Search } from "lucide-react";
import { useI18n } from "../../i18n/i18n";
import { cn } from "@/lib/utils";
import { useRepoActions } from "../../hooks/useRepoActions";
import { useFiltersStore } from "../../stores/filters-store";

import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent } from "../ui/card";
import { Input } from "../ui/input";
import {
  FilterPopover,
  FilterPopoverContent,
  FilterPopoverTrigger,
} from "../filters/filter-popover";
import {
  FilterBooleanSection,
  FilterPopoverHeader,
  FilterSectionDivider,
  FilterToggleSection,
} from "../filters/filter-popover-section";
import { MultiSelectFilterSection } from "../filters/multi-select-filter-section";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from "../ui/dropdown-menu";
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
  onVisibilitySettings?: (repo: OrganizationRepoWithOrg) => void;
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
  onVisibilitySettings,
  isSyncing,
  syncingRepoId,
  hideOrganization,
}: RepoMetricsTableProps) {
  const { t } = useI18n();
  const { handleViewRepo, handleViewPrs, handleViewIssues, handleNewTask } = useRepoActions();
  const [sorting, setSorting] = useState<SortingState>([]);
  const [search, setSearch] = useState("");

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
    const lower = search.toLowerCase();
    return repos.filter((repo) => {
      if (lower && !repo.repo_name.toLowerCase().includes(lower) && !repo.organization_name.toLowerCase().includes(lower)) return false;
      if (filters.visibility.length > 0 && !filters.visibility.includes(repo.visibility)) return false;
      if (filters.organizations.length > 0 && !filters.organizations.includes(repo.organization_name)) return false;
      if (showHasOpenPrsFilter && repo.open_prs_count === 0) return false;
      if (filters.defaultBranch.length > 0 && !filters.defaultBranch.includes(repo.default_branch)) return false;
      return true;
    });
  }, [repos, filters, showHasOpenPrsFilter, search]);

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
          <div className="flex flex-col gap-0.5">
            <div className="flex items-center gap-1.5">
              <button
                className="text-sm font-semibold text-gray-900 dark:text-white text-left hover:text-purple-600 dark:hover:text-purple-400 transition-colors cursor-pointer"
                onClick={() => handleViewRepo(row.original)}
              >
                {row.original.repo_name}
              </button>
              {row.original.is_fork && (
                <Badge variant="info" className="text-[10px] px-1.5 py-0 h-4 font-medium">
                  Fork
                </Badge>
              )}
            </div>
            <span className="text-xs text-gray-500 dark:text-gray-400">
              {row.original.owner}
              {row.original.is_fork && row.original.fork_owner && row.original.fork_repo && (
                <span className="text-zinc-400 dark:text-zinc-600"> · upstream: {row.original.fork_owner}/{row.original.fork_repo}</span>
              )}
            </span>
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
        id: "open_issues_count",
        accessorFn: (row) => row.open_issues_count ?? 0,
        header: ({ column }) => (
          <div className="flex justify-center">
            <button
              className="flex items-center cursor-pointer"
              onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
            >
              {t("issues.page.title")}
              <SortIcon sorted={column.getIsSorted()} />
            </button>
          </div>
        ),
        cell: ({ row }) =>
          (row.original.open_issues_count ?? 0) > 0 ? (
            <button
              onClick={() => handleViewIssues(row.original)}
              className="font-semibold tabular-nums text-purple-600 dark:text-purple-400 hover:text-purple-700 dark:hover:text-purple-300 underline-offset-2 hover:underline cursor-pointer w-full text-center block"
            >
              {row.original.open_issues_count}
            </button>
          ) : (
            <span className="block text-center">—</span>
          ),
      },
      {
        id: "open_prs_count",
        accessorFn: (row) => row.open_prs_count,
        header: ({ column }) => (
          <div className="flex justify-center">
            <button
              className="flex items-center cursor-pointer"
              onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
            >
               {t("pages.repository.stats.openPrs")}
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
            {row.original.default_branch ? (
              <Badge variant="secondary">{row.original.default_branch}</Badge>
            ) : (
              <span className="text-muted-foreground">—</span>
            )}
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
              <DropdownMenuLabel className="text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">{t("common.open")}</DropdownMenuLabel>
              <DropdownMenuItem onSelect={() => handleViewRepo(row.original)}>
                <Eye className="mr-2 h-4 w-4" />
                {t("common.viewRepo")}
              </DropdownMenuItem>
              <DropdownMenuItem onSelect={() => handleViewPrs(row.original)}>
                <GitPullRequest className="mr-2 h-4 w-4" />
                {t("pages.repository.stats.openPrs")}
              </DropdownMenuItem>
              <DropdownMenuItem onSelect={() => void handleNewTask(row.original)}>
                <Plus className="mr-2 h-4 w-4" />
                {t("common.newTask")}
              </DropdownMenuItem>
              {(onVisibilitySettings || onSyncRepo) && (
                <>
                  <DropdownMenuSeparator />
                  <DropdownMenuLabel className="text-[9px] font-medium tracking-[0.08em] text-zinc-500/70 dark:text-zinc-500">{t("common.manage")}</DropdownMenuLabel>
                </>
              )}
              {onVisibilitySettings && (
                <DropdownMenuItem onSelect={() => onVisibilitySettings(row.original)}>
                  <RefreshCw className="mr-2 h-4 w-4" />
                  {t("common.configureSync")}
                </DropdownMenuItem>
              )}
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
  }, [t, hideOrganization, onOrganizationClick, onVisibilitySettings, onSyncRepo, syncingRepoId, handleViewRepo, handleViewPrs, handleViewIssues, handleNewTask]);

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
          <div className="relative">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-zinc-500 pointer-events-none" />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder={t("filters.search.placeholder")}
              className="pl-8 h-9 w-48 text-sm focus-visible:ring-purple-500/50"
            />
          </div>
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
                title={t("repos.table.filter")}
                clearLabel={t("repos.table.filter.clear")}
                canClear={activeFilterCount > 0}
                onClear={() => clearFilters(filterNamespace)}
              />
              <FilterSectionDivider />

              {/* Visibility */}
              <FilterToggleSection
                label={t("repos.table.filter.visibility")}
                options={(["public", "private"] as const).map((v) => ({
                  key: v,
                  label: t(`repos.table.filter.${v}`),
                  checked: filters.visibility.includes(v),
                  onCheckedChange: () =>
                    setFilter(filterNamespace, "visibility", toggleItem(filters.visibility, v)),
                }))}
              />

              {/* Has open PRs */}
              <FilterSectionDivider />
              <FilterBooleanSection
                label={t("repos.table.filter.hasOpenPrs")}
                checked={showHasOpenPrsFilter}
                onCheckedChange={(checked) =>
                  setFilter(filterNamespace, "hasOpenPrs", checked ? ["true"] : [])
                }
              />

              {/* Organization (only when not hidden and there are multiple orgs) */}
              {!hideOrganization && allOrganizations.length > 1 && (
                <>
                  <FilterSectionDivider />
                  <MultiSelectFilterSection
                    label={t("repos.table.filter.organization")}
                    placeholder={t("repos.table.filter.orgSearch")}
                    items={allOrganizations}
                    value={filters.organizations}
                    onValueChange={(value) => setFilter(filterNamespace, "organizations", value)}
                  />
                </>
              )}

              {/* Default branch */}
              {allBranches.length > 1 && (
                <>
                  <FilterSectionDivider />
                  <MultiSelectFilterSection
                    label={t("repos.table.filter.defaultBranch")}
                    placeholder={t("repos.table.filter.branchSearch")}
                    items={allBranches}
                    value={filters.defaultBranch}
                    onValueChange={(value) => setFilter(filterNamespace, "defaultBranch", value)}
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
