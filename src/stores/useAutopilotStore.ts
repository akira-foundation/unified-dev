import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { useAgentsStore } from "./useAgentsStore";
import type { IssueDto } from "@/types/issue";

export type AutopilotJobStatus = "running" | "waiting" | "stopping" | "done" | "stopped" | "error";
export type AutopilotModelMode = "current" | "single" | "random";
export type AutopilotFilter = "all" | "unassigned" | "no_pr" | "assigned_to_me";

export interface AutopilotConfig {
  batchSize: number;
  delayMs: number;
  modelMode: AutopilotModelMode;
  modelId: string | null;
  filter: AutopilotFilter;
  assignedToLogin: string | null;
  autoSend: boolean;
}

export interface AutopilotThreadResult {
  rowId: string;
  issueId: string;
  issueNumber: number;
  issueTitle: string;
  threadId: string | null;
  status: "pending" | "creating" | "streaming" | "done" | "error";
}

export interface AutopilotJob {
  id: string;
  repoId: string;
  repoName: string;
  config: AutopilotConfig;
  issues: IssueDto[];
  total: number;
  created: number;
  status: AutopilotJobStatus;
  startedAt: string;
  finishedAt: string | null;
  threads: AutopilotThreadResult[];
}

const cancelTokens: Record<string, { cancelled: boolean }> = {};
const agentWatchers: Record<string, () => void> = {};
const threadWatchers: Record<string, () => void> = {};

function dbLog(
  jobId: string,
  event: string,
  extra: {
    threadRowId?: string;
    modelId?: string;
    repoName?: string;
    issueId?: string;
    issueNumber?: number;
    detail?: string;
  } = {},
  repoName = "",
) {
  invoke("autopilot_write_log", {
    input: {
      job_id: jobId,
      thread_row_id: extra.threadRowId ?? null,
      event,
      model_id: extra.modelId ?? null,
      repo_name: extra.repoName ?? repoName,
      issue_id: extra.issueId ?? null,
      issue_number: extra.issueNumber ?? null,
      detail: extra.detail ?? null,
    },
  }).catch(() => {});
}

function watchThread(
  jobId: string,
  threadRowId: string,
  threadId: string,
  repoName: string,
  _get: () => AutopilotState,
  set: (fn: (s: AutopilotState) => Partial<AutopilotState>) => void,
) {
  const key = `${jobId}:${threadId}`;
  const unsubscribe = useAgentsStore.subscribe((state) => {
    if (!state.streamingThreadIds[threadId]) {
      unsubscribe();
      delete threadWatchers[key];
      set((s) => ({
        jobs: {
          ...s.jobs,
          [jobId]: {
            ...s.jobs[jobId],
            threads: s.jobs[jobId]?.threads.map((t) =>
              t.threadId === threadId && t.status === "streaming" ? { ...t, status: "done" } : t,
            ) ?? [],
          },
        },
      }));
      invoke("autopilot_update_thread", { input: { id: threadRowId, thread_id: threadId, status: "done" } }).catch(() => {});
      dbLog(jobId, "streaming_done", { threadRowId, repoName });
    }
  });
  threadWatchers[key] = unsubscribe;

  const { streamingThreadIds } = useAgentsStore.getState();
  if (!streamingThreadIds[threadId]) {
    unsubscribe();
    delete threadWatchers[key];
    set((s) => ({
      jobs: {
        ...s.jobs,
        [jobId]: {
          ...s.jobs[jobId],
          threads: s.jobs[jobId]?.threads.map((t) =>
            t.threadId === threadId && t.status === "streaming" ? { ...t, status: "done" } : t,
          ) ?? [],
        },
      },
    }));
    invoke("autopilot_update_thread", { input: { id: threadRowId, thread_id: threadId, status: "done" } }).catch(() => {});
    dbLog(jobId, "streaming_done", { threadRowId, repoName });
  }
}

