import { useState } from "react";
import { Badge } from "@/components/ui/badge";
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
  MoreVertical,
  Trash2,
  Octagon,
} from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { RemoveThreadDialog } from "./remove-thread-dialog";

interface AgentHeaderProps {
  issue: AgentIssue;
}

type HeaderAction = "merge_local" | "merge_push" | "draft_pr" | "create_pr";

interface ActionConfig {
  label: string;
  description: string;
  icon: React.ElementType;
}

const ACTION_CONFIGS: Record<HeaderAction, ActionConfig> = {
  merge_local: {
    label: "Merge locally",
    description: "Sync changes with your local base branch",
    icon: Monitor,
  },
  merge_push: {
    label: "Merge and push",
    description: "Update local and sync with remote repository",
    icon: CloudUpload,
  },
  draft_pr: {
    label: "Draft PR",
    description: "Initialize a new draft PR on GitHub",
    icon: GitPullRequest,
  },
  create_pr: {
    label: "Create pull request",
    description: "Initialize a new PR directly on GitHub",
    icon: GitPullRequest,
  },
};

export function AgentHeader({ issue }: AgentHeaderProps) {
  const [selectedAction, setSelectedAction] = useState<HeaderAction>("draft_pr");
  const [showRemoveDialog, setShowRemoveDialog] = useState(false);
  const [isRemoving, setIsRemoving] = useState(false);
  const [isActioning, setIsActioning] = useState(false);
  const { removeThread, setSelectedIssueId, fileChanges } = useAgentsStore();

  const currentAction = ACTION_CONFIGS[selectedAction];

  const handleAction = async () => {
    if (selectedAction === "draft_pr" || selectedAction === "create_pr") {
      setIsActioning(true);
      try {
        const prUrl = await invoke<string>("create_draft_pr", {
          workspacePath: issue.workspacePath,
          branchName: issue.branchName,
          title: issue.title,
        });
        toast.success("Pull request created", { description: prUrl });
      } catch (err) {
        toast.error(`Failed to create PR: ${err}`);
      } finally {
        setIsActioning(false);
      }
    }
  };

  const handleRemoveThread = async () => {
    try {
      setIsRemoving(true);
      await invoke("delete_thread", { threadId: issue.id });
      removeThread(issue.repoId, issue.id);
      setSelectedIssueId(null);
      toast.success("Thread removed");
      setShowRemoveDialog(false);
    } catch (error) {
      toast.error(`Failed to remove thread: ${error}`);
    } finally {
      setIsRemoving(false);
    }
  };

  return (
    <header className="h-14 border-b border-white/[0.03] flex items-center px-4 bg-background backdrop-blur-md justify-between shrink-0">
      {/* Title & Metadata */}
      <div className="flex flex-col gap-0.5 min-w-0">
        <div className="flex items-center gap-3">
          <h1 className="text-[14px] font-semibold tracking-tight text-white/90 truncate max-w-xl">
            {issue.title}
          </h1>
          <Badge
            variant="outline"
            className={cn(
              "text-[9px] font-medium px-2 py-0 h-4 min-h-0 border-none transition-all",
              issue.status === "Running" ? "bg-blue-500/10 text-blue-400" :
                issue.status === "Completed" ? "bg-emerald-500/10 text-emerald-400" :
                  "bg-zinc-800 text-zinc-400"
            )}
          >
            {issue.status}
          </Badge>
        </div>
        <div className="flex items-center gap-2 text-[11px] text-muted-foreground/40 font-medium">
          <span className="hover:text-zinc-400 transition-colors cursor-default">{issue.repoName}</span>
          <span className="text-zinc-800">/</span>
          <span className="font-mono text-[10px] hover:text-zinc-400 transition-colors cursor-default">{issue.branchName}</span>
        </div>
      </div>

      {/* Actions */}
      <div className="flex items-center gap-3">
        {fileChanges.length > 0 && (
          <div className="flex items-center bg-[#0F0F0F] rounded-xl border border-white/5 shadow-2xl overflow-hidden transition-all duration-300">
            <Button
              variant="ghost"
              disabled={isActioning}
              onClick={handleAction}
              className="h-8 pl-4 pr-3 text-white/90 text-[12px] font-semibold gap-2.5 rounded-none hover:bg-transparent transition-all border-none"
            >
              <currentAction.icon className="h-4 w-4 text-[#A855F7]" />
              <span>{currentAction.label}</span>
            </Button>

            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-8 w-9 rounded-none hover:bg-white/5 text-zinc-400 hover:text-white transition-colors border-none"
                >
                  <ChevronDown className="h-4 w-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent
                align="end"
                className="w-80 bg-[#0F0F0F] border-white/[0.05] p-2 shadow-2xl rounded-2xl backdrop-blur-3xl animate-in fade-in zoom-in-95 duration-200"
              >
                {(Object.entries(ACTION_CONFIGS) as [HeaderAction, ActionConfig][]).map(([key, config]) => (
                  <DropdownMenuItem
                    key={key}
                    onSelect={() => setSelectedAction(key)}
                    className={cn(
                      "flex items-start gap-3.5 p-3.5 focus:bg-white/[0.03] rounded-xl cursor-pointer group transition-all duration-200",
                      selectedAction === key && "bg-white/[0.02]"
                    )}
                  >
                    <div className={cn(
                      "h-9 w-9 rounded-lg bg-white/5 flex items-center justify-center shrink-0 border border-white/5 group-hover:bg-[#A855F7]/10 group-hover:border-[#A855F7]/20 transition-all duration-200",
                      selectedAction === key && "bg-[#A855F7]/10 border-[#A855F7]/20"
                    )}>
                      <config.icon className={cn(
                        "h-4 w-4 transition-colors",
                        selectedAction === key ? "text-[#A855F7]" : "text-zinc-400 group-hover:text-[#A855F7]"
                      )} />
                    </div>
                    <div className="flex flex-col gap-0.5">
                      <span className="text-[13px] font-semibold text-white/90 tracking-tight">{config.label}</span>
                      <span className="text-[11px] text-zinc-500 leading-tight">{config.description}</span>
                    </div>
                  </DropdownMenuItem>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        )}

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="ghost"
              size="icon"
              className="h-8 w-8 rounded-lg hover:bg-white/5 text-muted-foreground/40 hover:text-white transition-colors border-none"
            >
              <MoreVertical className="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent
            align="end"
            className="w-56 bg-background border-white/[0.05] p-1 shadow-2xl rounded-md backdrop-blur-3xl"
          >
            <DropdownMenuItem className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-white/5 rounded-md cursor-pointer transition-all">
              <Octagon className="h-4 w-4 text-white/40 group-hover:text-white transition-colors" />
              <span>Stop agent</span>
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={() => setShowRemoveDialog(true)}
              className="flex items-center gap-3 text-[11px] font-bold uppercase tracking-wider p-3 focus:bg-red-500/10 text-red-500 rounded-md cursor-pointer transition-all"
            >
              <Trash2 className="h-4 w-4" />
              <span>Remove</span>
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      <RemoveThreadDialog
        open={showRemoveDialog}
        onOpenChange={setShowRemoveDialog}
        onRemove={handleRemoveThread}
        threadTitle={issue.title}
        isRemoving={isRemoving}
      />
    </header>
  );
}
