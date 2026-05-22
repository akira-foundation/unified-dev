import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, ChevronDown, GitMerge, Loader2, Sparkles } from "lucide-react";

import { useI18n } from "@/i18n/i18n";
import { useNavigationStore } from "@/stores/navigation-store";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { queryKeys } from "@/lib/query-keys";
import type { PrMergeStrategy, PullRequestDto } from "@/types/organization";

interface PrMergePanelProps {
  pr: PullRequestDto;
  organizationId: string;
  repoName: string;
  owner: string;
  onMerged: () => void;
}

export function PrMergePanel({ pr, organizationId, repoName, owner, onMerged }: PrMergePanelProps) {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const { navigateTo, setIsAgentMode } = useNavigationStore();
  const agents = useAgentsStore();
  const [mergeError, setMergeError] = useState<string | null>(null);
  const [isMerging, setIsMerging] = useState(false);
  const [isResolving, setIsResolving] = useState(false);

  const strategyLabels: Record<PrMergeStrategy, string> = {
    merge: t("components.prDetail.mergeCommit"),
    squash: t("components.prDetail.mergeSquash"),
    rebase: t("components.prDetail.mergeRebase"),
  };

  const handleMerge = async (strategy: PrMergeStrategy) => {
    if (isMerging) return;
    setMergeError(null);
    setIsMerging(true);
    const toastId = toast.loading(`Merging #${pr.number}…`);
    try {
      await invoke("merge_pr", { organizationId, repoName, prNumber: pr.number, strategy });
      toast.success(`PR #${pr.number} merged successfully`, { id: toastId });
      queryClient.invalidateQueries({ queryKey: queryKeys.allRepositories() });
      queryClient.invalidateQueries({ queryKey: queryKeys.selectedRepositories(organizationId) });
      queryClient.invalidateQueries({ queryKey: queryKeys.pullRequests(organizationId, repoName) });
      onMerged();
    } catch (err) {
      toast.dismiss(toastId);
      setMergeError(String(err));
    } finally {
      setIsMerging(false);
    }
  };

  const handleResolveWithAI = async () => {
    if (isResolving) return;
    setIsResolving(true);
    const toastId = toast.loading(t("components.prDetail.resolveWithAi.delegating"));
    try {
      const target = `${owner}/${repoName}`.toLowerCase();
      const repoOnly = repoName.toLowerCase();
      const findRepo = () =>
        useAgentsStore.getState().repositoryGroups
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

      let repo = findRepo();
      if (!repo) {
        toast.loading(t("components.prDetail.resolveWithAi.registering"), { id: toastId });
        await invoke("add_remote_repository", { url: `https://github.com/${owner}/${repoName}.git` });
        await agents.loadRepositories();
        repo = findRepo();
        if (!repo) {
          toast.error(t("pages.repositoryDetail.toast.repoNotInAgent"), { id: toastId });
          return;
        }
      }

      const thread = await invoke<{ id: string; title: string; workspace_path: string }>(
        "create_thread_from_pull_request",
        { repoId: repo.id, title: pr.title, headSha: pr.head_sha },
      );
      await invoke("set_thread_pr_url", { threadId: thread.id, prUrl: pr.url, prIsDraft: pr.is_draft });
      agents.setThreadPrInfo(thread.id, { url: pr.url, isDraft: pr.is_draft });
      agents.addThread(repo.id, thread);
      await agents.loadRepositories();
      agents.setExpandedRepos((prev) => ({ ...prev, [repo!.id]: true }));

      const prompt = t("components.prDetail.resolveWithAi.prompt", {
        number: String(pr.number),
        title: pr.title,
        error: mergeError ?? "",
      });
      agents.setActiveTab("workspace");
      agents.setSelectedIssueId(thread.id);
      setIsAgentMode(true);
      navigateTo("agents");
      if (agents.selectedModelId) {
        await agents.sendMessage(thread.id, prompt, agents.selectedModelId, false);
      }
      toast.success(t("components.prDetail.resolveWithAi.delegated"), { id: toastId });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : String(err), { id: toastId });
    } finally {
      setIsResolving(false);
    }
  };

  return (
    <div className="flex flex-col gap-2">
      {mergeError && (
        <div className="flex flex-col gap-2 rounded-lg border border-red-500/20 bg-red-500/5 px-3 py-2.5 dark:bg-red-500/10">
          <div className="flex items-start gap-2 text-[13px] text-red-600 dark:text-red-400">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
            <span className="flex-1">{mergeError}</span>
          </div>
          <Button
            variant="outline"
            size="sm"
            className="self-start border-red-500/40 text-red-600 hover:bg-red-500/10 dark:text-red-300"
            onClick={() => void handleResolveWithAI()}
            disabled={isResolving}
          >
            {isResolving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Sparkles className="h-3.5 w-3.5" />}
            {t("components.prDetail.resolveWithAi")}
          </Button>
        </div>
      )}
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            variant="ghost"
            className="w-full justify-center gap-2 border border-purple-500/20 bg-purple-500/10 text-purple-600 hover:bg-purple-500/20 dark:text-purple-300 dark:hover:bg-purple-500/20"
            disabled={isMerging || pr.merged_at !== null}
          >
            {isMerging ? <Loader2 className="h-4 w-4 animate-spin" /> : <GitMerge className="h-4 w-4" />}
            {isMerging ? t("components.prDetail.merging") : t("components.prDetail.merge")}
            <ChevronDown className="h-4 w-4 opacity-70" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start" className="w-[var(--radix-dropdown-menu-trigger-width)]">
          {(["merge", "squash", "rebase"] as PrMergeStrategy[]).map((s) => (
            <DropdownMenuItem key={s} onClick={() => void handleMerge(s)}>
              {strategyLabels[s]}
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}
