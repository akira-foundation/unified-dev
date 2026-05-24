import { CheckCircle2, XCircle, Loader2, CircleDashed, ExternalLink, Eye, X } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useNavigationStore, type ActiveRepo } from "@/stores/navigation-store";
import type { PullRequestDto } from "@/types/organization";

interface PrCiPanelProps {
  threadId: string;
  onClose: () => void;
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

function OpenInAppButton({ threadId, checkName }: { threadId: string; checkName?: string }) {
  const setActivePr = useNavigationStore((s) => s.setActivePr);
  const setActiveRepo = useNavigationStore((s) => s.setActiveRepo);
  const setTargetCheckName = useNavigationStore((s) => s.setTargetCheckName);
  const navigateTo = useNavigationStore((s) => s.navigateTo);

  const handleClick = async () => {
    try {
      const ctx = await invoke<{
        repo: { name: string; owner: string; organization_id: string };
        pr: PullRequestDto;
      }>("get_thread_pr_review_context", { threadId });
      const repo: ActiveRepo = {
        name: ctx.repo.name,
        owner: ctx.repo.owner,
        organizationId: ctx.repo.organization_id,
      };
      setActiveRepo(repo);
      setActivePr(ctx.pr);
      setTargetCheckName(checkName ?? null);
      navigateTo("pr-detail");
    } catch (err) {
      toast.error(`Failed to open PR review: ${err}`);
    }
  };

  return (
    <button
      type="button"
      onClick={handleClick}
      className="text-foreground/40 hover:text-[#A855F7] transition-colors"
      title="View check in app"
      aria-label="View check in app"
    >
      <Eye className="h-3.5 w-3.5" />
    </button>
  );
}

export function PrCiPanel({ threadId, onClose }: PrCiPanelProps) {
  const ci = useAgentsStore((s) => s.prCiByThread[threadId]);
  const prInfo = useAgentsStore((s) => s.prUrlByThread[threadId]);
  const prUrl = prInfo?.url ?? null;

  const failing = (ci?.failing ?? 0) > 0;
  const allPass = !!ci && !failing && ci.pending === 0 && ci.passing === ci.total && ci.total > 0;

  return (
    <div className="flex h-full w-[min(420px,32%)] shrink-0 flex-col overflow-hidden border-l border-zinc-200 bg-white dark:border-white/[0.06] dark:bg-background">
      <div className="flex h-11 shrink-0 items-center justify-between gap-2 border-b border-zinc-200 px-3 dark:border-white/[0.06]">
        <div className="flex min-w-0 items-center gap-2 text-[12px] font-medium text-foreground/70">
          <span>CI Checks</span>
          {ci && (
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
          )}
        </div>
        <button
          onClick={onClose}
          className="flex h-6 w-6 items-center justify-center rounded-md text-zinc-400 transition-colors hover:bg-zinc-100 hover:text-foreground dark:hover:bg-white/[0.06]"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto custom-scrollbar p-2">
        {!ci || ci.checks.length === 0 ? (
          <p className="px-2.5 py-6 text-center text-[12px] text-zinc-500">No checks</p>
        ) : (
          <ul className="space-y-1.5">
            {ci.checks.map((c) => {
              const { Icon, color } = bucketIcon(c.bucket);
              const target = resolveCheckLink(c.link, prUrl);
              return (
                <li
                  key={`${c.workflow ?? ""}-${c.name}`}
                  className="flex items-center gap-2.5 rounded-md px-2.5 py-2 text-[13px] text-foreground/80 hover:bg-zinc-100 dark:hover:bg-white/[0.04]"
                >
                  <Icon className={cn("h-4 w-4 shrink-0", color)} />
                  <span className="truncate flex-1">
                    {c.workflow ? `${c.workflow} / ` : ""}
                    {c.name}
                  </span>
                  <OpenInAppButton threadId={threadId} checkName={c.name} />
                  {target && (
                    <button
                      type="button"
                      onClick={() => openUrl(target)}
                      className="text-foreground/40 hover:text-foreground/80 transition-colors"
                      aria-label="Open check on provider"
                      title="Open on provider"
                    >
                      <ExternalLink className="h-3.5 w-3.5" />
                    </button>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  );
}
