export type AgentStatus = "Pending" | "Running" | "Completed" | "Error";

export type ImageMediaType = "image/png" | "image/jpeg" | "image/gif" | "image/webp";

export interface TextPart {
  type: "text";
  text: string;
}

export interface ImagePart {
  type: "image";
  data: string;
  mediaType: ImageMediaType;
}

export type ContentPart = TextPart | ImagePart;

export type MessageContent = string | ContentPart[];

export const IMAGE_SIZE_LIMIT = 5 * 1024 * 1024;

export function serializeContent(content: MessageContent): string {
  if (typeof content === "string") return content;
  return JSON.stringify(content);
}

export function parseContent(raw: string): MessageContent {
  if (!raw.startsWith("[")) return raw;
  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) return parsed as ContentPart[];
  } catch {
    // fall through
  }
  return raw;
}

export function contentToText(content: MessageContent): string {
  if (typeof content === "string") return content;
  return content
    .filter((p): p is TextPart => p.type === "text")
    .map((p) => p.text)
    .join(" ");
}

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
  defaultBranch: string;
  displayName: string | null;
  defaultModelId: string | null;
  reviewModelId: string | null;
  remoteUrl: string | null;
  issues: AgentIssue[];
}