function filterIssues(issues: IssueDto[], filter: AutopilotFilter, assignedToLogin: string | null): IssueDto[] {
  switch (filter) {
    case "unassigned":
      return issues.filter((i) => i.assignees.length === 0);
    case "no_pr":
      return issues.filter((i) => i.linkedPrNumbers.length === 0);
    case "assigned_to_me":
      if (!assignedToLogin) return issues;
      return issues.filter((i) =>
        i.assignees.some((a) => a.toLowerCase() === assignedToLogin.toLowerCase()),
      );
    default:
      return issues;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function watchAgentsAndFinalize(
  jobId: string,
  threadIds: string[],
  get: () => AutopilotState,
  set: (fn: (s: AutopilotState) => Partial<AutopilotState>) => void,
) {
  if (threadIds.length === 0) {
    finalizeJob(jobId, false, get, set);
    return;
  }

  const unsubscribe = useAgentsStore.subscribe((state) => {
    const stillStreaming = threadIds.some((id) => state.streamingThreadIds[id]);
    if (!stillStreaming) {
      unsubscribe();
      delete agentWatchers[jobId];
      finalizeJob(jobId, false, get, set);
    }
  });

  agentWatchers[jobId] = unsubscribe;

  const { streamingThreadIds } = useAgentsStore.getState();
  const stillStreaming = threadIds.some((id) => streamingThreadIds[id]);
  if (!stillStreaming) {
    unsubscribe();
    delete agentWatchers[jobId];
    finalizeJob(jobId, false, get, set);
  }
}

function finalizeJob(
  jobId: string,
  stopped: boolean,
  get: () => AutopilotState,
  set: (fn: (s: AutopilotState) => Partial<AutopilotState>) => void,
) {
  const job = get().jobs[jobId];
  if (!job) return;

  const status = stopped ? "stopped" : "done";
  const finishedAt = new Date().toISOString();

  set((s) => ({
    jobs: {
      ...s.jobs,
      [jobId]: { ...s.jobs[jobId], status, finishedAt },
    },
  }));

  invoke("autopilot_update_job", {
    input: { id: jobId, created: job.created, status, finished_at: finishedAt },
  }).catch(() => {});

  dbLog(jobId, stopped ? "job_stopped" : "job_done", { repoName: job.repoName, detail: `${job.created}/${job.total}` });

  if (stopped) {
    toast.info(`Autopilot stopped — ${job.created} / ${job.total} threads created`);
  } else {
    toast.success(`Autopilot complete — ${job.created} threads created in ${job.repoName}`);
  }
}

async function runJob(
  jobId: string,
  issues: IssueDto[],
  get: () => AutopilotState,
  set: (fn: (s: AutopilotState) => Partial<AutopilotState>) => void,
) {
  const token = cancelTokens[jobId];
  const createdThreadIds: string[] = [];

  for (let i = 0; i < issues.length; i++) {
    if (token?.cancelled) break;

    const issue = issues[i];
    const job = get().jobs[jobId];
    if (!job) break;

    const { config } = job;
    const { addThread, sendMessage, aiProviders, getEffectiveModelId } = useAgentsStore.getState();
    const threadRowId = `${jobId}:${issue.id}`;

    set((s) => ({
      jobs: {
        ...s.jobs,
        [jobId]: {
          ...s.jobs[jobId],
          threads: s.jobs[jobId].threads.map((t) =>
            t.issueId === issue.id ? { ...t, status: "creating" } : t,
          ),
        },
      },
    }));

    invoke("autopilot_update_thread", { input: { id: threadRowId, thread_id: null, status: "creating" } }).catch(() => {});

    try {
      const thread = await invoke<{ id: string; title: string; workspace_path: string }>(
        "create_thread_with_title",
        { repoId: job.repoId, title: issue.title },
      );

      addThread(job.repoId, thread);
      dbLog(jobId, "thread_created", { threadRowId, repoName: job.repoName, issueId: issue.id, issueNumber: issue.number });

      if (config.autoSend) {
        let modelId: string | null = null;

        if (config.modelMode === "current") {
          modelId = getEffectiveModelId(job.repoId, "");
        } else if (config.modelMode === "single") {
          modelId = config.modelId;
        } else {
          const allModels = aiProviders.flatMap((p) => p.models);
          if (allModels.length > 0) {
            modelId = allModels[Math.floor(Math.random() * allModels.length)].id;
          }
        }

        if (modelId) {
          const message = `Implement the following issue:\n\n**${issue.title}**\n\n${issue.body ?? ""}`;
          await sendMessage(thread.id, message, modelId, false);
          createdThreadIds.push(thread.id);

          set((s) => ({
            jobs: {
              ...s.jobs,
              [jobId]: {
                ...s.jobs[jobId],
                created: s.jobs[jobId].created + 1,
                threads: s.jobs[jobId].threads.map((t) =>
                  t.issueId === issue.id ? { ...t, threadId: thread.id, status: "streaming" } : t,
                ),
              },
            },
          }));

          invoke("autopilot_update_thread", { input: { id: threadRowId, thread_id: thread.id, status: "streaming" } }).catch(() => {});
          invoke("autopilot_update_job", { input: { id: jobId, created: get().jobs[jobId]?.created ?? 0, status: "running", finished_at: null } }).catch(() => {});
          dbLog(jobId, "streaming_started", { threadRowId, modelId, repoName: job.repoName, issueId: issue.id, issueNumber: issue.number });

          watchThread(jobId, threadRowId, thread.id, job.repoName, get, set);
        } else {
          set((s) => ({
            jobs: {
              ...s.jobs,
              [jobId]: {
                ...s.jobs[jobId],
                created: s.jobs[jobId].created + 1,
                threads: s.jobs[jobId].threads.map((t) =>
                  t.issueId === issue.id ? { ...t, threadId: thread.id, status: "done" } : t,
                ),
              },
            },
          }));
          invoke("autopilot_update_thread", { input: { id: threadRowId, thread_id: thread.id, status: "done" } }).catch(() => {});
          invoke("autopilot_update_job", { input: { id: jobId, created: get().jobs[jobId]?.created ?? 0, status: "running", finished_at: null } }).catch(() => {});
        }
      } else {
        set((s) => ({
          jobs: {
            ...s.jobs,
            [jobId]: {
              ...s.jobs[jobId],
              created: s.jobs[jobId].created + 1,
              threads: s.jobs[jobId].threads.map((t) =>
                t.issueId === issue.id ? { ...t, threadId: thread.id, status: "done" } : t,
              ),
            },
          },
        }));
        invoke("autopilot_update_thread", { input: { id: threadRowId, thread_id: thread.id, status: "done" } }).catch(() => {});
        invoke("autopilot_update_job", { input: { id: jobId, created: get().jobs[jobId]?.created ?? 0, status: "running", finished_at: null } }).catch(() => {});
      }
    } catch (e) {
      set((s) => ({
        jobs: {
          ...s.jobs,
          [jobId]: {
            ...s.jobs[jobId],
            threads: s.jobs[jobId].threads.map((t) =>
              t.issueId === issue.id ? { ...t, status: "error" } : t,
            ),
          },
        },
      }));
      invoke("autopilot_update_thread", { input: { id: threadRowId, thread_id: null, status: "error" } }).catch(() => {});
      dbLog(jobId, "thread_error", { threadRowId, repoName: job.repoName, issueId: issue.id, issueNumber: issue.number, detail: String(e) });
    }

    const isLastInBatch = (i + 1) % config.batchSize === 0;
    const isLast = i === issues.length - 1;

    if (isLastInBatch && !isLast && !token?.cancelled) {
      await sleep(config.delayMs);
    }
  }

  const stopped = token?.cancelled === true;
  delete cancelTokens[jobId];

  if (stopped) {
    finalizeJob(jobId, true, get, set);
    return;
  }

  const job = get().jobs[jobId];
  if (!job) return;

  if (createdThreadIds.length === 0 || !job.config.autoSend) {
    finalizeJob(jobId, false, get, set);
    return;
  }

  set((s) => ({
    jobs: {
      ...s.jobs,
      [jobId]: { ...s.jobs[jobId], status: "waiting" },
    },
  }));

  watchAgentsAndFinalize(jobId, createdThreadIds, get, set);
}

function cleanupJobTracking(job: AutopilotJob, abortActiveThreads: boolean) {
  const { abortThread } = useAgentsStore.getState();

  if (cancelTokens[job.id]) {
    cancelTokens[job.id].cancelled = true;
    delete cancelTokens[job.id];
  }

  if (agentWatchers[job.id]) {
    agentWatchers[job.id]();
    delete agentWatchers[job.id];
  }

  for (const thread of job.threads) {
    if (!thread.threadId) continue;

    const key = `${job.id}:${thread.threadId}`;
    if (threadWatchers[key]) {
      threadWatchers[key]();
      delete threadWatchers[key];
    }

    if (abortActiveThreads && (thread.status === "creating" || thread.status === "streaming")) {
      void abortThread(thread.threadId);
    }
  }
}

function deriveJobState(threads: AutopilotThreadResult[]): Pick<AutopilotJob, "total" | "created" | "status" | "finishedAt"> {
  const total = threads.length;
  const created = threads.filter((thread) => thread.threadId !== null).length;
  const hasCreating = threads.some((thread) => thread.status === "creating");
  const hasStreaming = threads.some((thread) => thread.status === "streaming");
  const hasPending = threads.some((thread) => thread.status === "pending");
  const hasOnlyErrors = threads.length > 0 && threads.every((thread) => thread.status === "error");

  const status: AutopilotJobStatus = hasCreating
    ? "running"
    : hasStreaming
      ? "waiting"
      : hasPending
        ? "stopped"
        : hasOnlyErrors
          ? "error"
          : "done";

  return {
    total,
    created,
    status,
    finishedAt: status === "running" || status === "waiting" ? null : new Date().toISOString(),
  };
}

interface AutopilotState {
  jobs: Record<string, AutopilotJob>;
  selectedJobId: string | null;
  selectJob: (id: string | null) => void;
  loadJobs: () => Promise<void>;
  startJob: (repoId: string, repoName: string, issues: IssueDto[], config: AutopilotConfig) => void;
  resumeJob: (jobId: string) => void;
  cancelJob: (jobId: string) => void;
  startThread: (jobId: string, issueId: string) => Promise<void>;
  cancelThread: (jobId: string, issueId: string) => void;
  removeJob: (jobId: string, options?: { removeThreads?: boolean }) => Promise<void>;
  removeThreadReference: (threadId: string) => void;
  clearCompleted: () => void;
}

interface DbJobDto {
  id: string;
  repo_id: string;
  repo_name: string;
  config: string;
  issues: string;
  total: number;
  created: number;
  status: string;
  started_at: string;
  finished_at: string | null;
  threads: DbThreadDto[];
}

interface DbThreadDto {
  id: string;
  job_id: string;
  issue_id: string;
  issue_number: number;
  issue_title: string;
  thread_id: string | null;
  status: string;
  sort_order: number;
}

function dbJobToStore(dbJob: DbJobDto): AutopilotJob {
  const status = (dbJob.status === "running" || dbJob.status === "waiting")
    ? "stopped" as const
    : dbJob.status as AutopilotJobStatus;

  return {
    id: dbJob.id,
    repoId: dbJob.repo_id,
    repoName: dbJob.repo_name,
    config: JSON.parse(dbJob.config) as AutopilotConfig,
    issues: JSON.parse(dbJob.issues) as IssueDto[],
    total: dbJob.total,
    created: dbJob.created,
    status,
    startedAt: dbJob.started_at,
    finishedAt: dbJob.finished_at ?? (status === "stopped" ? new Date().toISOString() : null),
    threads: dbJob.threads.map((t) => ({
      rowId: t.id,
      issueId: t.issue_id,
      issueNumber: t.issue_number,
      issueTitle: t.issue_title,
      threadId: t.thread_id,
      status: (t.status === "creating" || t.status === "streaming") ? "pending" as const : t.status as AutopilotThreadResult["status"],
    })),
  };
}

export const useAutopilotStore = create<AutopilotState>((set, get) => ({
  jobs: {},
  selectedJobId: null,

  selectJob: (id) => set({ selectedJobId: id }),

  loadJobs: async () => {
    try {
      const dbJobs = await invoke<DbJobDto[]>("autopilot_list_jobs");
      const jobs = Object.fromEntries(dbJobs.map((j) => [j.id, dbJobToStore(j)]));
      set({ jobs });
    } catch {
      // DB not ready yet or first run — start empty
    }
  },

  startJob: (repoId, repoName, issues, config) => {
    const filtered = filterIssues(issues, config.filter, config.assignedToLogin);

    if (filtered.length === 0) {
      toast.info("No issues match the selected filter.");
      return;
    }

    const jobId = `${repoId}-${Date.now()}`;
    const token = { cancelled: false };
    cancelTokens[jobId] = token;

    const threads: AutopilotThreadResult[] = filtered.map((issue) => ({
      rowId: `${jobId}:${issue.id}`,
      issueId: issue.id,
      issueNumber: issue.number,
      issueTitle: issue.title,
      threadId: null,
      status: "pending",
    }));

    const job: AutopilotJob = {
      id: jobId,
      repoId,
      repoName,
      config,
      issues: filtered,
      total: filtered.length,
      created: 0,
      status: "running",
      startedAt: new Date().toISOString(),
      finishedAt: null,
      threads,
    };

    set((s) => ({ jobs: { ...s.jobs, [jobId]: job } }));

    // Persist to SQLite
    invoke("autopilot_save_job", {
      input: {
        id: jobId,
        repo_id: repoId,
        repo_name: repoName,
        config: JSON.stringify(config),
        issues: JSON.stringify(filtered),
        total: filtered.length,
        started_at: job.startedAt,
      },
    }).catch(() => {});

    for (let i = 0; i < threads.length; i++) {
      const t = threads[i];
      invoke("autopilot_save_thread", {
        input: {
          id: t.rowId,
          job_id: jobId,
          issue_id: t.issueId,
          issue_number: t.issueNumber,
          issue_title: t.issueTitle,
          sort_order: i,
        },
      }).catch(() => {});
    }

    dbLog(jobId, "job_started", { repoName, detail: `${filtered.length} issues` });

    runJob(jobId, filtered, get, set);
  },

  resumeJob: (jobId) => {
    const job = get().jobs[jobId];
    if (!job || job.status !== "stopped") return;

    const pendingIssueIds = new Set(
      job.threads.filter((t) => t.status === "pending").map((t) => t.issueId),
    );
    const remainingIssues = job.issues.filter((i) => pendingIssueIds.has(i.id));

    if (remainingIssues.length === 0) return;

    const token = { cancelled: false };
    cancelTokens[jobId] = token;

    set((s) => ({
      jobs: {
        ...s.jobs,
        [jobId]: { ...s.jobs[jobId], status: "running", finishedAt: null },
      },
    }));

    invoke("autopilot_update_job", { input: { id: jobId, created: job.created, status: "running", finished_at: null } }).catch(() => {});
    dbLog(jobId, "job_resumed", { repoName: job.repoName, detail: `${remainingIssues.length} remaining` });

    runJob(jobId, remainingIssues, get, set);
  },

  cancelJob: (jobId) => {
    const job = get().jobs[jobId];
    if (!job || job.status === "stopping" || job.status === "stopped") return;

    set((s) => ({
      jobs: {
        ...s.jobs,
        [jobId]: {
          ...s.jobs[jobId],
          status: "stopping",
          finishedAt: null,
        },
      },
    }));
    invoke("autopilot_update_job", { input: { id: jobId, created: job.created, status: "stopping", finished_at: null, issues: null, total: null } }).catch(() => {});

    if (cancelTokens[jobId]) {
      cancelTokens[jobId].cancelled = true;
    }

    const { abortThread } = useAgentsStore.getState();

    for (const thread of job.threads) {
      if (thread.threadId && (thread.status === "streaming" || thread.status === "creating")) {
        void abortThread(thread.threadId);
        const key = `${jobId}:${thread.threadId}`;
        if (threadWatchers[key]) {
          threadWatchers[key]();
          delete threadWatchers[key];
        }
      }
    }

    if (agentWatchers[jobId]) {
      agentWatchers[jobId]();
      delete agentWatchers[jobId];
      finalizeJob(jobId, true, get, set);
    }
  },

  startThread: async (jobId, issueId) => {
    const job = get().jobs[jobId];
    if (!job) return;

    const issue = job.issues.find((i) => i.id === issueId);
    if (!issue) return;

    const thread = job.threads.find((t) => t.issueId === issueId);
    if (!thread || thread.status !== "pending") return;

    const threadRowId = `${jobId}:${issueId}`;
    const { addThread, sendMessage, aiProviders, getEffectiveModelId } = useAgentsStore.getState();

    set((s) => ({
      jobs: {
        ...s.jobs,
        [jobId]: {
          ...s.jobs[jobId],
          status: "running",
          finishedAt: null,
          threads: s.jobs[jobId].threads.map((t) =>
            t.issueId === issueId ? { ...t, status: "creating" } : t,
          ),
        },
      },
    }));
    invoke("autopilot_update_job", { input: { id: jobId, created: job.created, status: "running", finished_at: null } }).catch(() => {});
    invoke("autopilot_update_thread", { input: { id: threadRowId, thread_id: null, status: "creating" } }).catch(() => {});

    try {
      const agentThread = await invoke<{ id: string; title: string; workspace_path: string }>(
        "create_thread_with_title",
        { repoId: job.repoId, title: issue.title },
      );

      addThread(job.repoId, agentThread);

      const { config } = job;
      let modelId: string | null = null;

      if (config.modelMode === "current") {
        modelId = getEffectiveModelId(job.repoId, "");
      } else if (config.modelMode === "single") {
        modelId = config.modelId;
      } else {
        const allModels = aiProviders.flatMap((p) => p.models);
        if (allModels.length > 0) {
          modelId = allModels[Math.floor(Math.random() * allModels.length)].id;
        }
      }

      if (modelId && config.autoSend) {
        const message = `Implement the following issue:\n\n**${issue.title}**\n\n${issue.body ?? ""}`;
        await sendMessage(agentThread.id, message, modelId, false);

        set((s) => ({
          jobs: {
            ...s.jobs,
            [jobId]: {
              ...s.jobs[jobId],
              created: s.jobs[jobId].created + 1,
              threads: s.jobs[jobId].threads.map((t) =>
                t.issueId === issueId ? { ...t, threadId: agentThread.id, status: "streaming" } : t,
              ),
            },
          },
        }));
        invoke("autopilot_update_thread", { input: { id: threadRowId, thread_id: agentThread.id, status: "streaming" } }).catch(() => {});
        invoke("autopilot_update_job", { input: { id: jobId, created: get().jobs[jobId]?.created ?? 0, status: "running", finished_at: null } }).catch(() => {});
        watchThread(jobId, threadRowId, agentThread.id, job.repoName, get, set);
      } else {
        set((s) => ({
          jobs: {
            ...s.jobs,
            [jobId]: {
              ...s.jobs[jobId],
              created: s.jobs[jobId].created + 1,
              threads: s.jobs[jobId].threads.map((t) =>
                t.issueId === issueId ? { ...t, threadId: agentThread.id, status: "done" } : t,
              ),
            },
          },
        }));
        invoke("autopilot_update_thread", { input: { id: threadRowId, thread_id: agentThread.id, status: "done" } }).catch(() => {});

        const nextJob = get().jobs[jobId];
        if (!nextJob) return;

        const hasPending = nextJob.threads.some((t) => t.status === "pending");
        if (hasPending) {
          const finishedAt = new Date().toISOString();
          set((s) => ({
            jobs: {
              ...s.jobs,
              [jobId]: { ...s.jobs[jobId], status: "stopped", finishedAt },
            },
          }));
          invoke("autopilot_update_job", { input: { id: jobId, created: nextJob.created, status: "stopped", finished_at: finishedAt } }).catch(() => {});
        } else {
          finalizeJob(jobId, false, get, set);
        }
      }
    } catch (e) {
      set((s) => ({
        jobs: {
          ...s.jobs,
          [jobId]: {
            ...s.jobs[jobId],
            threads: s.jobs[jobId].threads.map((t) =>
              t.issueId === issueId ? { ...t, status: "error" } : t,
            ),
          },
        },
      }));
      invoke("autopilot_update_thread", { input: { id: threadRowId, thread_id: null, status: "error" } }).catch(() => {});
    }
  },

  cancelThread: (jobId, issueId) => {
    const job = get().jobs[jobId];
    if (!job) return;

    const thread = job.threads.find((t) => t.issueId === issueId);
    if (!thread || !thread.threadId) return;

    void useAgentsStore.getState().abortThread(thread.threadId);

    const key = `${jobId}:${thread.threadId}`;
    if (threadWatchers[key]) {
      threadWatchers[key]();
      delete threadWatchers[key];
    }

    const threadRowId = `${jobId}:${issueId}`;
    const nextCreated = Math.max(0, job.created - 1);
    const remainingActive = job.threads.some((t) =>
      t.issueId !== issueId && (t.status === "creating" || t.status === "streaming"),
    );
    const nextStatus = remainingActive ? job.status : "stopped";
    const finishedAt = remainingActive ? null : new Date().toISOString();

    set((s) => ({
      jobs: {
        ...s.jobs,
        [jobId]: {
          ...s.jobs[jobId],
          created: nextCreated,
          status: nextStatus,
          finishedAt,
          threads: s.jobs[jobId].threads.map((t) =>
            t.issueId === issueId ? { ...t, threadId: null, status: "pending" } : t,
          ),
        },
      },
    }));
    invoke("autopilot_update_job", { input: { id: jobId, created: nextCreated, status: nextStatus, finished_at: finishedAt } }).catch(() => {});
    invoke("autopilot_update_thread", { input: { id: threadRowId, thread_id: null, status: "pending" } }).catch(() => {});
  },

  removeJob: async (jobId, options) => {
    const job = get().jobs[jobId];
    if (!job) return;

    const removeThreads = options?.removeThreads === true;
    cleanupJobTracking(job, removeThreads);

    invoke("autopilot_delete_job", { jobId }).catch(() => {});

    set((s) => {
      const next = { ...s.jobs };
      delete next[jobId];
      return { jobs: next, selectedJobId: s.selectedJobId === jobId ? null : s.selectedJobId };
    });

    if (!removeThreads) return;

    const { removeThread, abortThread } = useAgentsStore.getState();
    const threadIds = job.threads
      .filter((thread) => thread.threadId)
      .map((thread) => ({ id: thread.threadId!, status: thread.status }));

    for (const thread of threadIds) {
      if (thread.status === "creating" || thread.status === "streaming") {
        void abortThread(thread.id);
      }

      removeThread(job.repoId, thread.id);
    }

    await Promise.all(
      threadIds.map(async (thread) => {
        await invoke("delete_thread", { threadId: thread.id }).catch(() => {});
      }),
    );
  },

  removeThreadReference: (threadId) => {
    const jobs = get().jobs;
    const nextJobs = { ...jobs };
    const removedJobs: AutopilotJob[] = [];

    for (const job of Object.values(jobs)) {
      const removedThread = job.threads.find((thread) => thread.threadId === threadId);
      if (!removedThread) continue;

      const threadWatcherKey = `${job.id}:${threadId}`;
      if (threadWatchers[threadWatcherKey]) {
        threadWatchers[threadWatcherKey]();
        delete threadWatchers[threadWatcherKey];
      }

      const nextThreads = job.threads.filter((thread) => thread.threadId !== threadId);
      const nextIssues = job.issues.filter((issue) => issue.id !== removedThread.issueId);

      if (nextThreads.length === 0) {
        removedJobs.push(job);
        delete nextJobs[job.id];
        invoke("autopilot_delete_job", { jobId: job.id }).catch(() => {});
        continue;
      }

      const nextState = deriveJobState(nextThreads);
      nextJobs[job.id] = {
        ...job,
        issues: nextIssues,
        threads: nextThreads,
        ...nextState,
      };

      invoke("autopilot_delete_thread", { input: { thread_row_id: removedThread.rowId } }).catch(() => {});
      invoke("autopilot_update_job", {
        input: {
          id: job.id,
          created: nextState.created,
          status: nextState.status,
          finished_at: nextState.finishedAt,
          issues: JSON.stringify(nextIssues),
          total: nextState.total,
        },
      }).catch(() => {});
    }

    for (const job of removedJobs) {
      cleanupJobTracking(job, false);
    }

    set((state) => ({
      jobs: nextJobs,
      selectedJobId: state.selectedJobId && !nextJobs[state.selectedJobId] ? null : state.selectedJobId,
    }));
  },

  clearCompleted: () => {
    const { jobs } = get();
    for (const [id, job] of Object.entries(jobs)) {
      if (job.status !== "running" && job.status !== "waiting") {
        invoke("autopilot_delete_job", { jobId: id }).catch(() => {});
      }
    }
    set((s) => ({
      jobs: Object.fromEntries(
        Object.entries(s.jobs).filter(([, job]) => job.status === "running" || job.status === "waiting"),
      ),
    }));
  },
}));
