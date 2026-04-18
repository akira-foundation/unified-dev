import { Rocket } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAutopilotStore } from "@/stores/useAutopilotStore";
import { useI18n } from "@/i18n/i18n";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";

interface AutopilotIndicatorProps {
  onOpen: () => void;
  collapsed?: boolean;
}

export function AutopilotIndicator({ onOpen, collapsed = false }: AutopilotIndicatorProps) {
  const { t } = useI18n();
  const jobs = useAutopilotStore((s) => s.jobs);

  const allJobs = Object.values(jobs);
  const running = allJobs.filter((j) => j.status === "running" || j.status === "waiting");
  const hasAny = allJobs.length > 0;

  if (!hasAny) return null;

  const button = (
    <button
      type="button"
      onClick={onOpen}
      className={cn(
        "flex items-center gap-2 rounded-md px-3 h-10 text-sm font-medium transition-colors w-full",
        "text-zinc-500 hover:bg-zinc-100/50 dark:hover:bg-zinc-900/50 hover:text-foreground dark:hover:text-zinc-300",
        collapsed && "justify-center px-0 size-10",
      )}
    >
      <div className="relative shrink-0 flex items-center justify-center">
        <Rocket
          className={cn(
            "h-4 w-4",
            running.length > 0 ? "text-purple-500" : "text-zinc-500",
          )}
        />
        {allJobs.length > 0 && (
          <span className={cn(
            "absolute -top-1.5 -right-1.5 flex h-3.5 w-3.5 items-center justify-center rounded-full text-[8px] font-bold text-white leading-none",
            running.length > 0 ? "bg-purple-500" : "bg-zinc-500",
          )}>
            {allJobs.length > 9 ? "9+" : allJobs.length}
          </span>
        )}
      </div>

      {!collapsed && (
        <span className="text-[13px] font-medium truncate">
          {running.length > 0
            ? t("autopilot.indicator.running").replace("{n}", String(running.length))
            : t("autopilot.indicator.idle")}
        </span>
      )}
    </button>
  );

  if (collapsed) {
    return (
      <TooltipProvider>
        <Tooltip>
          <TooltipTrigger asChild>{button}</TooltipTrigger>
          <TooltipContent side="right">
            {running.length > 0
              ? t("autopilot.indicator.running").replace("{n}", String(running.length))
              : t("autopilot.indicator.idle")}
          </TooltipContent>
        </Tooltip>
      </TooltipProvider>
    );
  }

  return button;
}
