import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { toast } from "sonner";

import type { MessageContent } from "@/types/agents";
import { serializeContent, contentToText } from "@/types/agents";
import { openUpgradeModal } from "@/stores/upgrade-modal-store";
import { refreshUsage } from "@/stores/usage-store";
import type { AgentsSliceCreator, AgentsState, ChatMessage } from "./types";

const SLASH_COMMAND_MAP: Record<string, string> = {
  "/diff": "git diff",
  "/status": "git status",
  "/branch": "git rev-parse --abbrev-ref HEAD",
  "/tree": "find . -not -path './.git/*' -not -path './node_modules/*' -not -path './target/*' -not -path './.next/*' -not -path './dist/*' -maxdepth 4",
};

function omitThread(record: Record<string, number>, threadId: string): Record<string, number> {
  const next = { ...record };
  delete next[threadId];
  return next;
}

function makeMessage(threadId: string, role: ChatMessage["role"], content: MessageContent): ChatMessage {
  return {
    id: crypto.randomUUID(),
    thread_id: threadId,
    role,
    model: null,
    content,
    metadata: null,
    created_at: new Date().toISOString(),
  };
}

type SendMessageSlice = Pick<AgentsState, "sendMessage">;

export const createSendMessageSlice: AgentsSliceCreator<SendMessageSlice> = (set, get) => ({
  sendMessage: async (threadId, content, model, silent = false, options) => {
    const { repositoryGroups, streamingThreadIds } = get();

    if (streamingThreadIds[threadId]) {
      set((state) => ({
        messageQueueByThread: {
          ...state.messageQueueByThread,
          [threadId]: [...(state.messageQueueByThread[threadId] ?? []), { content, model, options }],
        },
      }));
      return;
    }

    const allIssues = repositoryGroups.flatMap((g) => g.repositories.flatMap((r) => r.issues));
    const thread = allIssues.find((i) => i.id === threadId);
    const workspacePath = thread?.workspacePath ?? "";

    const trimmed = contentToText(content).trim();

    if (trimmed === "/clear") {
      set((state) => ({
        messagesByThread: { ...state.messagesByThread, [threadId]: [] },
        streamingContentByThread: { ...state.streamingContentByThread, [threadId]: "" },
      }));
      return;
    }

    const shellCmd = SLASH_COMMAND_MAP[trimmed.split(" ")[0]];
    if (shellCmd && workspacePath) {
      set((state) => ({
        messagesByThread: {
          ...state.messagesByThread,
          [threadId]: [...(state.messagesByThread[threadId] ?? []), makeMessage(threadId, "user", trimmed)],
        },
      }));

      try {
        const output = await invoke<string>("run_workspace_command", { workspacePath, command: shellCmd });
        set((state) => ({
          messagesByThread: {
            ...state.messagesByThread,
            [threadId]: [...(state.messagesByThread[threadId] ?? []), makeMessage(threadId, "tool", output || "(no output)")],
          },
        }));
      } catch (err) {
        set((state) => ({
          messagesByThread: {
            ...state.messagesByThread,
            [threadId]: [...(state.messagesByThread[threadId] ?? []), makeMessage(threadId, "tool", `Error: ${err}`)],
          },
        }));
      }
      return;
    }

    if (!silent) {
      set((state) => ({
        messagesByThread: {
          ...state.messagesByThread,
          [threadId]: [...(state.messagesByThread[threadId] ?? []), makeMessage(threadId, "user", content)],
        },
        streamingContentByThread: { ...state.streamingContentByThread, [threadId]: "" },
        abortRequestedByThread: { ...state.abortRequestedByThread, [threadId]: false },
        streamingThreadIds: { ...state.streamingThreadIds, [threadId]: true },
        streamStartedAtByThread: { ...state.streamStartedAtByThread, [threadId]: Date.now() },
        streamingThreadId: threadId,
        toolCallsByThread: { ...state.toolCallsByThread, [threadId]: [] },
      }));
    } else {
      set((state) => ({
        streamingContentByThread: { ...state.streamingContentByThread, [threadId]: "" },
        abortRequestedByThread: { ...state.abortRequestedByThread, [threadId]: false },
        streamingThreadIds: { ...state.streamingThreadIds, [threadId]: true },
        streamStartedAtByThread: { ...state.streamStartedAtByThread, [threadId]: Date.now() },
        streamingThreadId: threadId,
        toolCallsByThread: { ...state.toolCallsByThread, [threadId]: [] },
      }));
    }

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
          let existingIdx = -1;
          for (let i = current.length - 1; i >= 0; i--) {
            if (current[i].label === label && current[i].status === "running") {
              existingIdx = i;
              break;
            }
          }
          if (existingIdx !== -1) {
            const updated = [...current];
            updated[existingIdx] = { ...updated[existingIdx], status: status as "running" | "done" | "error", output };
            if (status === "done" && label.startsWith("Renaming workspace")) {
              get().loadRepositories();
            }
            return { toolCallsByThread: { ...state.toolCallsByThread, [threadId]: updated } };
          }
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
          streamStartedAtByThread: omitThread(state.streamStartedAtByThread, threadId),
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
          streamStartedAtByThread: omitThread(state.streamStartedAtByThread, threadId),
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
        streamStartedAtByThread: omitThread(state.streamStartedAtByThread, threadId),
        streamingContentByThread: { ...state.streamingContentByThread, [threadId]: "" },
        streamingThreadId: null,
      }));
      if (String(err) === "run_limit_reached") {
        openUpgradeModal("run_limit_reached");
      } else {
        toast.error(`Failed to send message: ${err}`);
      }
    }
  } ,
});
