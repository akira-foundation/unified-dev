import { CheckCircle2, XCircle, Loader2, CircleDashed, ExternalLink, Eye } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useNavigationStore, type ActiveRepo } from "@/stores/navigation-store";
import type { PullRequestDto } from "@/types/organization";

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
      navigateTo("pr-review");
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
      <Eye className="h-3 w-3" />
    </button>
  );
}

export function PrCiCard({ threadId, className }: PrCiCardProps) {
  const ci = useAgentsStore((s) => s.prCiByThread[threadId]);
  const prInfo = useAgentsStore((s) => s.prUrlByThread[threadId]);
  const prUrl = prInfo?.url ?? null;
  const isOpen = useAgentsStore((s) => s.prCiCardOpenByThread[threadId]);
  if (!ci || ci.total === 0) return null;
  if (prInfo?.state === "MERGED") return null;

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
          const target = resolveCheckLink(c.link, prUrl);
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
              <OpenInAppButton threadId={threadId} checkName={c.name} />
              {target && (
                <button
                  type="button"
                  onClick={() => openUrl(target)}
                  className="text-foreground/40 hover:text-foreground/80 transition-colors"
                  aria-label="Open check on provider"
                  title="Open on provider"
                >
                  <ExternalLink className="h-3 w-3" />
                </button>
              )}
            </li>
          );
        })}
      </ul>
    </div>
  );
}
