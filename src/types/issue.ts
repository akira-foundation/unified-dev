export interface IssueDto {
  id: string;
  externalId: string;
  provider: string;
  orgId: string;
  repoName: string;
  number: number;
  title: string;
  body: string | null;
  status: string;
  stateReason: string | null;
  labels: string[];
  labelColors: string[];
  assignees: string[];
  author: string | null;
  url: string;
  linkedPrNumbers: number[];
  createdAt: string;
  updatedAt: string;
  syncedAt: string;
  syncWithProvider: boolean;
  /** Optional explicit column (used by tracker providers like Linear). */
  column?: IssueColumnId;
  /** Optional human identifier (e.g. Linear ENG-123). */
  identifier?: string;
  /** App-level project container resolved from the issue source. */
  projectId?: string;
  projectName?: string;
  /** Repo container (project_repo) resolved from the issue source. */
  repoId?: string;
  containerName?: string;
}

/** Kanban column IDs for the issue board */
export type IssueColumnId = "backlog" | "todo" | "in_progress" | "done";

export interface IssueColumn {
  id: IssueColumnId;
  label: string;
}

export const ISSUE_COLUMNS: IssueColumn[] = [
  { id: "backlog",     label: "Backlog"     },
  { id: "todo",        label: "Todo"        },
  { id: "in_progress", label: "In Progress" },
  { id: "done",        label: "Done"        },
];

/**
 * Map a raw GitHub status + state_reason to a kanban column.
 * - open + no assignee     → backlog
 * - open + has assignee(s) → in_progress
 * - closed (any reason)    → done
 */
export function issueToColumn(issue: IssueDto): IssueColumnId {
  if (issue.column) return issue.column;
  if (issue.status === "open") {
    return issue.assignees.length > 0 ? "in_progress" : "backlog";
  }
  return "done";
}

export function orderIssuesByColumn(issues: IssueDto[]): IssueDto[] {
  const order: IssueColumnId[] = ["in_progress", "todo", "backlog", "done"];
  const map: Record<IssueColumnId, IssueDto[]> = { backlog: [], todo: [], in_progress: [], done: [] };
  issues.forEach((issue) => map[issueToColumn(issue)].push(issue));
  order.forEach((col) => map[col].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)));
  return order.flatMap((col) => map[col]);
}

/** @deprecated use IssueDto */
export interface IssueSummary {
  id: string;
  title: string;
  repository: string;
  status: string;
  updatedAt: string;
}
