import { invoke } from "@tauri-apps/api/core";

import type { AgentStatus } from "@/types/agents";
import type { AgentsSliceCreator, AgentsState } from "./types";

type ThreadActionsSlice = Pick<
  AgentsState,
  "updateRepositorySettings" | "addRepository" | "addThread" | "abortThread" | "removeThread" | "removeRepository"
>;

export const createThreadActionsSlice: AgentsSliceCreator<ThreadActionsSlice> = (set) => ({
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

    void import("../useAutopilotStore").then(({ useAutopilotStore }) => {
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
});
