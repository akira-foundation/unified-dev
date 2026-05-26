import { invoke } from "@tauri-apps/api/core";

import type { IssueColumnId, IssueDto } from "@/types/issue";
import { sourceKey, type Project } from "@/services/projectService";

export interface TrackerNamed {
  id: string;
  name: string;
}

export interface TrackerIssue {
  id: string;
  identifier?: string | null;
  title: string;
  description?: string | null;
  url?: string | null;
  status: string;
  category?: string | null;
  project?: string | null;
  milestone?: string | null;
  team?: string | null;
  assignee?: string | null;
  author?: string | null;
  labels: string[];
  priority?: number | null;
  createdAt?: string | null;
  updatedAt: string;
  projectName?: string | null;
  milestoneName?: string | null;
  teamName?: string | null;
  assigneeName?: string | null;
  authorName?: string | null;
  labelNames?: string[];
}

export interface TrackerIssueFilter {
  team?: string | null;
  project?: string | null;
  assignee?: string | null;
  category?: string | null;
}

export interface TrackerIssueDraft {
  team: string;
  title: string;
  status?: string | null;
  category?: string | null;
  project?: string | null;
  milestone?: string | null;
  assignee?: string | null;
  priority?: number | null;
}

export interface TrackerIssuePatch {
  title?: string | null;
  category?: string | null;
  project?: string | null;
  milestone?: string | null;
  assignee?: string | null;
  priority?: number | null;
}

export const trackerService = {
  async connect(provider: string, token: string): Promise<TrackerNamed> {
    return invoke<TrackerNamed>("tracker_connect", { provider, token });
  },
  async status(provider: string): Promise<boolean> {
    return invoke<boolean>("tracker_status", { provider });
  },
  async disconnect(provider: string): Promise<void> {
    await invoke<void>("tracker_disconnect", { provider });
  },
  async providers(): Promise<string[]> {
    return invoke<string[]>("tracker_providers");
  },
  async sync(provider: string, filter?: TrackerIssueFilter): Promise<number> {
    return invoke<number>("tracker_sync", { provider, filter: filter ?? null });
  },
  async listIssues(provider: string): Promise<TrackerIssue[]> {
    return invoke<TrackerIssue[]>("tracker_list_issues", { provider });
  },
  async getIssue(id: string): Promise<TrackerIssue> {
    return invoke<TrackerIssue>("tracker_get_issue", { id });
  },
  async createIssue(provider: string, draft: TrackerIssueDraft): Promise<TrackerIssue> {
    return invoke<TrackerIssue>("tracker_create_issue", { provider, draft });
  },
  async updateIssue(
    provider: string,
    id: string,
    patch: TrackerIssuePatch,
  ): Promise<TrackerIssue> {
    return invoke<TrackerIssue>("tracker_update_issue", { provider, id, patch });
  },
  async closeIssue(provider: string, id: string): Promise<TrackerIssue> {
    return invoke<TrackerIssue>("tracker_close_issue", { provider, id });
  },
  async deleteIssue(provider: string, id: string): Promise<void> {
    await invoke<void>("tracker_delete_issue", { provider, id });
  },
  async listProjects(provider: string): Promise<TrackerNamed[]> {
    return invoke<TrackerNamed[]>("tracker_list_projects", { provider });
  },
  async listTeams(provider: string): Promise<TrackerNamed[]> {
    return invoke<TrackerNamed[]>("tracker_list_teams", { provider });
  },
};

function categoryToColumn(category?: string | null): IssueColumnId {
  switch (category) {
    case "Started":
      return "in_progress";
    case "Unstarted":
      return "todo";
    case "Completed":
    case "Canceled":
      return "done";
    default:
      return "backlog";
  }
}

export function trackerIssueToDto(
  issue: TrackerIssue,
  provider = "linear",
  projectMap?: Map<string, Project>,
): IssueDto {
  const column = categoryToColumn(issue.category);
  const number = issue.identifier ? parseInt(issue.identifier.replace(/\D/g, ""), 10) || 0 : 0;
  const labels = issue.labelNames ?? [];
  const assignee = issue.assigneeName ?? undefined;
  const project =
    (issue.project && projectMap?.get(sourceKey(provider, "project", issue.project))) ||
    (issue.team && projectMap?.get(sourceKey(provider, "team", issue.team))) ||
    undefined;
  return {
    id: issue.id,
    externalId: issue.id,
    provider,
    orgId: provider,
    repoName: project?.name ?? issue.teamName ?? "Linear",
    number,
    title: issue.title,
    body: issue.description ?? null,
    status: column === "done" ? "closed" : "open",
    stateReason: null,
    labels,
    labelColors: [],
    assignees: assignee ? [assignee] : [],
    author: issue.authorName ?? null,
    url: issue.url ?? "",
    linkedPrNumbers: [],
    createdAt: issue.createdAt ?? issue.updatedAt,
    updatedAt: issue.updatedAt,
    syncedAt: issue.updatedAt,
    syncWithProvider: false,
    column,
    identifier: issue.identifier ?? undefined,
    projectId: project?.id,
    projectName: project?.name ?? issue.projectName ?? undefined,
  };
}
