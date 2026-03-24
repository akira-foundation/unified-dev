import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useQuery } from "@tanstack/react-query";
import { CheckCircle2, XCircle, Clock, MinusCircle, SkipForward, Timer, ChevronDown, ChevronRight } from "lucide-react";
import { Card, CardContent } from "../ui/card";
import { Skeleton } from "../ui/skeleton";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "../ui/collapsible";
import { useI18n } from "../../i18n/i18n";
import { queryKeys } from "../../lib/query-keys";
import { highlightLine } from "../../lib/ansi-highlight";
import type { CiCheckDto, CiCheckStepDto } from "../../types/organization";

function formatDuration(startedAt: string | null, completedAt: string | null): string | null {
  if (!startedAt || !completedAt) return null;
  const start = new Date(startedAt).getTime();
  const end = new Date(completedAt).getTime();
  const seconds = Math.round((end - start) / 1000);
  if (seconds <= 0) return null;
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  const remaining = seconds % 60;
  return remaining > 0 ? `${minutes}m ${remaining}s` : `${minutes}m`;
}

function parseLogsByStep(raw: string, steps: CiCheckStepDto[]): Map<number, string[]> {
  const map = new Map<number, string[]>();
  const lines = raw.split("\n");
  const tsRegex = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z) /;

  for (const step of steps) {
    if (!step.started_at) continue;
    const start = new Date(step.started_at).getTime();
    const end = step.completed_at ? new Date(step.completed_at).getTime() : Infinity;

    const stepLines = lines
      .filter((line) => {
        const match = line.match(tsRegex);
        if (!match) return false;
        const ts = new Date(match[1]).getTime();
        return ts >= start && ts <= end;
      })
      .map((line) => line.replace(tsRegex, ""))
      .filter((line) => !line.startsWith("##["));

    map.set(step.number, stepLines);
  }

  return map;
}

function conclusionIcon(conclusion: string | null, status: string, size: "sm" | "md" = "md") {
  const cls = size === "sm" ? "h-3.5 w-3.5 shrink-0" : "h-4 w-4 shrink-0";
  if (status === "in_progress") return <Timer className={`${cls} text-blue-500 animate-pulse`} />;
  if (status !== "completed") return <Clock className={`${cls} text-zinc-400`} />;
  switch (conclusion) {
    case "success":    return <CheckCircle2 className={`${cls} text-emerald-500`} />;
    case "failure":
    case "timed_out":  return <XCircle className={`${cls} text-red-500`} />;
    case "skipped":    return <SkipForward className={`${cls} text-zinc-400`} />;
    default:           return <MinusCircle className={`${cls} text-zinc-400`} />;
  }
}

function conclusionLabel(conclusion: string | null, status: string, t: (k: string) => string): string {
  if (status === "completed" && conclusion) return t(`components.prChecks.conclusion.${conclusion}`) ?? conclusion;
  return t(`components.prChecks.status.${status}`) ?? status;
}

function conclusionColor(conclusion: string | null, status: string): string {
  if (status === "in_progress") return "text-blue-500 dark:text-blue-400";
  if (status === "completed") {
    if (conclusion === "success") return "text-emerald-600 dark:text-emerald-400";
    if (conclusion === "failure" || conclusion === "timed_out") return "text-red-500 dark:text-red-400";
  }
  return "text-zinc-400 dark:text-zinc-500";
}

function StepRow({
  step,
  logLines,
  logsLoading,
}: {
  step: CiCheckStepDto;
  logLines: string[] | undefined;
  logsLoading: boolean;
}) {
  const [open, setOpen] = useState(false);
  const duration = formatDuration(step.started_at, step.completed_at);

  return (
    <Collapsible open={open} onOpenChange={setOpen}>
      <CollapsibleTrigger className="w-full" asChild>
        <div className="flex items-center gap-3 px-4 py-2.5 border-b border-zinc-100/60 dark:border-zinc-800/60 last:border-0 cursor-pointer">
          {conclusionIcon(step.conclusion, step.status, "sm")}
          <span className="flex-1 text-xs text-zinc-700 dark:text-zinc-300 truncate min-w-0 text-left">
            {step.name}
          </span>
          {duration && (
            <span className="text-[11px] text-zinc-400 dark:text-zinc-500 tabular-nums shrink-0">
              {duration}
            </span>
          )}
          <ChevronRight
            className={`h-3 w-3 text-zinc-400 transition-transform duration-200 shrink-0 ${open ? "rotate-90" : ""}`}
          />
        </div>
      </CollapsibleTrigger>
      <CollapsibleContent>
        {open && (logsLoading ? (
          <div className="px-4 py-3 border-b border-zinc-100/60 dark:border-zinc-800/60">
            <Skeleton className="h-3 w-3/4 rounded" />
          </div>
        ) : logLines && logLines.length > 0 ? (
          <div className="px-4 py-3 border-b border-zinc-100/60 dark:border-zinc-800/60 bg-zinc-950/60 dark:bg-zinc-950/80 overflow-x-auto font-mono">
            {logLines.map((line, i) => (
              <div key={i} className="text-[11px] leading-5 whitespace-pre">
                {highlightLine(line).map((seg, j) => (
                  <span key={j} className={seg.className || "text-zinc-300 dark:text-zinc-400"} style={seg.style}>
                    {seg.text}
                  </span>
                ))}
              </div>
            ))}
          </div>
        ) : (
          <div className="px-4 py-2.5 border-b border-zinc-100/60 dark:border-zinc-800/60">
            <span className="text-[11px] text-zinc-500 italic">No output</span>
          </div>
        ))}
      </CollapsibleContent>
    </Collapsible>
  );
}

