export type AgentStatus = "Pending" | "Running" | "Completed" | "Error";

export interface AgentIssue {
  id: string;
  title: string;
  repoId: string;
  workspacePath: string;
  repoName: string;
  branchName: string;
  agentName: string;
  status: AgentStatus;
  updatedAt: string;
  prUrl?: string;
}

export interface AgentTimelineStep {
  id: string;
  message: string;
  timestamp: string;
  status: "completed" | "running" | "warning" | "error" | "info";
  details?: string;
}

export interface FileChange {
  filename: string;
  status: "modified" | "added" | "deleted";
  diff?: string;
}

export interface RepositoryGroup {
  name: string;
  repositories: AgentRepository[];
}

export interface AgentRepository {
  id: string;
  name: string;
  issues: AgentIssue[];
}
