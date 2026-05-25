import { invoke } from "@tauri-apps/api/core";

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
};
