import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { toast } from "sonner";
import type { AgentTimelineStep, FileChange, RepositoryGroup, AgentStatus, MessageContent } from "../types/agents";
import { serializeContent, contentToText, parseContent } from "../types/agents";
import type { AiProviderGroup, AiProviderResponse } from "../types/ai-providers";
import { openUpgradeModal } from "../stores/upgrade-modal-store";
import { refreshUsage } from "../stores/usage-store";

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

interface AgentsState {
  repositoryGroups: RepositoryGroup[];
  selectedIssueId: string | null;
  timelineSteps: AgentTimelineStep[];
  fileChanges: FileChange[];
  selectedFilePath: string | null;
  activeTab: "workspace" | "skills" | "automations" | "create-automation" | "manage-skill" | "mcp" | "skill-source";
  previousTab: "workspace" | "skills" | "automations" | "create-automation" | "manage-skill" | "mcp" | "skill-source" | null;
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
  setActiveTab: (tab: "workspace" | "skills" | "automations" | "create-automation" | "manage-skill" | "mcp" | "skill-source") => void;
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
  prUrlByThread: Record<string, { url: string; isDraft: boolean } | null>;
  setThreadPrInfo: (threadId: string, prInfo: { url: string; isDraft: boolean } | null) => void;
  loadPrUrl: (threadId: string, workspacePath: string) => Promise<void>;
  isFilesAllExpanded: boolean;
  setIsFilesAllExpanded: (expanded: boolean) => void;
  showAddRepositoryDialog: boolean;
  setShowAddRepositoryDialog: (show: boolean) => void;
  isRightSidebarOpen: boolean;
  setIsRightSidebarOpen: (open: boolean) => void;
  diffViewTab: "changes" | "files";
  setDiffViewTab: (tab: "changes" | "files") => void;
  expandedRepos: Record<string, boolean>;
  setExpandedRepos: (update: Record<string, boolean> | ((prev: Record<string, boolean>) => Record<string, boolean>)) => void;
  isTerminalOpen: boolean;
  setIsTerminalOpen: (open: boolean) => void;
  collapsedFilesByThread: Record<string, Record<string, boolean>>;
  setFileCollapsed: (threadId: string, filename: string, collapsed: boolean) => void;
  installedSkills: InstalledSkill[];
  setInstalledSkills: (skills: InstalledSkill[]) => void;
}

function selectDefaultModel(providers: AiProviderGroup[]): string | null {
  if (providers.length === 0) return null;
  const claude = providers.find((p) => p.name === "Claude");
  if (claude && claude.models.length > 0) {
    const sonnet = claude.models.find((m) => m.id.includes("sonnet"));
    return sonnet ? sonnet.id : claude.models[0].id;
  }
  return providers[0].models[0]?.id ?? null;
}

