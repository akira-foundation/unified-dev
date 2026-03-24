import {
  type ColumnDef,
  type ColumnFiltersState,
  type RowSelectionState,
  getCoreRowModel,
  getFilteredRowModel,
  useReactTable,
  flexRender,
} from "@tanstack/react-table";
import { useMemo, useState } from "react";
import type { ProviderRepo } from "../../types/organization";
import { Badge } from "../ui/badge";
import { Checkbox } from "../ui/checkbox";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../ui/table";
import { Card, CardContent, CardHeader } from "@/components/ui/card.tsx";
import { SearchInput } from "./search-input";
import { VisibilityFilter } from "./visibility-filter";
import { useI18n } from "../../i18n/i18n";

interface RepoSelectionTableProps {
  repos: ProviderRepo[];
  selectedKeys: Set<string>;
  onSelectionChange: (keys: Set<string>) => void;
  /** Rendered in the card header alongside the repo count */
  action?: React.ReactNode;
  className?: string;
}

const repoKey = (repo: ProviderRepo) => `${repo.owner}/${repo.name}`;

type VisibilityFilterValue = "all" | "public" | "private";

export function RepoSelectionTable({
  repos,
  selectedKeys,
  onSelectionChange,
  action,
  className,
}: RepoSelectionTableProps) {
  const { t } = useI18n();
  const [search, setSearch] = useState("");
  const [visibility, setVisibility] = useState<VisibilityFilterValue>("all");
  const [columnFilters, setColumnFilters] = useState<ColumnFiltersState>([]);

  const rowSelection: RowSelectionState = useMemo(() => {
    const state: RowSelectionState = {};
    for (const key of selectedKeys) {
      state[key] = true;
    }
    return state;
  }, [selectedKeys]);

  const columns = useMemo<ColumnDef<ProviderRepo>[]>(
    () => [
      {
        id: "select",
        header: ({ table }) => (
          <Checkbox
            checked={
              table.getIsAllPageRowsSelected()
                ? true
                : table.getIsSomePageRowsSelected()
                  ? "indeterminate"
                  : false
            }
            onCheckedChange={(checked) =>
              checked
                ? table.toggleAllPageRowsSelected(true)
                : table.toggleAllPageRowsSelected(false)
            }
          />
        ),
        cell: ({ row }) => (
          <Checkbox
            checked={row.getIsSelected()}
            onCheckedChange={row.getToggleSelectedHandler()}
            onClick={(e) => e.stopPropagation()}
          />
        ),
        enableSorting: false,
        enableColumnFilter: false,
      },
      {
        id: "name",
        accessorFn: (row) => row.name,
        header: t("tables.header.name"),
        filterFn: (row, _colId, filterValue: string) => {
          const q = filterValue.toLowerCase();
          return (
            row.original.name.toLowerCase().includes(q) ||
            row.original.owner.toLowerCase().includes(q)
          );
        },
        cell: ({ row }) => (
          <div className="flex flex-col">
            <span className="text-sm font-semibold text-gray-900 dark:text-white">
              {row.original.name}
            </span>
            <span className="text-xs text-gray-500 dark:text-gray-400">{row.original.owner}</span>
          </div>
        ),
      },
      {
        id: "visibility",
        accessorFn: (row) => row.visibility,
        header: t("tables.header.visibility"),
        filterFn: (row, _colId, filterValue: VisibilityFilterValue) => {
          if (filterValue === "all") return true;
          return row.original.visibility === filterValue;
        },
        cell: ({ row }) => (
          <Badge variant={row.original.visibility === "private" ? "warning" : "secondary"}>
            {row.original.visibility}
          </Badge>
        ),
      },
    ],
    [t],
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

  const handleSearchChange = (value: string) => {
    setSearch(value);
    table.getColumn("name")?.setFilterValue(value || undefined);
  };

  const handleVisibilityChange = (value: VisibilityFilterValue) => {
    setVisibility(value);
    table.getColumn("visibility")?.setFilterValue(value === "all" ? undefined : value);
  };

  return (
    <div className={`overflow-hidden rounded-xl ${className ?? ""}`}>
      <Card className="h-full flex flex-col">
        <CardHeader>
          <div className="flex flex-wrap items-center gap-3">
            <div className="flex-1 min-w-0">
              <SearchInput value={search} onChange={handleSearchChange} />
            </div>
            <VisibilityFilter value={visibility} onChange={handleVisibilityChange} />
            {action}
          </div>
        </CardHeader>
        <CardContent className="flex-1 overflow-y-auto">
          <Table className="border-separate border-spacing-y-2">
            <TableHeader className="[&_tr]:border-b-0">
              {table.getHeaderGroups().map((headerGroup) => (
                <TableRow key={headerGroup.id}>
                  {headerGroup.headers.map((header, i) => (
                    <TableHead
                      key={header.id}
                      className={`bg-muted/10 ${i === 0 ? "w-12 rounded-l-lg" : ""} ${i === headerGroup.headers.length - 1 ? "rounded-r-lg text-right" : ""}`}
                    >
                      {header.isPlaceholder
                        ? null
                        : flexRender(header.column.columnDef.header, header.getContext())}
                    </TableHead>
                  ))}
                </TableRow>
              ))}
            </TableHeader>
            <TableBody className="[&_tr]:border-b-0">
              {table.getRowModel().rows.map((row) => (
                <TableRow
                  key={row.id}
                  className="group cursor-pointer"
                  onClick={() => row.toggleSelected()}
                >
                  {row.getVisibleCells().map((cell, i) => (
                    <TableCell
                      key={cell.id}
                      className={`bg-muted/10 transition-colors group-hover:bg-muted/20 ${i === 0 ? "w-12 rounded-l-lg" : ""} ${i === row.getVisibleCells().length - 1 ? "rounded-r-lg text-right" : ""}`}
                    >
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
