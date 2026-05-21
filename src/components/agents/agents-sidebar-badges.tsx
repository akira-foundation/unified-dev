import { CheckCircle2, GitMerge, GitPullRequest, Loader2, XCircle } from "lucide-react";
import { openUrl } from "@tauri-apps/plugin-opener";

import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useI18n } from "@/i18n/i18n";

export function RepoStreamingIndicator({ repoIssueIds }: { repoIssueIds: string[] }) {
  const streamingThreadIds = useAgentsStore((s) => s.streamingThreadIds);
  const isStreaming = repoIssueIds.some((id) => !!streamingThreadIds[id]);
  if (!isStreaming) return null;
  return <div className="h-3 w-3 shrink-0 rounded-full border border-t-foreground/60 border-foreground/20 animate-spin" />;
}

export function ThreadStreamingDots({ threadId }: { threadId: string }) {
  const isStreaming = useAgentsStore((s) => !!s.streamingThreadIds[threadId]);
  if (!isStreaming) return null;
  return (
    <span className="flex items-center gap-[3px] shrink-0">
      <span className="h-[3px] w-[3px] rounded-full dark:bg-white/50 bg-foreground/50 animate-bounce [animation-delay:0ms]" />
      <span className="h-[3px] w-[3px] rounded-full dark:bg-white/50 bg-foreground/50 animate-bounce [animation-delay:150ms]" />
      <span className="h-[3px] w-[3px] rounded-full dark:bg-white/50 bg-foreground/50 animate-bounce [animation-delay:300ms]" />
    </span>
  );
}

export function ThreadPrCiBadge({ threadId }: { threadId: string }) {
  const ci = useAgentsStore((s) => s.prCiByThread[threadId]);
  const prInfo = useAgentsStore((s) => s.prUrlByThread[threadId]);
  if (!ci || ci.total === 0) return null;
  if (prInfo?.state === "MERGED") return null;

  const failing = ci.failing > 0;
  const pending = ci.pending > 0;
  const allPass = !failing && !pending && ci.passing === ci.total;

  const Icon = failing ? XCircle : pending ? Loader2 : allPass ? CheckCircle2 : Loader2;
  const color = failing
    ? "text-red-400 border-red-500/30 bg-red-500/10"
    : pending
      ? "text-amber-400 border-amber-500/30 bg-amber-500/10"
      : allPass
        ? "text-emerald-400 border-emerald-500/30 bg-emerald-500/10"
        : "text-zinc-400 border-zinc-500/30 bg-zinc-500/10";

  return (
    <span
      className={cn(
        "shrink-0 inline-flex items-center gap-1 h-4 px-1.5 rounded border text-[10px] font-semibold tabular-nums",
        color,
      )}
      title={`${ci.passing} pass / ${ci.failing} fail / ${ci.pending} pending`}
    >
      <Icon className={cn("h-2.5 w-2.5", pending && "animate-spin")} />
      {ci.passing}/{ci.total}
    </span>
  );
}

export function ThreadPrIcon({ threadId }: { threadId: string }) {
  const { t } = useI18n();
  const prInfo = useAgentsStore((s) => s.prUrlByThread[threadId]);
  if (!prInfo) return null;
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={(event) => {
        event.stopPropagation();
        void openUrl(prInfo.url);
      }}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.stopPropagation();
          void openUrl(prInfo.url);
        }
      }}
      className="shrink-0 cursor-pointer"
      title={t("agents.header.viewPr")}
    >
      {prInfo.state === "MERGED" ? (
        <GitMerge className="h-3 w-3 shrink-0 text-emerald-400 transition-opacity hover:opacity-80" />
      ) : (
        <GitPullRequest
          className={cn(
            "h-3 w-3 shrink-0 transition-opacity hover:opacity-80",
            prInfo.isDraft ? "text-zinc-500" : "text-[#A855F7]",
          )}
        />
      )}
    </div>
  );
}