export const useAgentsStore = create<AgentsState>()(
  persist(
    (set, get) => ({
      repositoryGroups: [{ name: "THREADS", repositories: [] }],
      selectedIssueId: null,
      timelineSteps: [],
      fileChanges: [],
      selectedFilePath: null,
      activeTab: "workspace",
      previousTab: null,
      selectedSkill: null,
      selectedSkillSource: null,
      selectedAutomation: null,
      aiProviders: [],
      selectedModelId: null,
      selectedModelByThread: {},
      repositoriesLoaded: false,
      isFilesAllExpanded: false,
      showAddRepositoryDialog: false,
      isRightSidebarOpen: true,
      diffViewTab: "changes",
      prUrlByThread: {},
      setThreadPrInfo: (threadId, prInfo) => set((state) => ({
        prUrlByThread: { ...state.prUrlByThread, [threadId]: prInfo },
      })),
      messagesByThread: {},
      messagesLoadingByThread: {},
      streamingContentByThread: {},
      toolCallsByThread: {},
      abortRequestedByThread: {},
      streamingThreadIds: {},
      streamingThreadId: null,
      messageQueueByThread: {},
      setIsFilesAllExpanded: (expanded) => set({ isFilesAllExpanded: expanded }),
      setShowAddRepositoryDialog: (show) => set({ showAddRepositoryDialog: show }),
      setIsRightSidebarOpen: (open) => set({ isRightSidebarOpen: open }),
      setDiffViewTab: (tab) => set({ diffViewTab: tab }),
      expandedRepos: { "repo-1": true, "repo-4": true },
      setExpandedRepos: (update) => set((state) => ({
        expandedRepos: typeof update === "function" ? update(state.expandedRepos) : update
      })),
      isTerminalOpen: false,
      setIsTerminalOpen: (open) => set({ isTerminalOpen: open }),
      collapsedFilesByThread: {},
      setFileCollapsed: (threadId, filename, collapsed) => set((state) => ({
        collapsedFilesByThread: {
          ...state.collapsedFilesByThread,
          [threadId]: {
            ...state.collapsedFilesByThread[threadId],
            [filename]: collapsed,
          },
        },
      })),
      installedSkills: [],
      setInstalledSkills: (skills) => set({ installedSkills: skills }),
      setSelectedIssueId: (id) => set({ selectedIssueId: id, activeTab: "workspace" }),
      setSelectedFilePath: (path) => set({ selectedFilePath: path }),
      setActiveTab: (tab) => set((state) => ({ previousTab: state.activeTab, activeTab: tab })),
      setSelectedSkill: (skill) => set((state) => ({ selectedSkill: skill, previousTab: state.activeTab, activeTab: "manage-skill" })),
      setSelectedSkillSource: (source) => set((state) => ({ selectedSkillSource: source, previousTab: state.activeTab, activeTab: "skill-source" })),
      setSelectedAutomation: (automation) => set((state) => ({ selectedAutomation: automation, previousTab: state.activeTab, activeTab: "create-automation" })),
      setSelectedModelId: (id) => set({ selectedModelId: id }),
      setThreadModelId: (threadId, modelId) => set((state) => ({
        selectedModelByThread: { ...state.selectedModelByThread, [threadId]: modelId },
      })),
      updateRepositorySettings: async (repoId, patch) => {
        try {
          await invoke("update_repository_settings", {
            repoId,
            displayName: patch.displayName !== undefined && patch.displayName !== null ? patch.displayName : null,
            clearDisplayName: patch.displayName !== undefined && patch.displayName === null,
            defaultBranch: patch.defaultBranch ?? null,
            defaultModelId: patch.defaultModelId !== undefined && patch.defaultModelId !== null ? patch.defaultModelId : null,
            clearDefaultModelId: patch.defaultModelId !== undefined && patch.defaultModelId === null,
            reviewModelId: patch.reviewModelId !== undefined && patch.reviewModelId !== null ? patch.reviewModelId : null,
            clearReviewModelId: patch.reviewModelId !== undefined && patch.reviewModelId === null,
            defaultMergeAction: patch.defaultMergeAction !== undefined && patch.defaultMergeAction !== null ? patch.defaultMergeAction : null,
            clearDefaultMergeAction: patch.defaultMergeAction !== undefined && patch.defaultMergeAction === null,
          });
        } catch (e) {
          console.error("update_repository_settings failed:", e);
          throw e;
        }
        set((state) => ({
          repositoryGroups: state.repositoryGroups.map((group) => ({
            ...group,
            repositories: group.repositories.map((repo) => {
              if (repo.id !== repoId) return repo;
              return {
                ...repo,
                displayName: patch.displayName !== undefined ? patch.displayName : repo.displayName,
                defaultBranch: patch.defaultBranch ?? repo.defaultBranch,
                defaultModelId: patch.defaultModelId !== undefined ? patch.defaultModelId : repo.defaultModelId,
                reviewModelId: patch.reviewModelId !== undefined ? patch.reviewModelId : repo.reviewModelId,
                defaultMergeAction: patch.defaultMergeAction !== undefined ? patch.defaultMergeAction : repo.defaultMergeAction,
              };
            }),
          })),
        }));
      },
      getEffectiveModelId: (repoId, threadId) => {
        const state = get();
        const repo = state.repositoryGroups.flatMap((g) => g.repositories).find((r) => r.id === repoId);
        return (
          state.selectedModelByThread[threadId] ??
          repo?.defaultModelId ??
          state.selectedModelId ??
          null
        );
      },
      loadAiProviders: async () => {
        try {
          const response = await invoke<AiProviderResponse>("get_available_models");
          const providers = response.providers;
          const allModelIds = new Set(providers.flatMap((p) => p.models.map((m) => m.id)));
          const currentModelId = get().selectedModelId;
          const selectedModelId = currentModelId && allModelIds.has(currentModelId)
            ? currentModelId
            : selectDefaultModel(providers);
          const selectedModelByThread = Object.fromEntries(
            Object.entries(get().selectedModelByThread).filter(([, id]) => allModelIds.has(id))
          );
          set({ aiProviders: providers, selectedModelId, selectedModelByThread });
        } catch {
          set({ aiProviders: [], selectedModelId: null });
        }
      },
      loadRepositories: async () => {
        try {
          const rows = await invoke<Array<{
            id: string;
            name: string;
            default_branch: string;
            display_name: string | null;
            default_model_id: string | null;
            review_model_id: string | null;
            default_merge_action: string | null;
            remote_url: string | null;
            threads: Array<{ id: string; title: string; branch: string; workspace_path: string; status: string; created_at: string; pr_url: string | null; pr_is_draft: boolean }>;
          }>>("list_repositories");
          const prUrlByThread: Record<string, { url: string; isDraft: boolean } | null> = {};
          const repositories = rows.map((row) => ({
            id: row.id,
            name: row.name,
            defaultBranch: row.default_branch,
            displayName: row.display_name,
            defaultModelId: row.default_model_id,
            reviewModelId: row.review_model_id,
            defaultMergeAction: row.default_merge_action,
            remoteUrl: row.remote_url,
            issues: row.threads.map((t) => {
              if (t.pr_url) {
                prUrlByThread[t.id] = { url: t.pr_url, isDraft: t.pr_is_draft };
              } else {
                prUrlByThread[t.id] = null;
              }
              return {
                id: t.id,
                title: t.title,
                repoId: row.id,
                workspacePath: t.workspace_path,
                repoName: row.name,
                branchName: t.branch,
                agentName: "Unified Dev",
                status: "Running" as AgentStatus,
                updatedAt: t.created_at,
              };
            }),
          }));
          set({
            repositoryGroups: [{ name: "THREADS", repositories }],
            repositoriesLoaded: true,
            prUrlByThread,
          });
        } catch {
          set({ repositoriesLoaded: true });
        }
      },
      loadMessages: async (threadId: string) => {
        const hasCached = (get().messagesByThread[threadId]?.length ?? 0) > 0;
        if (!hasCached) {
          set((state) => ({
            messagesLoadingByThread: { ...state.messagesLoadingByThread, [threadId]: true },
          }));
        }
        try {
          const raw = await invoke<Array<Omit<ChatMessage, "content"> & { content: string }>>("get_messages", { threadId });
          const messages: ChatMessage[] = raw.map((m) => ({ ...m, content: parseContent(m.content) }));
          set((state) => ({
            messagesByThread: { ...state.messagesByThread, [threadId]: messages },
            messagesLoadingByThread: { ...state.messagesLoadingByThread, [threadId]: false },
          }));
        } catch {
          set((state) => ({
            messagesByThread: { ...state.messagesByThread, [threadId]: [] },
            messagesLoadingByThread: { ...state.messagesLoadingByThread, [threadId]: false },
          }));
        }
      },
      loadFileChanges: async (workspacePath: string) => {
        try {
          const changes = await invoke<FileChange[]>("get_workspace_changes", { workspacePath });
          set({ fileChanges: changes });
        } catch {
          set({ fileChanges: [] });
        }
      },
      loadPrUrl: async (threadId: string, workspacePath: string) => {
        try {
          const info = await invoke<{ url: string; is_draft: boolean }>("check_pr_url", { workspacePath });
          set((state) => ({
            prUrlByThread: {
              ...state.prUrlByThread,
              [threadId]: info.url
                ? { url: info.url, isDraft: info.is_draft }
                : (state.prUrlByThread[threadId] ?? null),
            },
          }));
          // Persist to DB so it survives app reloads.
          if (info.url) {
            await invoke("set_thread_pr_url", {
              threadId,
              prUrl: info.url,
              prIsDraft: info.is_draft,
            }).catch(() => {/* non-fatal */});
          }
        } catch {
          set((state) => ({
            prUrlByThread: {
              ...state.prUrlByThread,
              [threadId]: state.prUrlByThread[threadId] ?? null,
            },
          }));
        }
      },
      sendMessage: async (threadId: string, content: MessageContent, model: string, silent = false, options?: SendMessageOptions) => {
        const { repositoryGroups, streamingThreadIds } = get();

        // If this thread is already streaming, queue the message for later.
        if (streamingThreadIds[threadId]) {
          set((state) => ({
            messageQueueByThread: {
              ...state.messageQueueByThread,
              [threadId]: [...(state.messageQueueByThread[threadId] ?? []), { content, model, options }],
            },
          }));
          return;
        }

        // Resolve workspace path for the current thread
        const allIssues = repositoryGroups.flatMap((g) => g.repositories.flatMap((r) => r.issues));
        const thread = allIssues.find((i) => i.id === threadId);
        const workspacePath = thread?.workspacePath ?? "";

        // ── Slash command interception ─────────────────────────────────────
        const trimmed = contentToText(content).trim();

        if (trimmed === "/clear") {
          set((state) => ({
            messagesByThread: { ...state.messagesByThread, [threadId]: [] },
            streamingContentByThread: { ...state.streamingContentByThread, [threadId]: "" },
          }));
          return;
        }

        // Map slash command → shell command
        const slashCommandMap: Record<string, string> = {
          "/diff":   "git diff",
          "/status": "git status",
          "/branch": "git rev-parse --abbrev-ref HEAD",
          "/tree":   "find . -not -path './.git/*' -not -path './node_modules/*' -not -path './target/*' -not -path './.next/*' -not -path './dist/*' -maxdepth 4",
        };

        const shellCmd = slashCommandMap[trimmed.split(" ")[0]];
        if (shellCmd && workspacePath) {
          // Add user message locally (not persisted — it's a command, not a chat turn)
          const userMsg: ChatMessage = {
            id: crypto.randomUUID(),
            thread_id: threadId,
            role: "user",
            model: null,
            content: trimmed,
            metadata: null,
            created_at: new Date().toISOString(),
          };
          set((state) => ({
            messagesByThread: {
              ...state.messagesByThread,
              [threadId]: [...(state.messagesByThread[threadId] ?? []), userMsg],
            },
          }));

          try {
            const output = await invoke<string>("run_workspace_command", {
              workspacePath,
              command: shellCmd,
            });

            const toolMsg: ChatMessage = {
              id: crypto.randomUUID(),
              thread_id: threadId,
              role: "tool",
              model: null,
              content: output || "(no output)",
              metadata: null,
              created_at: new Date().toISOString(),
            };
            set((state) => ({
              messagesByThread: {
                ...state.messagesByThread,
                [threadId]: [...(state.messagesByThread[threadId] ?? []), toolMsg],
              },
            }));
          } catch (err) {
            const errMsg: ChatMessage = {
              id: crypto.randomUUID(),
              thread_id: threadId,
              role: "tool",
              model: null,
              content: `Error: ${err}`,
              metadata: null,
              created_at: new Date().toISOString(),
            };
            set((state) => ({
              messagesByThread: {
                ...state.messagesByThread,
                [threadId]: [...(state.messagesByThread[threadId] ?? []), errMsg],
              },
            }));
          }
          return;
        }
        // ──────────────────────────────────────────────────────────────────
        // Optimistically add the user message to the UI immediately (skipped for silent/action prompts).
        if (!silent) {
          const optimisticUserMessage: ChatMessage = {
            id: crypto.randomUUID(),
            thread_id: threadId,
            role: "user",
            model: null,
            content,
            metadata: null,
            created_at: new Date().toISOString(),
          };

          set((state) => ({
            messagesByThread: {
              ...state.messagesByThread,
              [threadId]: [...(state.messagesByThread[threadId] ?? []), optimisticUserMessage],
            },
            streamingContentByThread: { ...state.streamingContentByThread, [threadId]: "" },
            abortRequestedByThread: { ...state.abortRequestedByThread, [threadId]: false },
            streamingThreadIds: { ...state.streamingThreadIds, [threadId]: true },
            streamingThreadId: threadId,
            toolCallsByThread: { ...state.toolCallsByThread, [threadId]: [] },
          }));
        } else {
          set((state) => ({
            streamingContentByThread: { ...state.streamingContentByThread, [threadId]: "" },
            abortRequestedByThread: { ...state.abortRequestedByThread, [threadId]: false },
            streamingThreadIds: { ...state.streamingThreadIds, [threadId]: true },
            streamingThreadId: threadId,
            toolCallsByThread: { ...state.toolCallsByThread, [threadId]: [] },
          }));
        }

        // Buffer for incoming tokens — flushed to Zustand at most every 50ms
        // to avoid a re-render per token (which causes ReactMarkdown to re-parse
        // the entire string on every keystroke, freezing the UI on long responses).
        let tokenBuffer = "";
        let flushTimer: ReturnType<typeof setTimeout> | null = null;

        const flushTokenBuffer = () => {
          if (flushTimer) {
            clearTimeout(flushTimer);
            flushTimer = null;
          }
          if (tokenBuffer) {
            const buffered = tokenBuffer;
            tokenBuffer = "";
            set((state) => ({
              streamingContentByThread: {
                ...state.streamingContentByThread,
                [threadId]: (state.streamingContentByThread[threadId] ?? "") + buffered,
              },
            }));
          }
        };

        // Set up streaming listeners before invoking the command.
        const unlistenToken = await listen<{ thread_id: string; token: string }>(
          "agent-stream-token",
          (event) => {
            if (event.payload.thread_id !== threadId) return;
            if (get().abortRequestedByThread[threadId]) return;
            tokenBuffer += event.payload.token;
            if (!flushTimer) {
              flushTimer = setTimeout(() => {
                const buffered = tokenBuffer;
                tokenBuffer = "";
                flushTimer = null;
                set((state) => ({
                  streamingContentByThread: {
                    ...state.streamingContentByThread,
                    [threadId]: (state.streamingContentByThread[threadId] ?? "") + buffered,
                  },
                }));
              }, 50);
            }
          }
        );

        const unlistenToolCall = await listen<{ thread_id: string; label: string; status: string; output?: string }>(
          "agent-stream-tool-call",
          (event) => {
            if (event.payload.thread_id !== threadId) return;
            if (get().abortRequestedByThread[threadId]) return;
            set((state) => {
              const { label, status, output } = event.payload;
              const current = state.toolCallsByThread[threadId] ?? [];
              // Find last running entry with matching label
              let existingIdx = -1;
              for (let i = current.length - 1; i >= 0; i--) {
                if (current[i].label === label && current[i].status === "running") {
                  existingIdx = i;
                  break;
                }
              }
              if (existingIdx !== -1) {
                // Update existing running entry to done/error
                const updated = [...current];
                updated[existingIdx] = { ...updated[existingIdx], status: status as "running" | "done" | "error", output };
                if (status === "done" && label.startsWith("Renaming workspace")) {
                  get().loadRepositories();
                }
                return { toolCallsByThread: { ...state.toolCallsByThread, [threadId]: updated } };
              }
              // Add new entry
              return {
                toolCallsByThread: {
                  ...state.toolCallsByThread,
                  [threadId]: [
                    ...current,
                    { id: crypto.randomUUID(), label, status: status as "running" | "done" | "error", output },
                  ],
                },
              };
            });
          }
        );

        const unlistenDone = await listen<{ thread_id: string; aborted: boolean }>(
          "agent-stream-done",
          async (event) => {
            if (event.payload.thread_id !== threadId) return;
            unlistenToken();
            unlistenToolCall();
            unlistenDone();
            unlistenError();
            flushTokenBuffer();
            set((state) => ({
              abortRequestedByThread: { ...state.abortRequestedByThread, [threadId]: false },
              streamingThreadIds: { ...state.streamingThreadIds, [threadId]: false },
              streamingContentByThread: { ...state.streamingContentByThread, [threadId]: "" },
              streamingThreadId: null,
              toolCallsByThread: { ...state.toolCallsByThread, [threadId]: [] },
            }));
            if (!event.payload.aborted) {
              if (get().selectedIssueId === threadId) {
                await get().loadMessages(threadId);
              }
              if (workspacePath) {
                await get().loadFileChanges(workspacePath);
                await get().loadPrUrl(threadId, workspacePath);
              }
              const queue = get().messageQueueByThread[threadId] ?? [];
              if (queue.length > 0) {
                const [next, ...rest] = queue;
                set((state) => ({
                  messageQueueByThread: { ...state.messageQueueByThread, [threadId]: rest },
                }));
                await get().sendMessage(threadId, next.content, next.model, undefined, next.options);
              }
            }
          }
        );

        const unlistenError = await listen<{ thread_id: string; error: string }>(
          "agent-stream-error",
          (event) => {
            if (event.payload.thread_id !== threadId) return;
            unlistenToken();
            unlistenToolCall();
            unlistenDone();
            unlistenError();
            flushTokenBuffer();
            set((state) => ({
              abortRequestedByThread: { ...state.abortRequestedByThread, [threadId]: false },
              streamingThreadIds: { ...state.streamingThreadIds, [threadId]: false },
              streamingContentByThread: { ...state.streamingContentByThread, [threadId]: "" },
              streamingThreadId: null,
              toolCallsByThread: { ...state.toolCallsByThread, [threadId]: [] },
            }));
            toast.error(`Agent error: ${event.payload.error}`);
          }
        );

        try {
          await invoke("send_message", {
            threadId,
            message: serializeContent(content),
            model,
            silent,
            planMode: options?.planMode ?? false,
            thinkingBudget: options?.thinkingBudget ?? "medium",
            fastMode: options?.fastMode ?? false,
          });
          refreshUsage();
        } catch (err) {
          unlistenToken();
          unlistenDone();
          unlistenError();
          flushTokenBuffer();
          set((state) => ({
            streamingThreadIds: { ...state.streamingThreadIds, [threadId]: false },
            streamingContentByThread: { ...state.streamingContentByThread, [threadId]: "" },
            streamingThreadId: null,
          }));
          if (String(err) === "run_limit_reached") {
            openUpgradeModal("run_limit_reached");
          } else {
            toast.error(`Failed to send message: ${err}`);
          }
        }
      },
      addRepository: (repo, thread) => set((state) => {
        const newGroups = [...state.repositoryGroups];
        const threadsGroup = newGroups.find(g => g.name === "THREADS");
        if (threadsGroup) {
          threadsGroup.repositories.unshift({
            id: repo.id,
            name: repo.name,
            defaultBranch: "",
            displayName: null,
            defaultModelId: null,
            reviewModelId: null,
            defaultMergeAction: null,
            remoteUrl: null,
            issues: [{
              id: thread.id,
              title: thread.title,
              repoId: repo.id,
              workspacePath: thread.workspace_path,
              repoName: repo.name,
              branchName: "main",
              agentName: "Polyscope",
              status: "Running",
              updatedAt: "just now"
            }]
          });
        }
        return { repositoryGroups: newGroups, selectedIssueId: thread.id };
      }),
      addThread: (repoId, thread) => set((state) => {
        const newGroups = state.repositoryGroups.map(group => ({
          ...group,
          repositories: group.repositories.map(repo => {
            if (repo.id !== repoId) return repo;
            return {
              ...repo,
              issues: [...repo.issues, {
                id: thread.id,
                title: thread.title,
                repoId: repo.id,
                workspacePath: thread.workspace_path,
                repoName: repo.name,
                branchName: "main",
                agentName: "Unified Dev",
                status: "Running" as AgentStatus,
                updatedAt: "just now"
              }]
            };
          })
        }));
        return { repositoryGroups: newGroups, selectedIssueId: thread.id };
      }),
      abortThread: async (threadId) => {
        set((state) => ({
          abortRequestedByThread: { ...state.abortRequestedByThread, [threadId]: true },
          streamingThreadIds: { ...state.streamingThreadIds, [threadId]: false },
          streamingContentByThread: { ...state.streamingContentByThread, [threadId]: "" },
          streamingThreadId: state.streamingThreadId === threadId ? null : state.streamingThreadId,
          toolCallsByThread: { ...state.toolCallsByThread, [threadId]: [] },
          messageQueueByThread: { ...state.messageQueueByThread, [threadId]: [] },
        }));

        await invoke("abort_agent", { threadId }).catch(() => {});
      },
      removeThread: (repoId, threadId) => {
        set((state) => {
          const newGroups = state.repositoryGroups.map(group => ({
            ...group,
            repositories: group.repositories.map(repo => {
              if (repo.id !== repoId) return repo;
              return {
                ...repo,
                issues: repo.issues.filter(i => i.id !== threadId)
              };
            })
          }));

          const nextSelectedId = state.selectedIssueId === threadId ? null : state.selectedIssueId;

          const streamingContentByThread = { ...state.streamingContentByThread };
          const toolCallsByThread = { ...state.toolCallsByThread };
          const streamingThreadIds = { ...state.streamingThreadIds };
          const messageQueueByThread = { ...state.messageQueueByThread };
          const prUrlByThread = { ...state.prUrlByThread };
          const selectedModelByThread = { ...state.selectedModelByThread };
          const collapsedFilesByThread = { ...state.collapsedFilesByThread };
          const messagesByThread = { ...state.messagesByThread };
          const messagesLoadingByThread = { ...state.messagesLoadingByThread };
          const abortRequestedByThread = { ...state.abortRequestedByThread };
          delete streamingContentByThread[threadId];
          delete toolCallsByThread[threadId];
          delete streamingThreadIds[threadId];
          delete messageQueueByThread[threadId];
          delete prUrlByThread[threadId];
          delete selectedModelByThread[threadId];
          delete collapsedFilesByThread[threadId];
          delete messagesByThread[threadId];
          delete messagesLoadingByThread[threadId];
          delete abortRequestedByThread[threadId];

          return {
            repositoryGroups: newGroups,
            selectedIssueId: nextSelectedId,
            streamingContentByThread,
            toolCallsByThread,
            streamingThreadIds,
            messageQueueByThread,
            prUrlByThread,
            selectedModelByThread,
            collapsedFilesByThread,
            messagesByThread,
            messagesLoadingByThread,
            abortRequestedByThread,
          };
        });

        void import("./useAutopilotStore").then(({ useAutopilotStore }) => {
          useAutopilotStore.getState().removeThreadReference(threadId);
        });
      },
      removeRepository: (id) => set((state) => {
        const newGroups = state.repositoryGroups.map(group => ({
          ...group,
          repositories: group.repositories.filter(r => r.id !== id)
        }));

        const removedRepo = state.repositoryGroups
          .flatMap(g => g.repositories)
          .find(r => r.id === id);
        const removedThreadIds = new Set((removedRepo?.issues ?? []).map(i => i.id));

        const streamingContentByThread = { ...state.streamingContentByThread };
        const toolCallsByThread = { ...state.toolCallsByThread };
        const streamingThreadIds = { ...state.streamingThreadIds };
        const messageQueueByThread = { ...state.messageQueueByThread };
        const prUrlByThread = { ...state.prUrlByThread };
        const selectedModelByThread = { ...state.selectedModelByThread };
        const collapsedFilesByThread = { ...state.collapsedFilesByThread };
        const messagesByThread = { ...state.messagesByThread };
        const messagesLoadingByThread = { ...state.messagesLoadingByThread };
        for (const tid of removedThreadIds) {
          delete streamingContentByThread[tid];
          delete toolCallsByThread[tid];
          delete streamingThreadIds[tid];
          delete messageQueueByThread[tid];
          delete prUrlByThread[tid];
          delete selectedModelByThread[tid];
          delete collapsedFilesByThread[tid];
          delete messagesByThread[tid];
          delete messagesLoadingByThread[tid];
        }

        const nextSelectedId = removedThreadIds.has(state.selectedIssueId ?? "") ? null : state.selectedIssueId;

        return {
          repositoryGroups: newGroups,
          selectedIssueId: nextSelectedId,
          streamingContentByThread,
          toolCallsByThread,
          streamingThreadIds,
          messageQueueByThread,
          prUrlByThread,
          selectedModelByThread,
          collapsedFilesByThread,
          messagesByThread,
          messagesLoadingByThread,
        };
      }),
    }),
    {
      name: "unified_dev_agents",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({
        selectedIssueId: state.selectedIssueId,
        activeTab: state.activeTab,
        selectedModelId: state.selectedModelId,
        selectedModelByThread: state.selectedModelByThread,
        collapsedFilesByThread: state.collapsedFilesByThread,
      }),
    }
  )
);
