import type { ProviderRepo } from "../../types/organization";
import { Badge } from "../ui/badge";
import { Checkbox } from "../ui/checkbox";
import { TableCell, TableRow } from "../ui/table";

interface RepoSelectionRowProps {
  repo: ProviderRepo;
  isSelected: boolean;
  onToggle: (repo: ProviderRepo) => void;
}

export function RepoSelectionRow({ repo, isSelected, onToggle }: RepoSelectionRowProps) {
  return (
    <TableRow>
      <TableCell className="w-12">
        <Checkbox checked={isSelected} onCheckedChange={() => onToggle(repo)} />
      </TableCell>
      <TableCell>
        <div className="flex flex-col">
          <span className="text-sm font-semibold text-gray-900 dark:text-white">{repo.name}</span>
          <span className="text-xs text-gray-500 dark:text-gray-400">{repo.owner}</span>
        </div>
      </TableCell>
      <TableCell className="text-right">
        <Badge variant={repo.visibility === "private" ? "warning" : "secondary"}>
          {repo.visibility}
        </Badge>
      </TableCell>
    </TableRow>
  );
}
