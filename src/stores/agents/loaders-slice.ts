import { invoke } from "@tauri-apps/api/core";

import type { AgentStatus, FileChange } from "@/types/agents";
import { parseContent } from "@/types/agents";
import type { AiProviderGroup, AiProviderResponse } from "@/types/ai-providers";
import type { AgentsSliceCreator, ChatMessage, PrCiStatus, PrInfo } from "./types";

function selectDefaultModel(providers: AiProviderGroup[]): string | null {
  if (providers.length === 0) return null;
  const claude = providers.find((p) => p.name === "Claude");
  if (claude && claude.models.length > 0) {
    const sonnet = claude.models.find((m) => m.id.includes("sonnet"));
    return sonnet ? sonnet.id : claude.models[0].id;
  }
  return providers[0].models[0]?.id ?? null;
}

type LoadersSlice = Pick<
  import("./types").AgentsState,
  "loadAiProviders" | "loadRepositories" | "loadMessages" | "loadFileChanges" | "loadPrCi" | "loadPrUrl"
>;

export const createLoadersSlice: AgentsSliceCreator<LoadersSlice> = (set, get) => ({
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
      const prUrlByThread: Record<string, PrInfo> = {};
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
      const selectedId = get().selectedIssueId;
      const selectedRepoId = selectedId
        ? repositories.find((r) => r.issues.some((i) => i.id === selectedId))?.id
        : undefined;
      set((state) => ({
        repositoryGroups: [{ name: "THREADS", repositories }],
        repositoriesLoaded: true,
        prUrlByThread,
        expandedRepos: selectedRepoId
          ? { ...state.expandedRepos, [selectedRepoId]: true }
          : state.expandedRepos,
      }));
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
  loadPrCi: async (threadId: string, workspacePath: string) => {
    try {
      const status = await invoke<PrCiStatus>("check_pr_ci", { workspacePath });
      set((state) => ({
        prCiByThread: { ...state.prCiByThread, [threadId]: status },
      }));
    } catch {
      return;
    }
  },
  loadPrUrl: async (threadId: string, workspacePath: string) => {
    try {
      const info = await invoke<{ url: string; is_draft: boolean; state: string; merged_at: string | null }>("check_pr_url", { workspacePath });
      set((state) => ({
        prUrlByThread: {
          ...state.prUrlByThread,
          [threadId]: info.url
            ? { url: info.url, isDraft: info.is_draft, state: info.state, mergedAt: info.merged_at }
            : (state.prUrlByThread[threadId] ?? null),
        },
      }));
      if (info.url) {
        await invoke("set_thread_pr_url", {
          threadId,
          prUrl: info.url,
          prIsDraft: info.is_draft,
        }).catch(() => {});
        await get().loadPrCi(threadId, workspacePath);
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
});
