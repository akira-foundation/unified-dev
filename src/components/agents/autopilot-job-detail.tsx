import { useState } from "react";
import { Square, CheckCircle2, XCircle, Rocket, Clock, ExternalLink, CircleDot, Loader2, Play, Trash2 } from "lucide-react";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { AutopilotRemoveDialog } from "@/components/agents/autopilot-remove-dialog";
import { RemoveThreadDialog } from "@/components/agents/remove-thread-dialog";
import { cn } from "@/lib/utils";
import { getAutopilotCompletedCount, useAutopilotStore, type AutopilotThreadResult } from "@/stores/useAutopilotStore";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useI18n } from "@/i18n/i18n";
import { toast } from "sonner";
import { invoke } from "@tauri-apps/api/core";

interface AutopilotJobDetailProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

function statusIcon(status: AutopilotThreadResult["status"]) {
  switch (status) {
    case "done":
      return <CheckCircle2 className="h-3.5 w-3.5 shrink-0 text-green-500" />;
    case "error":
      return <XCircle className="h-3.5 w-3.5 shrink-0 text-red-500" />;
    case "idle":
      return <CircleDot className="h-3.5 w-3.5 shrink-0 text-zinc-400" />;
    case "creating":
      return <CircleDot className="h-3.5 w-3.5 shrink-0 text-purple-500 animate-pulse" />;
    case "streaming":
      return <Loader2 className="h-3.5 w-3.5 shrink-0 text-purple-500 animate-spin" />;
    default:
      return <div className="h-3.5 w-3.5 shrink-0 rounded-full border border-zinc-300 dark:border-zinc-600" />;
  }
}

function ThreadActionButton({
  thread,
  jobId,
  onStart,
  onStop,
}: {
  thread: AutopilotThreadResult;
  jobId: string;
  onStart: (jobId: string, issueId: string) => void;
  onStop: (jobId: string, issueId: string) => void;
}) {
  if (thread.status === "pending") {
    return (
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); onStart(jobId, thread.issueId); }}
        className="flex h-6 w-6 shrink-0 items-center justify-center rounded-md border border-zinc-200 bg-zinc-100 text-zinc-500 transition-colors hover:border-purple-500 hover:bg-purple-500/10 hover:text-purple-500 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300"
        title="Start this thread"
      >
        <Play className="h-3 w-3 fill-current" />
      </button>
    );
  }

  if (thread.status === "streaming") {
    return (
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); onStop(jobId, thread.issueId); }}
        className="flex h-6 w-6 shrink-0 items-center justify-center rounded-md border border-purple-500/30 bg-purple-500/10 text-purple-500 transition-colors hover:bg-purple-500/20"
        title="Stop this thread"
      >
        <Square className="h-3 w-3 fill-current" />
      </button>
    );
  }

  if (thread.status === "creating") {
    return (
      <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-md border border-purple-500/20 bg-purple-500/10 text-purple-500">
        <Loader2 className="h-3 w-3 animate-spin" />
      </div>
    );
  }

  return statusIcon(thread.status);
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function formatDuration(startIso: string, endIso: string | null): string {
  const end = endIso ? new Date(endIso) : new Date();
  const diffMs = end.getTime() - new Date(startIso).getTime();
  const secs = Math.floor(diffMs / 1000);
  if (secs < 60) return `${secs}s`;
  const mins = Math.floor(secs / 60);
  return `${mins}m ${secs % 60}s`;
}

