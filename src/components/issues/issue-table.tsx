import type { IssueSummary } from "../../types/issue";
import { Table, TableBody, TableHead, TableHeader, TableRow } from "../ui/table";
import { IssueRow } from "./issue-row";

interface IssueTableProps {
  issues: IssueSummary[];
}

export function IssueTable({ issues }: IssueTableProps) {
  return (
    <div className="overflow-hidden rounded-xl border border-gray-100 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Issue</TableHead>
            <TableHead>Repository</TableHead>
            <TableHead>Status</TableHead>
            <TableHead>Updated</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {issues.map((issue) => (
            <IssueRow key={issue.id} issue={issue} />
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
