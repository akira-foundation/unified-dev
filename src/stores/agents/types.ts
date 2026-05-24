import type { StateCreator } from "zustand";
import type { AgentTimelineStep, FileChange, RepositoryGroup, MessageContent } from "@/types/agents";
import type { AiProviderGroup } from "@/types/ai-providers";

export interface SendMessageOptions {
  planMode?: boolean;
  thinkingBudget?: "x-high" | "high" | "medium" | "low" | "not-available";
  fastMode?: boolean;
}

export interface InstalledSkill {
  id: string;
  name: string;
  description: string;
  enabled: boolean;
  icon_path: string | null;
  installed_at: string;
  source_path: string;
  scope: "global" | "project";
}

export interface PrCheck {
  name: string;
  state: string;
  bucket: "pass" | "fail" | "pending" | "skipping" | "cancel" | string;
  link?: string | null;
  workflow?: string | null;
  startedAt?: string | null;
  completedAt?: string | null;
}

export interface PrCiStatus {
  checks: PrCheck[];
  total: number;
  passing: number;
  failing: number;
  pending: number;
}

export interface ChatMessage {
  id: string;
  thread_id: string;
  role: "user" | "assistant" | "system" | "tool";
  model: string | null;
  content: MessageContent;
  metadata: string | null;
  created_at: string;
}

export interface ToolCallEvent {
  id: string;
  label: string;
  status: "running" | "done" | "error";
  output?: string;
}

export type PrInfo = { url: string; isDraft: boolean; state?: string; mergedAt?: string | null } | null;

export type AgentTab = "workspace" | "skills" | "automations" | "create-automation" | "manage-skill" | "mcp" | "skill-source";

export interface AgentsState {
  repositoryGroups: RepositoryGroup[];
  selectedIssueId: string | null;
  timelineSteps: AgentTimelineStep[];
  fileChanges: FileChange[];
  selectedFilePath: string | null;
  activeTab: AgentTab;
  previousTab: AgentTab | null;
  selectedSkill: any | null;
  selectedSkillSource: { id: string; name: string; description: string } | null;
  selectedAutomation: any | null;
  aiProviders: AiProviderGroup[];
  selectedModelId: string | null;
  selectedModelByThread: Record<string, string>;
  repositoriesLoaded: boolean;
  messagesByThread: Record<string, ChatMessage[]>;
  messagesLoadingByThread: Record<string, boolean>;
  streamingContentByThread: Record<string, string>;
  toolCallsByThread: Record<string, ToolCallEvent[]>;
  abortRequestedByThread: Record<string, boolean>;
  streamingThreadIds: Record<string, boolean>;
  streamingThreadId: string | null;
  messageQueueByThread: Record<string, Array<{ content: MessageContent; model: string; options?: SendMessageOptions }>>;
  setSelectedIssueId: (id: string | null) => void;
  setSelectedFilePath: (path: string | null) => void;
  setActiveTab: (tab: AgentTab) => void;
  setSelectedSkill: (skill: any | null) => void;
  setSelectedSkillSource: (source: { id: string; name: string; description: string } | null) => void;
  setSelectedAutomation: (automation: any | null) => void;
  setSelectedModelId: (id: string) => void;
  setThreadModelId: (threadId: string, modelId: string) => void;
  getEffectiveModelId: (repoId: string, threadId: string) => string | null;
  updateRepositorySettings: (repoId: string, patch: { displayName?: string | null; defaultBranch?: string; defaultModelId?: string | null; reviewModelId?: string | null; defaultMergeAction?: string | null }) => Promise<void>;
  loadAiProviders: () => Promise<void>;
  loadRepositories: () => Promise<void>;
  loadMessages: (threadId: string) => Promise<void>;
  sendMessage: (threadId: string, content: MessageContent, model: string, silent?: boolean, options?: SendMessageOptions) => Promise<void>;
  loadFileChanges: (workspacePath: string) => Promise<void>;
  addRepository: (repo: { name: string, id: string }, thread: { title: string, id: string, workspace_path: string }) => void;
  addThread: (repoId: string, thread: { title: string, id: string, workspace_path: string }) => void;
  abortThread: (threadId: string) => Promise<void>;
  removeThread: (repoId: string, threadId: string) => void;
  removeRepository: (id: string) => void;
  prUrlByThread: Record<string, PrInfo>;
  setThreadPrInfo: (threadId: string, prInfo: PrInfo) => void;
  loadPrUrl: (threadId: string, workspacePath: string) => Promise<void>;
  prCiByThread: Record<string, PrCiStatus | null>;
  mergedBannerDismissedByThread: Record<string, boolean>;
  dismissMergedBanner: (threadId: string) => void;
  loadPrCi: (threadId: string, workspacePath: string) => Promise<void>;
  isFilesAllExpanded: boolean;
  setIsFilesAllExpanded: (expanded: boolean) => void;
  showAddRepositoryDialog: boolean;
  setShowAddRepositoryDialog: (show: boolean) => void;
  isRightSidebarOpen: boolean;
  setIsRightSidebarOpen: (open: boolean) => void;
  diffViewTab: "changes" | "files";
  setDiffViewTab: (tab: "changes" | "files") => void;
  diffSplitView: boolean;
  setDiffSplitView: (split: boolean) => void;
  islandPanel: "diff" | "terminal" | "ci";
  setIslandPanel: (panel: "diff" | "terminal" | "ci") => void;
  expandedRepos: Record<string, boolean>;
  setExpandedRepos: (update: Record<string, boolean> | ((prev: Record<string, boolean>) => Record<string, boolean>)) => void;
  collapsedFilesByThread: Record<string, Record<string, boolean>>;
  setFileCollapsed: (threadId: string, filename: string, collapsed: boolean) => void;
  installedSkills: InstalledSkill[];
  setInstalledSkills: (skills: InstalledSkill[]) => void;
}

export type AgentsSliceCreator<T> = StateCreator<AgentsState, [["zustand/persist", unknown]], [], T>;
