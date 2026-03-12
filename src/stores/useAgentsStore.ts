import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { toast } from "sonner";
import type { AgentTimelineStep, FileChange, RepositoryGroup, AgentStatus } from "../types/agents";
import type { AiProviderGroup, AiProviderResponse } from "../types/ai-providers";

export interface ChatMessage {
  id: string;
  thread_id: string;
  role: "user" | "assistant" | "system" | "tool";
  model: string | null;
  content: string;
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
  activeTab: "workspace" | "skills" | "automations" | "create-automation" | "manage-skill";
  selectedSkill: any | null;
  selectedAutomation: any | null;
  aiProviders: AiProviderGroup[];
  selectedModelId: string | null;
  repositoriesLoaded: boolean;
  // Chat
  messages: ChatMessage[];
  streamingContent: string;
  // Per-thread streaming state — keyed by threadId. Use this instead of a
  // global boolean so that streaming in one thread does not block others.
  streamingThreadIds: Record<string, boolean>;
  // Which thread is currently streaming (may differ from selectedIssueId when navigating)
  streamingThreadId: string | null;
  // Live tool call events during agentic loop
  toolCalls: ToolCallEvent[];
  setSelectedIssueId: (id: string | null) => void;
  setSelectedFilePath: (path: string | null) => void;
  setActiveTab: (tab: "workspace" | "skills" | "automations" | "create-automation" | "manage-skill") => void;
  setSelectedSkill: (skill: any | null) => void;
  setSelectedAutomation: (automation: any | null) => void;
  setSelectedModelId: (id: string) => void;
  loadAiProviders: () => Promise<void>;
  loadRepositories: () => Promise<void>;
  loadMessages: (threadId: string) => Promise<void>;
  sendMessage: (threadId: string, content: string, model: string, silent?: boolean) => Promise<void>;
  loadFileChanges: (workspacePath: string) => Promise<void>;
  addRepository: (repo: { name: string, id: string }, thread: { title: string, id: string, workspace_path: string }) => void;
  addThread: (repoId: string, thread: { title: string, id: string, workspace_path: string }) => void;
  removeThread: (repoId: string, threadId: string) => void;
  removeRepository: (id: string) => void;
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
  // Collapsed state of each file card in the diff viewer, keyed by threadId → filename
  collapsedFilesByThread: Record<string, Record<string, boolean>>;
  setFileCollapsed: (threadId: string, filename: string, collapsed: boolean) => void;
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
      selectedSkill: null,
      selectedAutomation: null,
      aiProviders: [],
      selectedModelId: null,
      repositoriesLoaded: false,
      isFilesAllExpanded: false,
      showAddRepositoryDialog: false,
      isRightSidebarOpen: true,
      diffViewTab: "changes",
      // Chat initial state
      messages: [],
      streamingContent: "",
      streamingThreadIds: {},
      streamingThreadId: null,
      toolCalls: [],
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
      setSelectedIssueId: (id) => set({ selectedIssueId: id, activeTab: "workspace" }),
      setSelectedFilePath: (path) => set({ selectedFilePath: path }),
      setActiveTab: (tab) => set({ activeTab: tab }),
      setSelectedSkill: (skill) => set({ selectedSkill: skill, activeTab: "manage-skill" }),
      setSelectedAutomation: (automation) => set({ selectedAutomation: automation, activeTab: "create-automation" }),
      setSelectedModelId: (id) => set({ selectedModelId: id }),
      loadAiProviders: async () => {
        try {
          const response = await invoke<AiProviderResponse>("get_available_models");
          const providers = response.providers;
          const defaultModel = selectDefaultModel(providers);
          set({ aiProviders: providers, selectedModelId: defaultModel });
        } catch {
          set({ aiProviders: [], selectedModelId: null });
        }
      },
      loadRepositories: async () => {
        try {
          const rows = await invoke<Array<{ id: string; name: string; threads: Array<{ id: string; title: string; branch: string; workspace_path: string; status: string; created_at: string }> }>>("list_repositories");
          const repositories = rows.map((row) => ({
            id: row.id,
            name: row.name,
            issues: row.threads.map((t) => ({
              id: t.id,
              title: t.title,
              repoId: row.id,
              workspacePath: t.workspace_path,
              repoName: row.name,
              branchName: t.branch,
              agentName: "Unified Dev",
              status: "Running" as AgentStatus,
              updatedAt: t.created_at,
            })),
          }));
          set({
            repositoryGroups: [{ name: "THREADS", repositories }],
            repositoriesLoaded: true,
          });
        } catch {
          set({ repositoriesLoaded: true });
        }
      },
      loadMessages: async (threadId: string) => {
        try {
          const messages = await invoke<ChatMessage[]>("agents_get_messages", { threadId });
          // Only reset streamingContent if we're loading a thread that isn't actively streaming.
          const { streamingThreadId } = get();
          set({
            messages,
            streamingContent: streamingThreadId === threadId ? get().streamingContent : "",
          });
        } catch {
          set({ messages: [] });
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
      sendMessage: async (threadId: string, content: string, model: string, silent = false) => {
        const { repositoryGroups } = get();

        // Resolve workspace path for the current thread
        const allIssues = repositoryGroups.flatMap((g) => g.repositories.flatMap((r) => r.issues));
        const thread = allIssues.find((i) => i.id === threadId);
        const workspacePath = thread?.workspacePath ?? "";

        // ── Slash command interception ─────────────────────────────────────
        const trimmed = content.trim();

        if (trimmed === "/clear") {
          set({ messages: [], streamingContent: "" });
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
          set((state) => ({ messages: [...state.messages, userMsg] }));

          try {
            const output = await invoke<string>("run_workspace_command", {
              workspacePath,
              command: shellCmd,
            });

            // Show output as a tool message in the UI
            const toolMsg: ChatMessage = {
              id: crypto.randomUUID(),
              thread_id: threadId,
              role: "tool",
              model: null,
              content: output || "(no output)",
              metadata: null,
              created_at: new Date().toISOString(),
            };
            set((state) => ({ messages: [...state.messages, toolMsg] }));
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
            set((state) => ({ messages: [...state.messages, errMsg] }));
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
            messages: [...state.messages, optimisticUserMessage],
            streamingContent: "",
            streamingThreadIds: { ...state.streamingThreadIds, [threadId]: true },
            streamingThreadId: threadId,
            toolCalls: [],
          }));
        } else {
          set((state) => ({
            streamingContent: "",
            streamingThreadIds: { ...state.streamingThreadIds, [threadId]: true },
            streamingThreadId: threadId,
            toolCalls: [],
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
            set((state) => ({ streamingContent: state.streamingContent + buffered }));
          }
        };

        // Set up streaming listeners before invoking the command.
        const unlistenToken = await listen<{ thread_id: string; token: string }>(
          "agent-stream-token",
          (event) => {
            if (event.payload.thread_id !== threadId) return;
            tokenBuffer += event.payload.token;
            if (!flushTimer) {
              flushTimer = setTimeout(() => {
                const buffered = tokenBuffer;
                tokenBuffer = "";
                flushTimer = null;
                set((state) => ({ streamingContent: state.streamingContent + buffered }));
              }, 50);
            }
          }
        );

        const unlistenToolCall = await listen<{ thread_id: string; label: string; status: string; output?: string }>(
          "agent-stream-tool-call",
          (event) => {
            if (event.payload.thread_id !== threadId) return;
            set((state) => {
              const { label, status, output } = event.payload;
              // Find last running entry with matching label
              let existingIdx = -1;
              for (let i = state.toolCalls.length - 1; i >= 0; i--) {
                if (state.toolCalls[i].label === label && state.toolCalls[i].status === "running") {
                  existingIdx = i;
                  break;
                }
              }
              if (existingIdx !== -1) {
                // Update existing running entry to done/error
                const updated = [...state.toolCalls];
                updated[existingIdx] = { ...updated[existingIdx], status: status as "running" | "done" | "error", output };
                return { toolCalls: updated };
              }
              // Add new entry
              return {
                toolCalls: [
                  ...state.toolCalls,
                  { id: crypto.randomUUID(), label, status: status as "running" | "done" | "error", output },
                ],
              };
            });
          }
        );

        const unlistenDone = await listen<{ thread_id: string }>(
          "agent-stream-done",
          async (event) => {
            if (event.payload.thread_id !== threadId) return;
            unlistenToken();
            unlistenToolCall();
            unlistenDone();
            unlistenError();
            flushTokenBuffer();
            set((state) => ({
              streamingThreadIds: { ...state.streamingThreadIds, [threadId]: false },
              streamingContent: "",
              streamingThreadId: null,
              toolCalls: [],
            }));
            // Only reload messages into visible state if still on this thread.
            if (get().selectedIssueId === threadId) {
              await get().loadMessages(threadId);
            }
            // Refresh file changes after the agent finishes writing
            if (workspacePath) {
              await get().loadFileChanges(workspacePath);
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
              streamingThreadIds: { ...state.streamingThreadIds, [threadId]: false },
              streamingContent: "",
              streamingThreadId: null,
              toolCalls: [],
            }));
            toast.error(`Agent error: ${event.payload.error}`);
          }
        );

        try {
          await invoke("agents_send_message", { threadId, message: content, model, silent });
        } catch (err) {
          unlistenToken();
          unlistenDone();
          unlistenError();
          flushTokenBuffer();
          set((state) => ({
            streamingThreadIds: { ...state.streamingThreadIds, [threadId]: false },
            streamingContent: "",
            streamingThreadId: null,
          }));
          toast.error(`Failed to send message: ${err}`);
        }
      },
      addRepository: (repo, thread) => set((state) => {
        const newGroups = [...state.repositoryGroups];
        const threadsGroup = newGroups.find(g => g.name === "THREADS");
        if (threadsGroup) {
          threadsGroup.repositories.unshift({
            id: repo.id,
            name: repo.name,
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
      removeThread: (repoId, threadId) => set((state) => {
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

        return { repositoryGroups: newGroups, selectedIssueId: nextSelectedId };
      }),
      removeRepository: (id) => set((state) => {
        const newGroups = state.repositoryGroups.map(group => ({
          ...group,
          repositories: group.repositories.filter(r => r.id !== id)
        }));
        return { repositoryGroups: newGroups };
      }),
    }),
    {
      name: "unified_dev_agents",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({
        selectedIssueId: state.selectedIssueId,
        activeTab: state.activeTab,
        selectedModelId: state.selectedModelId,
        collapsedFilesByThread: state.collapsedFilesByThread,
      }),
    }
  )
);
