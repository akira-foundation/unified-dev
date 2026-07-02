import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";

import type { AgentsState } from "./agents/types";
import { createLoadersSlice } from "./agents/loaders-slice";
import { createSendMessageSlice } from "./agents/send-message-slice";
import { createThreadActionsSlice } from "./agents/thread-actions-slice";

export type {
  SendMessageOptions,
  InstalledSkill,
  PrCheck,
  PrCiStatus,
  ChatMessage,
  ToolCallEvent,
  AgentsState,
} from "./agents/types";

export const useAgentsStore = create<AgentsState>()(
  persist(
    (set, get, api) => ({
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
      isRightSidebarOpen: false,
      diffViewTab: "changes",
      diffSplitView: false,
      islandPanel: "diff",
      prUrlByThread: {},
      setThreadPrInfo: (threadId, prInfo) => set((state) => ({
        prUrlByThread: { ...state.prUrlByThread, [threadId]: prInfo },
      })),
      prCiByThread: {},
      mergedBannerDismissedByThread: {},
      dismissMergedBanner: (threadId) => set((state) => ({
        mergedBannerDismissedByThread: { ...state.mergedBannerDismissedByThread, [threadId]: true },
      })),
      messagesByThread: {},
      messagesLoadingByThread: {},
      streamingContentByThread: {},
      toolCallsByThread: {},
      abortRequestedByThread: {},
      streamingThreadIds: {},
      streamStartedAtByThread: {},
      streamingThreadId: null,
      messageQueueByThread: {},
      setIsFilesAllExpanded: (expanded) => set({ isFilesAllExpanded: expanded }),
      setShowAddRepositoryDialog: (show) => set({ showAddRepositoryDialog: show }),
      setIsRightSidebarOpen: (open) => set({ isRightSidebarOpen: open }),
      setDiffViewTab: (tab) => set({ diffViewTab: tab }),
      setDiffSplitView: (split) => set({ diffSplitView: split }),
      setIslandPanel: (panel) => set({ islandPanel: panel }),
      expandedRepos: { "repo-1": true, "repo-4": true },
      setExpandedRepos: (update) => set((state) => ({
        expandedRepos: typeof update === "function" ? update(state.expandedRepos) : update
      })),
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
      setSelectedIssueId: (id) => set((state) => {
        const repoId = id
          ? state.repositoryGroups.flatMap((g) => g.repositories).find((r) => r.issues.some((i) => i.id === id))?.id
          : undefined;
        return {
          selectedIssueId: id,
          activeTab: "workspace",
          expandedRepos: repoId ? { ...state.expandedRepos, [repoId]: true } : state.expandedRepos,
        };
      }),
      setSelectedFilePath: (path) => set({ selectedFilePath: path }),
      setActiveTab: (tab) => set((state) => ({ previousTab: state.activeTab, activeTab: tab })),
      setSelectedSkill: (skill) => set((state) => ({ selectedSkill: skill, previousTab: state.activeTab, activeTab: "manage-skill" })),
      setSelectedSkillSource: (source) => set((state) => ({ selectedSkillSource: source, previousTab: state.activeTab, activeTab: "skill-source" })),
      setSelectedAutomation: (automation) => set((state) => ({ selectedAutomation: automation, previousTab: state.activeTab, activeTab: "create-automation" })),
      setSelectedModelId: (id) => set({ selectedModelId: id }),
      setThreadModelId: (threadId, modelId) => set((state) => ({
        selectedModelByThread: { ...state.selectedModelByThread, [threadId]: modelId },
      })),
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
      ...createLoadersSlice(set, get, api),
      ...createSendMessageSlice(set, get, api),
      ...createThreadActionsSlice(set, get, api),
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
