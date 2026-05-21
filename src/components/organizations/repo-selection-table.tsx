import {
  type ColumnDef,
  type ColumnFiltersState,
  type RowSelectionState,
  getCoreRowModel,
  getFilteredRowModel,
  useReactTable,
} from "@tanstack/react-table";
import { useEffect, useMemo, useState } from "react";
import type { ProviderRepo } from "../../types/organization";
import { Badge } from "../ui/badge";
import { Checkbox } from "../ui/checkbox";
import { EmptyState } from "../ui/empty-state";
import { useI18n } from "../../i18n/i18n";

export type VisibilityFilterValue = "all" | "public" | "private";

interface RepoSelectionTableProps {
  repos: ProviderRepo[];
  selectedKeys: Set<string>;
  onSelectionChange: (keys: Set<string>) => void;
  search?: string;
  visibility?: VisibilityFilterValue;
  action?: React.ReactNode;
  className?: string;
}

const repoKey = (repo: ProviderRepo) => `${repo.owner}/${repo.name}`;

export function RepoSelectionTable({
  repos,
  selectedKeys,
  onSelectionChange,
  search = "",
  visibility = "all",
  action,
  className,
}: RepoSelectionTableProps) {
  const { t } = useI18n();
  const [columnFilters, setColumnFilters] = useState<ColumnFiltersState>([]);

  const rowSelection: RowSelectionState = useMemo(() => {
    const state: RowSelectionState = {};
    for (const key of selectedKeys) state[key] = true;
    return state;
  }, [selectedKeys]);

  const columns = useMemo<ColumnDef<ProviderRepo>[]>(
    () => [
      {
        id: "name",
        accessorFn: (row) => row.name,
        filterFn: (row, _colId, filterValue: string) => {
          const q = filterValue.toLowerCase();
          return row.original.name.toLowerCase().includes(q) || row.original.owner.toLowerCase().includes(q);
        },
      },
      {
        id: "visibility",
        accessorFn: (row) => row.visibility,
        filterFn: (row, _colId, filterValue: VisibilityFilterValue) =>
          filterValue === "all" ? true : row.original.visibility === filterValue,
      },
    ],
    [],
  );

  const table = useReactTable({
    data: repos,
    columns,
    state: { rowSelection, columnFilters },
    getRowId: repoKey,
    getCoreRowModel: getCoreRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    onRowSelectionChange: (updater) => {
      const next = typeof updater === "function" ? updater(rowSelection) : updater;
      onSelectionChange(new Set(Object.keys(next).filter((k) => next[k])));
    },
    onColumnFiltersChange: setColumnFilters,
    enableRowSelection: true,
  });

  useEffect(() => {
    table.getColumn("name")?.setFilterValue(search || undefined);
  }, [search, table]);

  useEffect(() => {
    table.getColumn("visibility")?.setFilterValue(visibility === "all" ? undefined : visibility);
  }, [visibility, table]);

  const rows = table.getRowModel().rows;

  return (
    <div className={`flex flex-col ${className ?? ""}`}>
      {action && <div className="flex items-center justify-end px-1 pb-3">{action}</div>}

      <div className="min-h-0 flex-1 overflow-y-auto custom-scrollbar">
        {rows.length === 0 ? (
          <EmptyState title={t("pages.importRepos.failedRepos.title")} />
        ) : (
          <div className="flex flex-col">
            {rows.map((row) => (
              <div
                key={row.id}
                onClick={() => row.toggleSelected()}
                className="group flex h-11 cursor-pointer items-center gap-3 rounded-md pl-3 pr-2 transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.03]"
              >
                <Checkbox
                  checked={row.getIsSelected()}
                  onCheckedChange={row.getToggleSelectedHandler()}
                  onClick={(e) => e.stopPropagation()}
                />
                <div className="flex min-w-0 flex-1 flex-col">
                  <span className="truncate text-[13px] font-medium text-zinc-800 dark:text-zinc-100">{row.original.name}</span>
                  <span className="truncate text-[11px] text-zinc-500">{row.original.owner}</span>
                </div>
                <Badge variant={row.original.visibility === "private" ? "warning" : "secondary"} className="shrink-0 text-[10px]">
                  {row.original.visibility}
                </Badge>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
