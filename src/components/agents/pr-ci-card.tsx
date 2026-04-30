import { CheckCircle2, XCircle, Loader2, CircleDashed, ExternalLink } from "lucide-react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";

interface PrCiCardProps {
  threadId: string;
  className?: string;
}

function bucketIcon(bucket: string) {
  switch (bucket) {
    case "pass":
      return { Icon: CheckCircle2, color: "text-emerald-400" };
    case "fail":
    case "cancel":
      return { Icon: XCircle, color: "text-red-400" };
    case "pending":
      return { Icon: Loader2, color: "text-amber-400 animate-spin" };
    default:
      return { Icon: CircleDashed, color: "text-zinc-400" };
  }
}

function resolveCheckLink(link: string | null | undefined, prUrl: string | null): string | null {
  if (!link) return prUrl;
  try {
    const u = new URL(link);
    if (u.pathname === "/" || u.pathname === "") return prUrl ?? link;
    return link;
  } catch {
    return prUrl ?? link;
  }
}

export function PrCiCard({ threadId, className }: PrCiCardProps) {
  const ci = useAgentsStore((s) => s.prCiByThread[threadId]);
  const prUrl = useAgentsStore((s) => s.prUrlByThread[threadId]?.url ?? null);
  const isOpen = useAgentsStore((s) => s.prCiCardOpenByThread[threadId]);
  if (!ci || ci.total === 0) return null;

  const autoShow = ci.failing > 0 || ci.pending > 0;
  if (!autoShow && !isOpen) return null;

  const failing = ci.failing > 0;
  const allPass = !failing && ci.pending === 0 && ci.passing === ci.total;

  return (
    <div
      className={cn(
        "rounded-xl border border-border/40 bg-card/40 backdrop-blur-sm p-3",
        className,
      )}
    >
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-2">
          <span className="text-[12px] font-semibold text-foreground/80">CI Checks</span>
          <span
            className={cn(
              "text-[11px] font-medium tabular-nums px-2 py-0.5 rounded-md",
              failing
                ? "text-red-400 bg-red-500/10"
                : allPass
                  ? "text-emerald-400 bg-emerald-500/10"
                  : "text-amber-400 bg-amber-500/10",
            )}
          >
            {ci.passing}/{ci.total}
          </span>
        </div>
      </div>
      <ul className="space-y-1.5">
        {ci.checks.map((c) => {
          const { Icon, color } = bucketIcon(c.bucket);
          return (
            <li
              key={`${c.workflow ?? ""}-${c.name}`}
              className="flex items-center gap-2 text-[12px] text-foreground/80"
            >
              <Icon className={cn("h-3.5 w-3.5 shrink-0", color)} />
              <span className="truncate flex-1">
                {c.workflow ? `${c.workflow} / ` : ""}
                {c.name}
              </span>
              {(() => {
                const target = resolveCheckLink(c.link, prUrl);
                if (!target) return null;
                return (
                  <button
                    type="button"
                    onClick={() => openUrl(target)}
                    className="text-foreground/40 hover:text-foreground/80 transition-colors"
                    aria-label="Open check"
                  >
                    <ExternalLink className="h-3 w-3" />
                  </button>
                );
              })()}
            </li>
          );
        })}
      </ul>
    </div>
  );
}
