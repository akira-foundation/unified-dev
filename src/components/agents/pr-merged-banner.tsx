import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { GitMerge, Trash2, X } from "lucide-react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useAutopilotStore } from "@/stores/useAutopilotStore";
import { RemoveThreadDialog } from "@/components/agents/remove-thread-dialog";
import { useI18n } from "@/i18n/i18n";

interface PrMergedBannerProps {
  threadId: string;
  threadTitle: string;
  className?: string;
}

export function PrMergedBanner({ threadId, threadTitle, className }: PrMergedBannerProps) {
  const { t } = useI18n();
  const prInfo = useAgentsStore((s) => s.prUrlByThread[threadId]);
  const dismissed = useAgentsStore((s) => s.mergedBannerDismissedByThread[threadId]);
  const dismissBanner = useAgentsStore((s) => s.dismissMergedBanner);
  const repositoryGroups = useAgentsStore((s) => s.repositoryGroups);
  const removeThread = useAgentsStore((s) => s.removeThread);
  const loadRepositories = useAgentsStore((s) => s.loadRepositories);
  const removeThreadReference = useAutopilotStore((s) => s.removeThreadReference);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [removing, setRemoving] = useState(false);

  if (dismissed) return null;
  if (prInfo?.state !== "MERGED") return null;

  const repoId = repositoryGroups
    .flatMap((g) => g.repositories)
    .find((r) => r.issues.some((i) => i.id === threadId))?.id ?? "";

  const handleRemove = async () => {
    const toastId = toast.loading(t("agents.sidebar.toast.removingThread"));
    setRemoving(true);
    try {
      await invoke("delete_thread", { threadId });
      removeThread(repoId, threadId);
      removeThreadReference(threadId);
      await loadRepositories();
      toast.success(t("agents.sidebar.toast.threadRemoved"), { id: toastId });
      setConfirmOpen(false);
    } catch (error) {
      toast.error(String(error), { id: toastId });
    } finally {
      setRemoving(false);
    }
  };

  const mergedLabel = prInfo.mergedAt
    ? new Date(prInfo.mergedAt).toLocaleString()
    : "";

  return (
    <>
      <div
        className={cn(
          "rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-3 py-2.5 flex items-center gap-3",
          className,
        )}
      >
        <GitMerge className="h-4 w-4 text-emerald-400 shrink-0" />
        <div className="flex-1 min-w-0">
          <p className="text-[12px] font-semibold text-foreground/90">PR merged{mergedLabel ? ` · ${mergedLabel}` : ""}</p>
          <p className="text-[11px] text-foreground/60">Workspace no longer needed. Safe to remove.</p>
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={() => setConfirmOpen(true)}
          className="h-7 px-2.5 text-[11px] gap-1.5 text-emerald-400 hover:bg-emerald-500/15 border border-emerald-500/30"
        >
          <Trash2 className="h-3 w-3" />
          Remove
        </Button>
        <button
          type="button"
          onClick={() => dismissBanner(threadId)}
          className="text-foreground/40 hover:text-foreground/80 shrink-0"
          aria-label="Dismiss"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </div>
      <RemoveThreadDialog
        open={confirmOpen}
        onOpenChange={(o) => !o && setConfirmOpen(false)}
        onRemove={handleRemove}
        threadTitle={threadTitle}
        isRemoving={removing}
      />
    </>
  );
}
