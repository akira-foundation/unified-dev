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
    <TableRow className="group">
      <TableCell className="w-12 rounded-l-lg bg-muted/10 transition-colors group-hover:bg-muted/20">
        <Checkbox checked={isSelected} onCheckedChange={() => onToggle(repo)} />
      </TableCell>
      <TableCell className="bg-muted/10 transition-colors group-hover:bg-muted/20">
        <div className="flex flex-col">
          <span className="text-sm font-semibold text-gray-900 dark:text-white">{repo.name}</span>
          <span className="text-xs text-gray-500 dark:text-gray-400">{repo.owner}</span>
        </div>
      </TableCell>
      <TableCell className="rounded-r-lg bg-muted/10 text-right transition-colors group-hover:bg-muted/20">
        <Badge variant={repo.visibility === "private" ? "warning" : "secondary"}>
          {repo.visibility}
        </Badge>
      </TableCell>
    </TableRow>
  );
}