function CheckItem({
  check,
  orgId,
  repoName,
}: {
  check: CiCheckDto;
  orgId: string;
  repoName: string;
}) {
  const { t } = useI18n();
  const [open, setOpen] = useState(false);
  const duration = formatDuration(check.started_at, check.completed_at);
  const hasSteps = check.steps.length > 0;

  const { data: rawLogs, isLoading: logsLoading } = useQuery({
    queryKey: queryKeys.jobLogs(orgId, repoName, check.id),
    queryFn: async () => {
      const logs = await invoke<string>("get_job_logs", {
        organizationId: orgId,
        repoName,
        jobId: check.id,
      });
      return logs;
    },
    enabled: open && hasSteps && check.status === "completed",
    staleTime: 5 * 60 * 1000,
  });

  const logsByStep = rawLogs ? parseLogsByStep(rawLogs, check.steps) : undefined;

  return (
    <Collapsible open={open} onOpenChange={setOpen} disabled={!hasSteps}>
      <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
        <CollapsibleTrigger className="w-full" asChild>
          <div className={`flex items-center gap-3 px-4 py-3 select-none ${hasSteps ? "cursor-pointer" : ""}`}>
            <div className="h-7 w-7 flex items-center justify-center rounded-lg border shrink-0 bg-zinc-500/10 border-zinc-500/10">
              {conclusionIcon(check.conclusion, check.status)}
            </div>
            <span className="flex-1 text-sm font-semibold text-zinc-900 dark:text-white/95 truncate min-w-0 text-left">
              {check.name}
            </span>
            <div className="flex items-center gap-2 shrink-0">
              {duration && (
                <span className="text-[11px] text-zinc-400 dark:text-zinc-500 tabular-nums">
                  {duration}
                </span>
              )}
              <span className={`text-xs font-medium ${conclusionColor(check.conclusion, check.status)}`}>
                {conclusionLabel(check.conclusion, check.status, t)}
              </span>
            </div>
            <ChevronDown
              className={`h-3.5 w-3.5 text-zinc-400 transition-transform duration-200 shrink-0 ${hasSteps ? "" : "opacity-0"}`}
            />
          </div>
        </CollapsibleTrigger>
        {hasSteps && (
          <CollapsibleContent>
            <CardContent className="px-0 py-0 border-t border-zinc-100 dark:border-zinc-800">
              {check.steps.map((step) => (
                <StepRow
                  key={step.number}
                  step={step}
                  logLines={logsByStep?.get(step.number)}
                  logsLoading={logsLoading}
                />
              ))}
            </CardContent>
          </CollapsibleContent>
        )}
      </Card>
    </Collapsible>
  );
}

export function PrChecksView({
  checks,
  loading,
  orgId,
  repoName,
}: {
  checks: CiCheckDto[];
  loading: boolean;
  orgId: string;
  repoName: string;
}) {
  const { t } = useI18n();

  if (loading) {
    return (
      <div className="flex flex-col gap-2 p-3">
        <Skeleton className="h-12 w-full rounded-lg" />
        <Skeleton className="h-12 w-full rounded-lg" />
        <Skeleton className="h-12 w-full rounded-lg" />
      </div>
    );
  }

  if (checks.length === 0) {
    return (
      <div className="flex items-center justify-center h-full py-16">
        <p className="text-sm text-zinc-400 dark:text-zinc-500 italic">
          {t("components.prChecks.empty")}
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2 p-3">
      {checks.map((check) => (
        <CheckItem key={check.id} check={check} orgId={orgId} repoName={repoName} />
      ))}
    </div>
  );
}
