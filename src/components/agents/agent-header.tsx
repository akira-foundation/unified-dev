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
import {
  ChevronDown,
  GitPullRequest,
  Monitor,
  CloudUpload,
  ExternalLink,
  GitCommitHorizontal,
} from "lucide-react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { toast } from "sonner";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useSettingsStore } from "@/stores/settings-store";
import { useI18n } from "@/i18n/i18n";

interface AgentHeaderProps {
  issue: AgentIssue;
}

type HeaderAction = "merge_local" | "merge_push" | "draft_pr" | "create_pr" | "merge_commit";

interface ActionConfig {
  label: string;
  description: string;
  icon: React.ElementType;
}

export function AgentHeader({ issue }: AgentHeaderProps) {
  const { t } = useI18n();
  const ACTION_CONFIGS: Record<HeaderAction, ActionConfig> = {
    merge_local: {
      label: t("agents.header.action.mergeLocal.label"),
      description: t("agents.header.action.mergeLocal.description"),
      icon: Monitor,
    },
    merge_push: {
      label: t("agents.header.action.mergePush.label"),
      description: t("agents.header.action.mergePush.description"),
      icon: CloudUpload,
    },
    draft_pr: {
      label: t("agents.header.action.draftPr.label"),
      description: t("agents.header.action.draftPr.description"),
      icon: GitPullRequest,
    },
    create_pr: {
      label: t("agents.header.action.createPr.label"),
      description: t("agents.header.action.createPr.description"),
      icon: GitPullRequest,
    },
    merge_commit: {
      label: t("agents.header.action.mergeCommit.label"),
      description: t("agents.header.action.mergeCommit.description"),
      icon: GitCommitHorizontal,
    },
  };
  const [selectedAction, setSelectedAction] = useState<HeaderAction>("draft_pr");
  const [isActioning, setIsActioning] = useState(false);
  const { fileChanges, sendMessage, selectedModelId, selectedModelByThread, prUrlByThread } = useAgentsStore();
  const { getPrompt } = useSettingsStore();

  const currentAction = ACTION_CONFIGS[selectedAction];

  // Effective model for this thread: per-thread override → global default.
  const effectiveModelId = selectedModelByThread[issue.id] ?? selectedModelId;

  // Whether a PR already exists for this thread.
  const prUrl = prUrlByThread[issue.id] ?? null;

  const handleAction = async () => {
    if (!effectiveModelId) {
      toast.error(t("agents.header.toast.noModel"));
      return;
    }

    setIsActioning(true);
    try {
      // When a PR exists, always run the merge_commit action regardless of selectedAction.
      const actionKey = prUrl ? "merge_commit" : selectedAction;
      const basePrompt = getPrompt(actionKey);
      const issueContext = `\n\nContext about this thread:\n- Thread title: ${issue.title}\n- Branch: ${issue.branchName}\n- Repository: ${issue.repoName}\n\nUse the thread title as the basis for the PR title and body. The PR title should clearly reflect what was done.`;
      const prompt = basePrompt + issueContext;
      await sendMessage(issue.id, prompt, effectiveModelId, true);
    } catch (err) {
      toast.error(`Failed to start action: ${err}`);
    } finally {
      setIsActioning(false);
    }
  };

  return (
    <header className="h-14 border-b border-border/30 flex items-center px-4 bg-background backdrop-blur-md justify-between shrink-0">
      {/* Title & Metadata */}
      <div className="flex items-center gap-1.5 min-w-0">
        <span className="text-[13px] font-medium tracking-tight text-foreground/40 truncate">
          {issue.repoName}
        </span>
        <span className="text-muted-foreground shrink-0">/</span>
        <span className="text-[13px] font-semibold tracking-tight text-foreground/80 truncate">
          {issue.title}
        </span>
      </div>

      {/* Actions */}
      <div className="flex items-center gap-3">
        {prUrl && (
          <Button
            variant="ghost"
            onClick={() => openUrl(prUrl.url)}
            className="h-8 px-3 text-[#A855F7] text-[12px] font-semibold gap-2 rounded-md hover:bg-[#A855F7]/10 border border-[#A855F7]/20 hover:border-[#A855F7]/40 transition-all cursor-pointer"
          >
            <ExternalLink className="h-3.5 w-3.5" />
            <span>{t("agents.header.viewPr")}</span>
          </Button>
        )}
        {fileChanges.length > 0 && (
          <div className="flex items-center dark:bg-[#0F0F0F] bg-secondary rounded-xl dark:border-white/5 border-border border shadow-2xl overflow-hidden transition-all duration-300">
            <Button
              variant="ghost"
              disabled={isActioning}
              onClick={handleAction}
              className="h-8 pl-4 pr-3 text-foreground/90 text-[12px] font-semibold gap-2.5 rounded-none hover:bg-transparent transition-all border-none cursor-pointer"
            >
              {prUrl ? (
                <>
                  <GitCommitHorizontal className="h-4 w-4 text-[#A855F7]" />
                  <span>{t("agents.header.pushChanges")}</span>
                </>
              ) : (
                <>
                  <currentAction.icon className="h-4 w-4 text-[#A855F7]" />
                  <span>{currentAction.label}</span>
                </>
              )}
            </Button>

            {!prUrl && (
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-9 rounded-none dark:hover:bg-white/5 hover:bg-black/5 text-zinc-400 hover:text-foreground transition-colors border-none cursor-pointer"
                  >
                    <ChevronDown className="h-4 w-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent
                  align="end"
                  className="w-80 dark:bg-[#0F0F0F] bg-popover dark:border-white/[0.05] border-border p-2 shadow-2xl rounded-2xl backdrop-blur-3xl animate-in fade-in zoom-in-95 duration-200"
                >
                  {(Object.entries(ACTION_CONFIGS) as [HeaderAction, ActionConfig][])
                    .filter(([key]) => key !== "merge_commit")
                    .map(([key, config]) => (
                      <DropdownMenuItem
                        key={key}
                        onSelect={() => setSelectedAction(key)}
                        className={cn(
                          "flex items-start gap-3.5 p-3.5 dark:focus:bg-white/[0.03] focus:bg-black/[0.03] rounded-xl cursor-pointer group transition-all duration-200",
                          selectedAction === key && "dark:bg-white/[0.02] bg-black/[0.02]"
                        )}
                      >
                        <div className={cn(
                          "h-9 w-9 rounded-lg dark:bg-white/5 bg-black/5 flex items-center justify-center shrink-0 dark:border-white/5 border-border border group-hover:bg-[#A855F7]/10 group-hover:border-[#A855F7]/20 transition-all duration-200",
                          selectedAction === key && "bg-[#A855F7]/10 border-[#A855F7]/20"
                        )}>
                          <config.icon className={cn(
                            "h-4 w-4 transition-colors",
                            selectedAction === key ? "text-[#A855F7]" : "text-zinc-400 group-hover:text-[#A855F7]"
                          )} />
                        </div>
                        <div className="flex flex-col gap-0.5">
                          <span className="text-[13px] font-semibold text-foreground/90 tracking-tight">{config.label}</span>
                          <span className="text-[11px] text-zinc-500 leading-tight">{config.description}</span>
                        </div>
                      </DropdownMenuItem>
                    ))}
                </DropdownMenuContent>
              </DropdownMenu>
            )}
          </div>
        )}

      </div>
    </header>
  );
}
