import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import type { AgentIssue } from "@/types/agents";
import { ChevronDown, ExternalLink, GitCommitHorizontal, GitMerge, Eye } from "lucide-react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useSettingsStore } from "@/stores/settings-store";
import { useI18n } from "@/i18n/i18n";
import { usePRChecksPolling } from "@/hooks/usePRChecks";
import { PrCiToggle } from "@/components/agents/pr-ci-toggle";
import { useNavigationStore } from "@/stores/navigation-store";
import { AppbarActions } from "@/components/layout/appbar-actions";
import { AgentPanelSelector } from "@/components/agents/agent-panel-selector";
import { buildActionConfigs, type ActionConfig, type HeaderAction } from "@/components/agents/agent-header-config";
import type { PullRequestDto } from "@/types/organization";

interface AgentHeaderProps {
  issue: AgentIssue;
}

export function AgentHeader({ issue }: AgentHeaderProps) {
  const { t } = useI18n();
  const ACTION_CONFIGS = buildActionConfigs(t);
  const [selectedAction, setSelectedAction] = useState<HeaderAction>("draft_pr");
  const [isActioning, setIsActioning] = useState(false);
  const [sheetCtx, setSheetCtx] = useState<{ pr: PullRequestDto; orgId: string; repo: string; owner: string } | null>(null);
  const [isMerging, setIsMerging] = useState(false);
  const ci = useAgentsStore((s) => s.prCiByThread[issue.id]);
  const allChecksPass = !!ci && ci.total > 0 && ci.passing === ci.total && ci.failing === 0 && ci.pending === 0;
  const { fileChanges, sendMessage, repositoryGroups, getEffectiveModelId, prUrlByThread, loadPrUrl, setThreadPrInfo } = useAgentsStore();
  const isStreaming = useAgentsStore((s) => !!s.streamingThreadIds[issue.id]);
  const { getPrompt } = useSettingsStore();
  const { navigateTo, setActivePr, setActiveRepo } = useNavigationStore();
  const isAgentMode = useNavigationStore((s) => s.isAgentMode);

  const currentAction = ACTION_CONFIGS[selectedAction];

  const repoId = repositoryGroups.flatMap((g) => g.repositories).find((r) => r.issues.some((i) => i.id === issue.id))?.id ?? "";
  const effectiveModelId = getEffectiveModelId(repoId, issue.id);
  const prUrl = prUrlByThread[issue.id] ?? null;
  usePRChecksPolling(issue.id, issue.workspacePath);

  const fetchContext = async () => {
    if (sheetCtx) return sheetCtx;
    const ctx = await invoke<{
      repo: { name: string; owner: string; organization_id: string };
      pr: PullRequestDto;
    }>("get_thread_pr_review_context", { threadId: issue.id });
    const next = {
      pr: ctx.pr,
      orgId: ctx.repo.organization_id,
      repo: ctx.repo.name,
      owner: ctx.repo.owner,
    };
    setSheetCtx(next);
    return next;
  };

  const handleMergePr = async () => {
    if (isMerging) return;
    setIsMerging(true);
    const toastId = toast.loading("Merging PR…");
    try {
      const ctx = await fetchContext();
      await invoke("merge_pr", {
        organizationId: ctx.orgId,
        repoName: ctx.repo,
        prNumber: ctx.pr.number,
        strategy: "merge",
      });
      toast.success(`PR #${ctx.pr.number} merged`, { id: toastId });
      setThreadPrInfo(issue.id, {
        url: ctx.pr.url,
        isDraft: false,
        state: "MERGED",
        mergedAt: new Date().toISOString(),
      });
      void loadPrUrl(issue.id, issue.workspacePath);
    } catch (err) {
      toast.error(String(err), { id: toastId });
    } finally {
      setIsMerging(false);
    }
  };

  const handleOpenSheet = async () => {
    try {
      const ctx = await fetchContext();
      setActiveRepo({ name: ctx.repo, owner: ctx.owner, organizationId: ctx.orgId });
      setActivePr(ctx.pr);
      navigateTo("pr-detail");
    } catch (err) {
      toast.error(`Failed to open PR: ${err}`);
    }
  };

  const handleAction = async (actionOverride?: HeaderAction) => {
    if (!effectiveModelId) {
      toast.error(t("agents.header.toast.noModel"));
      return;
    }

    setIsActioning(true);
    try {
      const actionKey = prUrl ? "merge_commit" : (actionOverride ?? selectedAction);
      const basePrompt = getPrompt(actionKey);
      const linearMatch = issue.title.match(/^([a-z]+)-(\d+)-/i);
      const linearId = linearMatch ? `${linearMatch[1].toUpperCase()}-${linearMatch[2]}` : null;
      const linkingNote = linearId
        ? `\n- Linear/Issue identifier: ${linearId}\n\nIMPORTANT: include "Closes ${linearId}" on its own line at the end of the PR body so the issue auto-links and the provider posts a backlink.`
        : "";
      const issueContext = `\n\nContext about this thread:\n- Thread title: ${issue.title}\n- Branch: ${issue.branchName}\n- Repository: ${issue.repoName}${linkingNote}\n\nUse the thread title as the basis for the PR title and body. The PR title should clearly reflect what was done.`;
      const prompt = basePrompt + issueContext;
      await sendMessage(issue.id, prompt, effectiveModelId, true);
    } catch (err) {
      toast.error(`Failed to start action: ${err}`);
    } finally {
      setIsActioning(false);
    }
  };

  if (!isAgentMode) return null;

  return (
    <AppbarActions>
      <div className="flex items-center gap-2">
        {fileChanges.length > 0 && !isStreaming && (
          prUrl ? (
            <Button onClick={() => void handleAction()} disabled={isActioning} title={t("agents.header.pushChanges")}>
              <GitCommitHorizontal className="h-4 w-4" />
              <span className="hidden xl:inline">{t("agents.header.pushChanges")}</span>
            </Button>
          ) : (
            <div className="flex items-center">
              <Button onClick={() => void handleAction()} disabled={isActioning} className="rounded-r-none" title={currentAction.label}>
                <currentAction.icon className="h-4 w-4" />
                <span className="hidden xl:inline">{currentAction.label}</span>
              </Button>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button size="icon-sm" disabled={isActioning} className="rounded-l-none border-l border-l-white/20">
                    <ChevronDown className="h-4 w-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="w-80 bg-popover border-border p-2 shadow-md rounded-xl">
                  {(Object.entries(ACTION_CONFIGS) as [HeaderAction, ActionConfig][])
                    .filter(([key]) => key !== "merge_commit")
                    .map(([key, config]) => (
                      <DropdownMenuItem
                        key={key}
                        onSelect={() => { setSelectedAction(key); void handleAction(key); }}
                        className={cn(
                          "flex items-start gap-3 p-3 rounded-lg cursor-pointer group",
                          selectedAction === key && "dark:bg-white/[0.04] bg-black/[0.04]"
                        )}
                      >
                        <div className={cn(
                          "h-9 w-9 rounded-lg flex items-center justify-center shrink-0 border border-border group-hover:bg-purple-500/10 group-hover:border-purple-500/20 transition-colors",
                          selectedAction === key ? "bg-purple-500/10 border-purple-500/20" : "dark:bg-white/[0.04] bg-black/[0.04]"
                        )}>
                          <config.icon className={cn("h-4 w-4 transition-colors", selectedAction === key ? "text-purple-500" : "text-zinc-400 group-hover:text-purple-500")} />
                        </div>
                        <div className="flex flex-col gap-0.5">
                          <span className="text-[13px] font-semibold text-foreground/90 tracking-tight">{config.label}</span>
                          <span className="text-[11px] text-zinc-500 leading-tight">{config.description}</span>
                        </div>
                      </DropdownMenuItem>
                    ))}
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          )
        )}

        {prUrl && prUrl.state !== "MERGED" && allChecksPass && (
          <Button
            variant="ghost"
            onClick={handleMergePr}
            disabled={isMerging}
            title="Merge PR"
            className="border border-emerald-500/20 bg-emerald-500/10 text-emerald-600 hover:bg-emerald-500/20 dark:text-emerald-400 dark:hover:bg-emerald-500/20"
          >
            <GitMerge className="h-4 w-4" />
            <span className="hidden xl:inline">{isMerging ? "Merging…" : "Merge"}</span>
          </Button>
        )}

        {prUrl?.state === "MERGED" && (
          <Button
            variant="outline"
            onClick={() => openUrl(prUrl.url)}
            title={prUrl.mergedAt ? `Merged ${new Date(prUrl.mergedAt).toLocaleString()}` : "Merged"}
            className="text-emerald-600 dark:text-emerald-400"
          >
            <GitMerge className="h-4 w-4" />
            <span className="hidden xl:inline">Merged</span>
          </Button>
        )}

        {prUrl && prUrl.state !== "MERGED" && (
          <Button variant="outline" size="icon-sm" onClick={() => openUrl(prUrl.url)} title={t("agents.header.viewPr")}>
            <ExternalLink className="h-4 w-4" />
          </Button>
        )}
        {prUrl && prUrl.state !== "MERGED" && (
          <Button variant="outline" size="icon-sm" onClick={handleOpenSheet} title="Open PR">
            <Eye className="h-4 w-4" />
          </Button>
        )}
        {prUrl && prUrl.state !== "MERGED" && <PrCiToggle threadId={issue.id} />}
        <AgentPanelSelector />
      </div>
    </AppbarActions>
  );
}
