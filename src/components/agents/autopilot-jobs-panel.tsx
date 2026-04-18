import { useEffect, useState } from "react";
import { Square, CheckCircle2, XCircle, Rocket, Trash2, Play, Loader2 } from "lucide-react";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { AutopilotRemoveDialog } from "@/components/agents/autopilot-remove-dialog";
import { cn } from "@/lib/utils";
import { useAutopilotStore, type AutopilotJob } from "@/stores/useAutopilotStore";
import { useI18n } from "@/i18n/i18n";

interface AutopilotJobsPanelProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

function JobRow({ job, onSelect, onStop, onResume, onRemove }: {
  job: AutopilotJob;
  onSelect: () => void;
  onStop: () => void;
  onResume: () => void;
  onRemove: () => void;
}) {
  const { t } = useI18n();
  const pct = job.total > 0 ? Math.round((job.created / job.total) * 100) : 0;

  return (
    <button
      type="button"
      onClick={onSelect}
      className="w-full text-left rounded-lg border border-border bg-background/50 p-3 hover:bg-accent transition-colors group"
    >
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-2 min-w-0">
          {(job.status === "running" || job.status === "waiting") && <Rocket className="h-3.5 w-3.5 shrink-0 text-purple-500 animate-pulse" />}
          {job.status === "stopping" && <Loader2 className="h-3.5 w-3.5 shrink-0 text-red-500 animate-spin" />}
          {job.status === "done" && <CheckCircle2 className="h-3.5 w-3.5 shrink-0 text-green-500" />}
          {job.status === "stopped" && <XCircle className="h-3.5 w-3.5 shrink-0 text-yellow-500" />}
          {job.status === "error" && <XCircle className="h-3.5 w-3.5 shrink-0 text-red-500" />}
          <span className="text-sm font-medium truncate">{job.repoName}</span>
        </div>

        <div className="flex items-center gap-1 shrink-0" onClick={(e) => e.stopPropagation()}>
          {job.status === "running" || job.status === "waiting" ? (
            <Button
              size="icon"
              variant="ghost"
              className="h-6 w-6 text-red-500 hover:text-red-600 hover:bg-red-500/10"
              onClick={onStop}
              title={t("autopilot.panel.stop")}
            >
              <Square className="h-3 w-3 fill-current" />
            </Button>
          ) : job.status === "stopping" ? (
            <Button
              size="icon"
              variant="ghost"
              disabled
              className="h-6 w-6 text-red-500 opacity-100"
              title={t("autopilot.panel.stopping")}
            >
              <Loader2 className="h-3 w-3 animate-spin" />
            </Button>
          ) : job.status === "stopped" ? (
            <>
              <Button
                size="icon"
                variant="ghost"
                className="h-6 w-6 text-purple-500 hover:text-purple-600 hover:bg-purple-500/10"
                onClick={onResume}
                title={t("autopilot.panel.resume")}
              >
                <Play className="h-3 w-3 fill-current" />
              </Button>
              <Button
                size="icon"
                variant="ghost"
                className="h-6 w-6 text-muted-foreground hover:text-red-500 hover:bg-red-500/10"
                onClick={onRemove}
                title={t("autopilot.panel.remove")}
              >
                <Trash2 className="h-3 w-3" />
              </Button>
            </>
          ) : (
            <Button
              size="icon"
              variant="ghost"
              className="h-6 w-6 opacity-0 group-hover:opacity-100 text-muted-foreground hover:text-foreground"
              onClick={onRemove}
              title={t("autopilot.panel.remove")}
            >
              <Trash2 className="h-3 w-3" />
            </Button>
          )}
        </div>
      </div>

      <div className="mt-2 space-y-1">
        <div className="h-1.5 w-full rounded-full bg-zinc-200 dark:bg-zinc-800 overflow-hidden">
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
              ? t("autopilot.panel.progress").replace("{created}", String(job.created)).replace("{total}", String(job.total))
              : job.status === "stopping"
                ? t("autopilot.panel.stopping")
              : job.status === "done"
                ? t("autopilot.panel.done").replace("{total}", String(job.total))
                : t("autopilot.panel.stopped").replace("{created}", String(job.created)).replace("{total}", String(job.total))}
          </span>
          <span>{pct}%</span>
        </div>
      </div>
    </button>
  );
}

export function AutopilotJobsPanel({ open, onOpenChange }: AutopilotJobsPanelProps) {
  const { t } = useI18n();
  const { jobs, selectJob, cancelJob, removeJob, clearCompleted, resumeJob } = useAutopilotStore();
  const [jobToRemove, setJobToRemove] = useState<AutopilotJob | null>(null);

  const allJobs = Object.values(jobs).sort(
    (a, b) => new Date(b.startedAt).getTime() - new Date(a.startedAt).getTime(),
  );
  const hasCompleted = allJobs.some((j) => j.status !== "running" && j.status !== "waiting");

  useEffect(() => {
    if (open && allJobs.length === 0 && !jobToRemove) {
      onOpenChange(false);
    }
  }, [allJobs.length, jobToRemove, onOpenChange, open]);

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="left" className="w-[380px] flex flex-col p-0">
        <SheetHeader className="px-5 pt-5 pb-3 border-b border-border shrink-0 pr-12">
          <div className="flex items-center justify-between">
            <SheetTitle className="flex items-center gap-2 text-base">
              <Rocket className="h-4 w-4 text-purple-500" />
              {t("autopilot.panel.title")}
            </SheetTitle>
            {hasCompleted && (
              <Button
                variant="ghost"
                size="sm"
                className="h-7 text-xs text-muted-foreground"
                onClick={clearCompleted}
              >
                {t("autopilot.panel.clearCompleted")}
              </Button>
            )}
          </div>
        </SheetHeader>

        <div className="flex-1 overflow-y-auto p-4 space-y-2">
          {allJobs.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-16 text-center gap-3">
              <Rocket className="h-8 w-8 text-muted-foreground/30" />
              <p className="text-sm text-muted-foreground">{t("autopilot.panel.empty")}</p>
            </div>
          ) : (
            allJobs.map((job) => (
              <JobRow
                key={job.id}
                job={job}
                onSelect={() => {
                  selectJob(job.id);
                  onOpenChange(false);
                }}
                onStop={() => cancelJob(job.id)}
                onResume={() => resumeJob(job.id)}
                 onRemove={() => setJobToRemove(job)}
               />
             ))
           )}
         </div>
      </SheetContent>

      <AutopilotRemoveDialog
        open={!!jobToRemove}
        onOpenChange={(nextOpen) => {
          if (!nextOpen) setJobToRemove(null);
        }}
        repoName={jobToRemove?.repoName ?? ""}
        onConfirm={async ({ removeThreads }) => {
          if (!jobToRemove) return;
          await removeJob(jobToRemove.id, { removeThreads });
          setJobToRemove(null);
        }}
      />
    </Sheet>
  );
}
