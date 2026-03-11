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
  isStreaming: boolean;
  setSelectedIssueId: (id: string | null) => void;
  setSelectedFilePath: (path: string | null) => void;
  setActiveTab: (tab: "workspace" | "skills" | "automations" | "create-automation" | "manage-skill") => void;
  setSelectedSkill: (skill: any | null) => void;
  setSelectedAutomation: (automation: any | null) => void;
  setSelectedModelId: (id: string) => void;
  loadAiProviders: () => Promise<void>;
  loadRepositories: () => Promise<void>;
  loadMessages: (threadId: string) => Promise<void>;
  sendMessage: (threadId: string, content: string, model: string) => Promise<void>;
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
      isStreaming: false,
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
          set({ messages, streamingContent: "" });
        } catch {
          set({ messages: [] });
        }
      },
      sendMessage: async (threadId: string, content: string, model: string) => {
        // Optimistically add the user message to the UI immediately.
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
          isStreaming: true,
        }));

        // Set up streaming listeners before invoking the command.
        const unlistenToken = await listen<{ thread_id: string; token: string }>(
          "agent-stream-token",
          (event) => {
            if (event.payload.thread_id !== threadId) return;
            set((state) => ({
              streamingContent: state.streamingContent + event.payload.token,
            }));
          }
        );

        const unlistenDone = await listen<{ thread_id: string }>(
          "agent-stream-done",
          async (event) => {
            if (event.payload.thread_id !== threadId) return;
            unlistenToken();
            unlistenDone();
            unlistenError();
            // Reload persisted messages from the backend so IDs and model are correct.
            await get().loadMessages(threadId);
            set({ isStreaming: false, streamingContent: "" });
          }
        );

        const unlistenError = await listen<{ thread_id: string; error: string }>(
          "agent-stream-error",
          (event) => {
            if (event.payload.thread_id !== threadId) return;
            unlistenToken();
            unlistenDone();
            unlistenError();
            set({ isStreaming: false, streamingContent: "" });
            toast.error(`Agent error: ${event.payload.error}`);
          }
        );

        try {
          await invoke("agents_send_message", { threadId, message: content, model });
        } catch (err) {
          unlistenToken();
          unlistenDone();
          unlistenError();
          set({ isStreaming: false, streamingContent: "" });
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
      }),
    }
  )
);
