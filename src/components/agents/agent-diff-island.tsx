import { useEffect, useState } from "react";
import { Columns2, ExternalLink, FileCode2, GitBranch, Maximize2, Minimize2, TerminalSquare, WrapText, X } from "lucide-react";

import { cn } from "@/lib/utils";
import { DiffViewer } from "@/components/agents/diff-viewer";
import { FileEditor } from "@/components/agents/file-editor";
import { OpenInEditorMenu } from "@/components/agents/open-in-editor-menu";
import { TerminalPanel } from "@/components/agents/terminal-panel";
import { useAgentsStore } from "@/stores/useAgentsStore";
import type { FileChange } from "@/types/agents";

interface AgentDiffIslandProps {
  branchName: string;
  files: FileChange[];
  workspacePath: string;
  onClose: () => void;
}

export function AgentDiffIsland({ branchName, files, workspacePath, onClose }: AgentDiffIslandProps) {
  const diffViewTab = useAgentsStore((s) => s.diffViewTab);
  const diffSplitView = useAgentsStore((s) => s.diffSplitView);
  const setDiffSplitView = useAgentsStore((s) => s.setDiffSplitView);
  const selectedFilePath = useAgentsStore((s) => s.selectedFilePath);
  const setSelectedFilePath = useAgentsStore((s) => s.setSelectedFilePath);
  const islandPanel = useAgentsStore((s) => s.islandPanel);

  const isTerminal = islandPanel === "terminal";
  const showEditor = !isTerminal && !!selectedFilePath;
  const [fullscreen, setFullscreen] = useState(false);
  const [terminalMounted, setTerminalMounted] = useState(false);

  useEffect(() => {
    if (isTerminal) setTerminalMounted(true);
  }, [isTerminal]);

  return (
    <div
      className={cn(
        "flex h-full flex-col overflow-hidden border-l border-zinc-200 bg-white dark:border-white/[0.06] dark:bg-background",
        fullscreen ? "absolute inset-0 z-40 w-full border-l-0" : "w-[min(640px,46%)] shrink-0",
      )}
    >
      <div className="flex h-11 shrink-0 items-center justify-between gap-2 border-b border-zinc-200 px-3 dark:border-white/[0.06]">
        <div className="flex min-w-0 items-center gap-1.5 text-[12px] font-medium text-foreground/70">
          {isTerminal ? (
            <TerminalSquare className="h-3.5 w-3.5 shrink-0 text-purple-500" />
          ) : showEditor ? (
            <FileCode2 className="h-3.5 w-3.5 shrink-0 text-purple-500" />
          ) : (
            <GitBranch className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          )}
          <span className="truncate font-mono">{isTerminal ? "Terminal" : showEditor ? selectedFilePath : branchName}</span>
        </div>
        <div className="flex shrink-0 items-center gap-1.5">
          {!isTerminal && !showEditor && diffViewTab === "changes" && (
            <div className="flex items-center gap-0.5 rounded-md border border-zinc-200 bg-zinc-100 p-0.5 dark:border-white/[0.06] dark:bg-white/[0.04]">
              {([["unified", false, WrapText], ["split", true, Columns2]] as const).map(([key, split, Icon]) => (
                <button
                  key={key}
                  onClick={() => setDiffSplitView(split)}
                  className={cn(
                    "flex h-6 w-6 items-center justify-center rounded transition-colors",
                    diffSplitView === split ? "bg-white text-zinc-900 shadow-sm dark:bg-white/[0.1] dark:text-white" : "text-zinc-500 hover:text-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-200",
                  )}
                  title={key}
                >
                  <Icon className="h-3.5 w-3.5" />
                </button>
              ))}
            </div>
          )}
          {showEditor && selectedFilePath && (
            <OpenInEditorMenu
              workspacePath={workspacePath}
              filePath={selectedFilePath}
              trigger={
                <button
                  title="Open in editor"
                  className="flex h-6 w-6 items-center justify-center rounded-md text-zinc-400 transition-colors hover:bg-zinc-100 hover:text-foreground dark:hover:bg-white/[0.06]"
                >
                  <ExternalLink className="h-3.5 w-3.5" />
                </button>
              }
            />
          )}
          <button
            onClick={() => setFullscreen((f) => !f)}
            title={fullscreen ? "Exit fullscreen" : "Fullscreen"}
            className="flex h-6 w-6 items-center justify-center rounded-md text-zinc-400 transition-colors hover:bg-zinc-100 hover:text-foreground dark:hover:bg-white/[0.06]"
          >
            {fullscreen ? <Minimize2 className="h-3.5 w-3.5" /> : <Maximize2 className="h-3.5 w-3.5" />}
          </button>
          <button
            onClick={() => (showEditor ? setSelectedFilePath(null) : onClose())}
            className="flex h-6 w-6 items-center justify-center rounded-md text-zinc-400 transition-colors hover:bg-zinc-100 hover:text-foreground dark:hover:bg-white/[0.06]"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>
      <div className="min-h-0 flex-1 overflow-hidden">
        <div className={cn("h-full", (showEditor || isTerminal) && "hidden")}>
          <DiffViewer files={files} hideHeader />
        </div>
        {showEditor && (
          <div className="h-full">
            <FileEditor hideHeader />
          </div>
        )}
        {terminalMounted && (
          <div className={cn("h-full", !isTerminal && "hidden")}>
            <TerminalPanel cwd={workspacePath} onMinimize={onClose} onClose={onClose} />
          </div>
        )}
      </div>
    </div>
  );
}
