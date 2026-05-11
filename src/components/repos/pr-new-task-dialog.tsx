import { invoke } from "@tauri-apps/api/core";
import { Loader2, Rocket } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";

import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useI18n } from "@/i18n/i18n";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useNavigationStore } from "@/stores/navigation-store";
import type { PullRequestDto } from "@/types/organization";

interface PrNewTaskDialogProps {
  pr: PullRequestDto | null;
  repoNameWithOwner: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function PrNewTaskDialog({
  pr,
  repoNameWithOwner,
  open,
  onOpenChange,
}: PrNewTaskDialogProps) {
  const { t } = useI18n();
  const {
    repositoryGroups,
    addThread,
    sendMessage,
    selectedModelId,
    setThreadPrInfo,
    setExpandedRepos,
    loadRepositories,
    setSelectedIssueId,
    setActiveTab,
  } = useAgentsStore();
  const setIsAgentMode = useNavigationStore((s) => s.setIsAgentMode);
  const navigateTo = useNavigationStore((s) => s.navigateTo);
  const [prompt, setPrompt] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!open) setPrompt("");
  }, [open]);

  async function handleSubmit() {
    if (!pr || !repoNameWithOwner || !prompt.trim()) return;
    setBusy(true);
    try {
      const target = repoNameWithOwner.toLowerCase();
      const repoOnly = target.split("/")[1] ?? target;
      const repo = repositoryGroups
        .flatMap((g) => g.repositories)
        .find((r) => {
          if (r.displayName?.toLowerCase() === target) return true;
          if (r.remoteUrl) {
            const m = r.remoteUrl.match(/github\.com[:/]([^/]+\/[^/]+?)(?:\.git)?$/i);
            if (m && m[1].toLowerCase() === target) return true;
          }
          const n = r.name.toLowerCase();
          return n === target || n.endsWith(`/${repoOnly}`) || n === repoOnly;
        });

      if (!repo) {
        toast.error(t("pages.repositoryDetail.toast.repoNotInAgent"));
        return;
      }

      const thread = await invoke<{ id: string; title: string; workspace_path: string }>(
        "create_thread_from_pull_request",
        { repoId: repo.id, title: pr.title, headSha: pr.head_sha },
      );

      await invoke("set_thread_pr_url", {
        threadId: thread.id,
        prUrl: pr.url,
        prIsDraft: pr.is_draft,
      });

      setThreadPrInfo(thread.id, { url: pr.url, isDraft: pr.is_draft });
      addThread(repo.id, thread);
      await loadRepositories();
      setExpandedRepos((prev) => ({ ...prev, [repo.id]: true }));

      setActiveTab("workspace");
      setSelectedIssueId(thread.id);
      setIsAgentMode(true);
      navigateTo("agents");
      onOpenChange(false);

      if (selectedModelId) {
        await sendMessage(thread.id, prompt.trim(), selectedModelId, false);
      }
    } catch (error) {
      toast.error(error instanceof Error ? error.message : String(error));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-[480px] gap-0 overflow-hidden p-0">
        <DialogHeader className="border-b border-border px-5 pt-5 pb-4">
          <DialogTitle className="flex items-center gap-2 text-base">
            <Rocket className="h-4 w-4 text-purple-500" />
            {t("components.prNewTask.title")}
          </DialogTitle>
          {pr ? (
            <p className="mt-1.5 text-sm text-muted-foreground">
              <span className="text-zinc-400 dark:text-zinc-500">#{pr.number}</span>{" "}
              <span>{pr.title}</span>
            </p>
          ) : null}
        </DialogHeader>

        <div className="px-5 py-4">
          <textarea
            autoFocus
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
            placeholder={t("components.prNewTask.placeholder")}
            rows={6}
            className="w-full resize-none rounded-md border border-zinc-200 bg-zinc-100 px-3 py-2 text-sm text-zinc-700 placeholder:text-zinc-400 focus:border-zinc-300 focus:outline-none dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-200 dark:placeholder:text-zinc-500 dark:focus:border-zinc-600"
          />
        </div>

        <DialogFooter className="flex gap-2 px-5 pb-5 pt-0">
          <Button variant="outline" size="sm" onClick={() => onOpenChange(false)} disabled={busy}>
            {t("common.cancel")}
          </Button>
          <Button
            onClick={handleSubmit}
            size="sm"
            className="flex-1 bg-purple-600 text-white hover:bg-purple-700"
            disabled={busy || !prompt.trim() || !selectedModelId}
          >
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
            {t("components.prNewTask.submit")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