export function AutopilotJobDetail({ open, onOpenChange }: AutopilotJobDetailProps) {
  const { t } = useI18n();
  const { jobs, selectedJobId, selectJob, cancelJob, resumeJob, startThread, cancelThread, removeJob, removeThreadReference } = useAutopilotStore();
  const { setSelectedIssueId, getEffectiveModelId, removeThread, loadRepositories, prUrlByThread, streamingThreadIds } = useAgentsStore();
  const aiProviders = useAgentsStore((s) => s.aiProviders);
  const [removeOpen, setRemoveOpen] = useState(false);
  const [threadToRemove, setThreadToRemove] = useState<AutopilotThreadResult | null>(null);
  const [isRemovingThread, setIsRemovingThread] = useState(false);

  const job = selectedJobId ? jobs[selectedJobId] : null;

  const allModels = aiProviders.flatMap((p) => p.models);

  function resolveModelLabel(modelId: string | null): string | null {
    if (!modelId) return null;
    return allModels.find((m) => m.id === modelId)?.label ?? modelId;
  }

  function modelConfigLabel(): string {
    if (job!.config.modelMode === "single") {
      return resolveModelLabel(job!.config.modelId) ?? t("autopilot.modelMode.single");
    }
    if (job!.config.modelMode === "current") {
      return resolveModelLabel(getEffectiveModelId(job!.repoId, "")) ?? t("autopilot.modelMode.current");
    }
    return t("autopilot.modelMode.random");
  }

  if (!job) return null;

  const completed = getAutopilotCompletedCount(job.threads, prUrlByThread, streamingThreadIds);
  const pct = job.total > 0 ? Math.round((completed / job.total) * 100) : 0;
  const currentBatch = Math.ceil(job.created / job.config.batchSize);
  const totalBatches = Math.ceil(job.total / job.config.batchSize);

  function handleClose() {
    selectJob(null);
    onOpenChange(false);
  }

  function handleGoToThread(threadId: string) {
    setSelectedIssueId(threadId);
    handleClose();
  }

  async function handleRemoveThread() {
    if (!threadToRemove?.threadId) return;

    const toastId = toast.loading(t("agents.sidebar.toast.removingThread"));
    const repoId = job!.repoId;

    try {
      setIsRemovingThread(true);
      await invoke("delete_thread", { threadId: threadToRemove.threadId });
      removeThread(repoId, threadToRemove.threadId);
      removeThreadReference(threadToRemove.threadId);
      await loadRepositories();
      toast.success(t("agents.sidebar.toast.threadRemoved"), { id: toastId });
      setThreadToRemove(null);
    } catch (error) {
      toast.error(String(error), { id: toastId });
    } finally {
      setIsRemovingThread(false);
    }
  }

  return (
    <Sheet open={open} onOpenChange={(v) => { if (!v) handleClose(); }}>
      <SheetContent side="left" className="w-[440px] flex flex-col p-0">
        {/* Header */}
        <SheetHeader className="px-5 pt-5 pb-4 border-b border-border shrink-0 space-y-3 pr-12">
          <div className="flex items-center gap-2">
            {job.status === "stopping"
              ? <Loader2 className="h-4 w-4 shrink-0 animate-spin text-red-500" />
              : <Rocket className={cn("h-4 w-4 shrink-0", (job.status === "running" || job.status === "waiting") ? "text-purple-500" : "text-muted-foreground")} />}
            <SheetTitle className="text-base leading-tight truncate flex-1">
              {job.repoName}
            </SheetTitle>
            {(job.status === "running" || job.status === "waiting") && (
              <Button
                size="sm"
                variant="destructive"
                className="h-7 gap-1.5 text-xs shrink-0"
                onClick={() => cancelJob(job.id)}
              >
                <Square className="h-3 w-3 fill-current" />
                {t("autopilot.detail.stop")}
              </Button>
            )}
            {job.status === "stopping" && (
              <Button
                size="sm"
                variant="destructive"
                disabled
                className="h-7 gap-1.5 text-xs shrink-0 opacity-100"
              >
                <Loader2 className="h-3 w-3 animate-spin" />
                {t("autopilot.detail.stopping")}
              </Button>
            )}
            {job.status === "stopped" && (
              <Button
                size="sm"
                variant="ghost"
                className="h-7 gap-1.5 text-xs shrink-0 text-purple-500 hover:text-purple-600 hover:bg-purple-500/10"
                onClick={() => resumeJob(job.id)}
              >
                <Play className="h-3 w-3 fill-current" />
                {t("autopilot.panel.resume")}
              </Button>
            )}
            {job.status !== "running" && job.status !== "waiting" && (
              <Button
                size="sm"
                variant="ghost"
                className="h-7 text-xs shrink-0 text-muted-foreground hover:text-red-500 hover:bg-red-500/10"
                onClick={() => setRemoveOpen(true)}
              >
                {t("autopilot.panel.remove")}
              </Button>
            )}
          </div>

          {/* Progress bar */}
          <div className="space-y-1.5">
            <div className="h-2 w-full rounded-full bg-zinc-200 dark:bg-zinc-800 overflow-hidden">
              <div
                className={cn(
                  "h-full rounded-full transition-all duration-500",
                  job.status === "done" ? "bg-green-500" : job.status === "stopped" ? "bg-yellow-500" : job.status === "stopping" ? "bg-red-500" : "bg-purple-500",
                )}
                style={{ width: `${pct}%` }}
              />
            </div>
            <div className="flex items-center justify-between text-[11px] text-muted-foreground">
              <span>
                {job.status === "running"
                  ? t("autopilot.detail.progress")
                      .replace("{created}", String(completed))
                      .replace("{total}", String(job.total))
                  : job.status === "waiting"
                    ? t("autopilot.detail.waiting").replace("{total}", String(job.total))
                  : job.status === "stopping"
                    ? t("autopilot.detail.stopping")
                  : job.status === "done"
                    ? t("autopilot.detail.done").replace("{total}", String(job.total))
                    : t("autopilot.detail.stopped")
                        .replace("{created}", String(job.created))
                        .replace("{total}", String(job.total))}
              </span>
              <span>{pct}%</span>
            </div>
            {job.status === "running" && (
              <p className="text-[11px] text-muted-foreground">
                {t("autopilot.detail.batch")
                  .replace("{current}", String(currentBatch))
                  .replace("{total}", String(totalBatches))}
              </p>
            )}
          </div>
        </SheetHeader>

        {/* Config summary */}
        <div className="px-5 py-3 border-b border-border shrink-0">
          <p className="text-[10px] font-semibold uppercase tracking-widest text-muted-foreground mb-2">
            {t("autopilot.detail.config")}
          </p>
          <div className="flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-muted-foreground">
            <span>{t("autopilot.detail.configFilter")}: <strong className="text-foreground">{t(`autopilot.filter.${job.config.filter}`)}</strong></span>
            <span>{t("autopilot.detail.configBatch")}: <strong className="text-foreground">{job.config.batchSize === 999999 ? t("autopilot.dialog.batchAll") : job.config.batchSize}</strong></span>
            <span>{t("autopilot.detail.configDelay")}: <strong className="text-foreground">{job.config.delayMs / 1000}s</strong></span>
            <span>{t("autopilot.detail.configModel")}: <strong className="text-foreground">{modelConfigLabel()}</strong></span>
            <div className="flex items-center gap-1">
              <Clock className="h-3 w-3" />
              <span>{formatTime(job.startedAt)}</span>
              {job.finishedAt && <span>· {formatDuration(job.startedAt, job.finishedAt)}</span>}
            </div>
          </div>
        </div>

        {/* Thread list */}
        <div className="flex-1 overflow-y-auto">
          <div className="p-3 space-y-0.5">
            {job.threads.map((thread) => (
              <div
                key={thread.issueId}
                className={cn(
                  "group flex items-center gap-2.5 rounded-lg border border-transparent px-2.5 py-2 text-sm transition-colors",
                  (thread.status === "creating" || thread.status === "streaming") && "border-purple-500/10 bg-purple-500/5",
                  thread.threadId && "cursor-pointer hover:bg-accent",
                )}
                onClick={() => thread.threadId && handleGoToThread(thread.threadId)}
              >
                <ThreadActionButton
                  thread={thread}
                  jobId={job.id}
                  onStart={startThread}
                  onStop={cancelThread}
                />
                <span className={cn(
                  "flex-1 truncate text-[12px]",
                  thread.status === "pending" || thread.status === "idle" ? "text-muted-foreground" : thread.status === "error" ? "text-red-400" : "text-foreground",
                )}>
                  #{thread.issueNumber} {thread.issueTitle}
                </span>
                {thread.threadId && (
                  <button
                    type="button"
                    className="opacity-0 transition-opacity group-hover:opacity-100 text-muted-foreground hover:text-red-500"
                    onClick={(e) => {
                      e.stopPropagation();
                      setThreadToRemove(thread);
                    }}
                    title={t("dialogs.removeThread.remove")}
                  >
                    <Trash2 className="h-3 w-3" />
                  </button>
                )}
                {thread.threadId && (
                  <ExternalLink className="h-3 w-3 shrink-0 text-muted-foreground" />
                )}
              </div>
            ))}
          </div>
        </div>
      </SheetContent>

      <AutopilotRemoveDialog
        open={removeOpen}
        onOpenChange={setRemoveOpen}
        repoName={job.repoName}
        onConfirm={async ({ removeThreads }) => {
          const toastId = toast.loading(t("autopilot.remove.removing"));
          try {
            await removeJob(job.id, { removeThreads });
            toast.success(
              removeThreads ? t("autopilot.remove.removedWithThreads") : t("autopilot.remove.removed"),
              { id: toastId },
            );
          } catch (error) {
            toast.error(t("autopilot.remove.failed"), { id: toastId });
            throw error;
          }
          setRemoveOpen(false);
          handleClose();
        }}
      />

      <RemoveThreadDialog
        open={!!threadToRemove}
        onOpenChange={(nextOpen) => {
          if (!nextOpen) setThreadToRemove(null);
        }}
        onRemove={() => void handleRemoveThread()}
        threadTitle={threadToRemove?.issueTitle ?? ""}
        isRemoving={isRemovingThread}
      />
    </Sheet>
  );
}
