import { CheckCircle2, XCircle, Loader2, CircleDashed } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";

interface PrCiToggleProps {
  threadId: string;
}

export function PrCiToggle({ threadId }: PrCiToggleProps) {
  const ci = useAgentsStore((s) => s.prCiByThread[threadId]);
  const islandPanel = useAgentsStore((s) => s.islandPanel);
  const isRightSidebarOpen = useAgentsStore((s) => s.isRightSidebarOpen);
  const setIslandPanel = useAgentsStore((s) => s.setIslandPanel);
  const setIsRightSidebarOpen = useAgentsStore((s) => s.setIsRightSidebarOpen);
  if (!ci || ci.total === 0) return null;

  const isOpen = isRightSidebarOpen && islandPanel === "ci";
  const failing = ci.failing > 0;
  const pending = ci.pending > 0;
  const allPass = !failing && !pending && ci.passing === ci.total;

  const Icon = failing ? XCircle : pending ? Loader2 : allPass ? CheckCircle2 : CircleDashed;
  const color = failing
    ? "text-red-400 border-red-500/30 hover:bg-red-500/10 hover:border-red-500/40"
    : pending
      ? "text-amber-400 border-amber-500/30 hover:bg-amber-500/10 hover:border-amber-500/40"
      : allPass
        ? "text-emerald-400 border-emerald-500/30 hover:bg-emerald-500/10 hover:border-emerald-500/40"
        : "text-zinc-400 border-zinc-500/30 hover:bg-zinc-500/10 hover:border-zinc-500/40";

  const toggle = () => {
    if (isOpen) setIsRightSidebarOpen(false);
    else {
      setIslandPanel("ci");
      setIsRightSidebarOpen(true);
    }
  };

  return (
    <button
      type="button"
      onClick={toggle}
      title={`CI: ${ci.passing}/${ci.total} (${isOpen ? "hide" : "show"} details)`}
      className={cn(
        "h-8 inline-flex items-center gap-1.5 px-2.5 rounded-md border text-[12px] font-semibold tabular-nums transition-all cursor-pointer",
        color,
        isOpen && "bg-foreground/5",
      )}
    >
      <Icon className={cn("h-3.5 w-3.5", pending && "animate-spin")} />
      <span>{ci.passing}/{ci.total}</span>
    </button>
  );
}
