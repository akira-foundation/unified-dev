import { ChevronDown, ExternalLink, Monitor, ChevronsUpDown, RotateCcw } from "lucide-react";
import { OpenInEditorMenu } from "@/components/agents/open-in-editor-menu";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import type { FileChange } from "@/types/agents";
import { FileExplorer } from "./file-explorer";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { DiscardFileDialog } from "./discard-file-dialog";
import { PatchViewer } from "@/components/shared/patch-viewer";
import { useViewedFilesStore } from "@/stores/useViewedFilesStore";

interface DiffViewerProps {
  files: FileChange[];
  hideHeader?: boolean;
}

export function DiffViewer({ files, hideHeader }: DiffViewerProps) {
  const { t } = useI18n();
  const {
    isFilesAllExpanded,
    setIsFilesAllExpanded,
    diffViewTab,
    setDiffViewTab,
    selectedIssueId,
    collapsedFilesByThread,
    setFileCollapsed,
    repositoryGroups,
    loadFileChanges,
    diffSplitView,
  } = useAgentsStore();

  const [discardTarget, setDiscardTarget] = useState<string | null>(null);
  const [isDiscarding, setIsDiscarding] = useState(false);

  const storeKey = selectedIssueId ? `issue:${selectedIssueId}` : null;
  const { isViewed, toggleViewed: toggleViewedFile } = useViewedFilesStore();

  const selectedIssue = repositoryGroups
    .flatMap((g) => g.repositories.flatMap((r) => r.issues))
    .find((i) => i.id === selectedIssueId);

  const handleDiscard = async () => {
    if (!discardTarget || !selectedIssue) return;
    setIsDiscarding(true);
    try {
      await invoke("discard_file_changes", {
        workspacePath: selectedIssue.workspacePath,
        filename: discardTarget,
      });
      toast.success(t("agents.diffViewer.toast.discarded").replace("{filename}", discardTarget));
      setDiscardTarget(null);
      await loadFileChanges(selectedIssue.workspacePath);
    } catch (err) {
      toast.error(t("agents.diffViewer.toast.discardFailed").replace("{error}", String(err)));
    } finally {
      setIsDiscarding(false);
    }
  };

  const collapsedFiles = selectedIssueId ? (collapsedFilesByThread[selectedIssueId] ?? {}) : {};

  const isCollapsed = (filename: string) =>
    collapsedFiles[filename] ?? (storeKey ? isViewed(storeKey, filename) : false);

  const toggleCollapse = (filename: string) => {
    if (!selectedIssueId) return;
    setFileCollapsed(selectedIssueId, filename, !isCollapsed(filename));
  };

  const toggleAll = () => {
    if (diffViewTab === "files") {
      setIsFilesAllExpanded(!isFilesAllExpanded);
      return;
    }
    if (!selectedIssueId) return;

    const allCollapsed = files.length > 0 && files.every(f => isCollapsed(f.filename));
    files.forEach(f => setFileCollapsed(selectedIssueId, f.filename, !allCollapsed));
  };

  return (
    <div className="flex flex-col h-full bg-zinc-50 dark:bg-background border-l border-zinc-200 dark:border-white/[0.05]">
      {!hideHeader && (
      <div className="flex items-center justify-between px-4 h-11 bg-white dark:bg-background border-b border-zinc-200 dark:border-white/[0.05] shrink-0">
        <div className="flex items-center gap-5 h-full">
          <button
            onClick={() => setDiffViewTab("changes")}
            className={cn(
              "relative h-full flex items-center text-[11px] font-semibold uppercase tracking-wider transition-colors cursor-pointer",
              diffViewTab === "changes" ? "text-purple-600 dark:text-purple-400" : "text-zinc-400 dark:text-zinc-500 hover:text-zinc-600 dark:hover:text-zinc-300"
            )}
          >
            {t("agents.diffViewer.changes")}
            {diffViewTab === "changes" && <div className="absolute bottom-0 left-0 right-0 h-[1.5px] bg-purple-500" />}
          </button>
          <button
            onClick={() => setDiffViewTab("files")}
            className={cn(
              "relative h-full flex items-center text-[11px] font-semibold uppercase tracking-wider transition-colors cursor-pointer",
              diffViewTab === "files" ? "text-purple-600 dark:text-purple-400" : "text-zinc-400 dark:text-zinc-500 hover:text-zinc-600 dark:hover:text-zinc-300"
            )}
          >
            {t("agents.diffViewer.files")}
            {diffViewTab === "files" && <div className="absolute bottom-0 left-0 right-0 h-[1.5px] bg-purple-500" />}
          </button>
        </div>

        <div className="flex items-center gap-4">
          <button
            onClick={toggleAll}
            className="flex items-center gap-1.5 text-[10px] font-semibold text-zinc-400 dark:text-zinc-500 hover:text-zinc-600 dark:hover:text-zinc-300 transition-colors uppercase tracking-wider cursor-pointer"
          >
            <ChevronsUpDown className="h-3 w-3" />
            <span>{t("agents.diffViewer.toggleAll")}</span>
          </button>

          <div className="flex items-center gap-2">
            <span className="text-[10px] font-semibold text-zinc-400 dark:text-zinc-500 uppercase tracking-wider tabular-nums">
              {t("agents.diffViewer.filesCount").replace("{count}", String(files.length))}
            </span>
            <Monitor className="h-3 w-3 text-zinc-300 dark:text-zinc-600" />
          </div>
        </div>
      </div>
      )}

      {diffViewTab === "changes" ? (
        <div className="flex-1 overflow-y-auto custom-scrollbar">
          <div className="flex flex-col">
            {files.map((file) => {
              const viewed = !!(storeKey && isViewed(storeKey, file.filename));
              const collapsed = isCollapsed(file.filename);
              const lines = file.diff ? file.diff.split("\n") : [];
              const additions = lines.filter((l) => l.startsWith("+") && !l.startsWith("+++")).length;
              const deletions = lines.filter((l) => l.startsWith("-") && !l.startsWith("---")).length;
              return (
                <div key={file.filename} className={cn("transition-opacity", viewed && "opacity-50")}>
                  <div
                    onClick={() => toggleCollapse(file.filename)}
                    className="group flex h-9 cursor-pointer select-none items-center justify-between gap-2 border-b border-zinc-100 px-3 transition-colors hover:bg-zinc-50 dark:border-white/[0.04] dark:hover:bg-white/[0.02]"
                  >
                    <div className="flex min-w-0 items-center gap-1.5">
                      <span className="truncate text-[13px] text-foreground/85">{file.filename}</span>
                      {!viewed && (
                        <span
                          role="button"
                          aria-label="mark viewed"
                          onClick={(e) => {
                            e.stopPropagation();
                            if (!storeKey) return;
                            toggleViewedFile(storeKey, file.filename);
                            if (selectedIssueId) setFileCollapsed(selectedIssueId, file.filename, true);
                          }}
                          className="h-1.5 w-1.5 shrink-0 cursor-pointer rounded-full bg-blue-500 transition-transform hover:scale-125"
                        />
                      )}
                    </div>
                    <div className="flex shrink-0 items-center gap-2">
                      {file.diff != null && (
                        <span className="flex items-center gap-1.5 font-mono text-[11px] font-semibold tabular-nums">
                          <span className="text-emerald-500">+{additions}</span>
                          <span className="text-red-500">-{deletions}</span>
                        </span>
                      )}
                      <OpenInEditorMenu
                        workspacePath={selectedIssue?.workspacePath}
                        filePath={file.filename}
                        trigger={
                          <button
                            onClick={(e) => e.stopPropagation()}
                            title={t("agents.fileEditor.openInEditor")}
                            className="flex h-6 w-6 items-center justify-center rounded text-zinc-400 transition-colors hover:text-foreground"
                          >
                            <ExternalLink className="h-3.5 w-3.5" />
                          </button>
                        }
                      />
                      <button
                        onClick={(e) => { e.stopPropagation(); setDiscardTarget(file.filename); }}
                        title={t("agents.diffViewer.discard")}
                        className="flex h-6 w-6 items-center justify-center rounded text-zinc-400 transition-colors hover:text-red-500"
                      >
                        <RotateCcw className="h-3.5 w-3.5" />
                      </button>
                      <ChevronDown className={cn("h-3.5 w-3.5 shrink-0 text-muted-foreground/40 transition-transform", collapsed && "-rotate-90")} />
                    </div>
                  </div>
                  {!collapsed && file.diff && (
                    <div className="border-b border-zinc-100 bg-zinc-50/40 dark:border-white/[0.04] dark:bg-white/[0.01]">
                      <PatchViewer patch={file.diff} splitView={diffSplitView} filename={file.filename} />
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      ) : (
        <div className="flex-1 overflow-hidden bg-background">
          <FileExplorer />
        </div>
      )}

      <DiscardFileDialog
        open={discardTarget !== null}
        onOpenChange={(open) => { if (!open) setDiscardTarget(null); }}
        onDiscard={handleDiscard}
        filename={discardTarget ?? ""}
        isDiscarding={isDiscarding}
      />
    </div>
  );
}
