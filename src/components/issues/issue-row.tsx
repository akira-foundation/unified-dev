import type { IssueSummary } from "../../types/issue";
import { TableCell, TableRow } from "../ui/table";

interface IssueRowProps {
  issue: IssueSummary;
}

export function IssueRow({ issue }: IssueRowProps) {
  return (
    <TableRow>
      <TableCell className="font-medium text-white">{issue.title}</TableCell>
      <TableCell>{issue.repository}</TableCell>
      <TableCell>{issue.status}</TableCell>
      <TableCell>{issue.updatedAt}</TableCell>
    </TableRow>
  );
}
