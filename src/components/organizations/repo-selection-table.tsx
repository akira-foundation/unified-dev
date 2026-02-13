import type { ProviderRepo } from "../../types/organization";
import { Checkbox } from "../ui/checkbox";
import { Table, TableBody, TableHead, TableHeader, TableRow } from "../ui/table";
import { RepoSelectionRow } from "./repo-selection-row";

interface RepoSelectionTableProps {
  repos: ProviderRepo[];
  selectedKeys: Set<string>;
  selectAllState: boolean | "indeterminate";
  onSelectAll: () => void;
  onClearAll: () => void;
  onToggleRepo: (repo: ProviderRepo) => void;
}

const repoKey = (repo: ProviderRepo) => `${repo.owner}/${repo.name}`;

export function RepoSelectionTable({
  repos,
  selectedKeys,
  selectAllState,
  onSelectAll,
  onClearAll,
  onToggleRepo,
}: RepoSelectionTableProps) {
  return (
    <div className="overflow-hidden rounded-xl border border-gray-100 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead className="w-12">
              <Checkbox
                checked={selectAllState}
                onCheckedChange={(checked) => (checked ? onSelectAll() : onClearAll())}
              />
            </TableHead>
            <TableHead>Repository</TableHead>
            <TableHead className="text-right">Visibility</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {repos.map((repo) => (
            <RepoSelectionRow
              key={repoKey(repo)}
              repo={repo}
              isSelected={selectedKeys.has(repoKey(repo))}
              onToggle={onToggleRepo}
            />
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
