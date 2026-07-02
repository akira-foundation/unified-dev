import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { GitPullRequest, Loader2 } from "lucide-react";

import { useAgentsStore } from "@/stores/useAgentsStore";
import { useI18n } from "@/i18n/i18n";
import { Button } from "@/components/ui/button";
import { shouldOfferPushPr } from "@/lib/push-pr";

interface AgentPushPrButtonProps {
  threadId: string;
  workspacePath: string;
  branchName: string;
  title: string;
  className?: string;
}

export function AgentPushPrButton({ threadId, workspacePath, branchName, title, className }: AgentPushPrButtonProps) {
  const { t } = useI18n();
  const isStreaming = useAgentsStore((s) => !!s.streamingThreadIds[threadId]);
  const hasPr = useAgentsStore((s) => Boolean(s.prUrlByThread[threadId]?.url));
  const loadPrUrl = useAgentsStore((s) => s.loadPrUrl);
  const [branchAhead, setBranchAhead] = useState(false);
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    if (isStreaming || hasPr || !workspacePath) {
      setBranchAhead(false);
      return;
    }
    let cancelled = false;
    invoke<boolean>("check_branch_ahead", { workspacePath })
      .then((ahead) => { if (!cancelled) setBranchAhead(ahead); })
      .catch(() => { if (!cancelled) setBranchAhead(false); });
    return () => { cancelled = true; };
  }, [isStreaming, hasPr, workspacePath]);

  if (!shouldOfferPushPr({ isStreaming, hasPr, branchAhead })) return null;

  const handleClick = async () => {
    if (creating) return;
    setCreating(true);
    const toastId = toast.loading(t("agents.pushPr.creating"));
    try {
      await invoke<string>("create_draft_pr", { workspacePath, branchName, title });
      toast.success(t("agents.pushPr.created"), { id: toastId });
      await loadPrUrl(threadId, workspacePath);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : String(err), { id: toastId });
    } finally {
      setCreating(false);
    }
  };

  return (
    <Button
      variant="outline"
      size="sm"
      className={className}
      onClick={() => void handleClick()}
      disabled={creating}
    >
      {creating ? <Loader2 className="h-4 w-4 animate-spin" /> : <GitPullRequest className="h-4 w-4" />}
      {t("agents.pushPr.action")}
    </Button>
  );
}
