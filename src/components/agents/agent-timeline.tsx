import { CheckCircle2, Loader2, AlertCircle, Info } from "lucide-react";
import { cn } from "@/lib/utils";
import type { AgentTimelineStep } from "@/types/agents";

interface AgentTimelineProps {
  steps: AgentTimelineStep[];
}

export function AgentTimeline({ steps }: AgentTimelineProps) {
  return (
    <div className="flex flex-col gap-6 p-8 relative">
      <div className="absolute left-[56px] top-12 bottom-12 w-px bg-gradient-to-b from-zinc-200 via-zinc-200 to-transparent dark:from-zinc-800 dark:via-zinc-800 dark:to-transparent" />

      {steps.map((step) => (
        <div key={step.id} className="flex gap-6 group">
          <div className="relative z-10 flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-white dark:bg-zinc-900 border border-border/10 shadow-sm group-hover:scale-105 transition-transform duration-300">
            {step.status === "completed" && <CheckCircle2 className="h-5 w-5 text-emerald-500" />}
            {step.status === "running" && <Loader2 className="h-5 w-5 text-blue-500 animate-spin" />}
            {step.status === "warning" && <AlertCircle className="h-5 w-5 text-amber-500" />}
            {step.status === "error" && <AlertCircle className="h-5 w-5 text-destructive" />}
            {step.status === "info" && <Info className="h-5 w-5 text-zinc-400" />}
          </div>

          <div className="flex flex-col gap-1.5 flex-1 pt-1.5">
            <div className="flex items-center justify-between gap-4">
              <span className={cn(
                "text-sm font-bold tracking-tight",
                step.status === "running" ? "text-foreground" : "text-foreground/80"
              )}>
                {step.message}
              </span>
              <span className="text-[10px] font-medium text-muted-foreground/40 tabular-nums uppercase tracking-widest">
                {step.timestamp}
              </span>
            </div>
            {step.details && (
              <div className="rounded-xl bg-zinc-50 dark:bg-zinc-900/50 p-3 border border-border/5 text-xs text-muted-foreground leading-relaxed">
                {step.details}
              </div>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
