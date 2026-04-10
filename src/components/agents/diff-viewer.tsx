import { FileCode2, ChevronDown, Monitor, ChevronsUpDown, MoreVertical, Pencil, RotateCcw, Columns2, WrapText, Check } from "lucide-react";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import type { FileChange } from "@/types/agents";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { FileExplorer } from "./file-explorer";
import { useAgentsStore } from "@/stores/useAgentsStore";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";
import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { DiscardFileDialog } from "./discard-file-dialog";
import { PatchViewer } from "@/components/shared/patch-viewer";
import { useViewedFilesStore } from "@/stores/useViewedFilesStore";

interface DiffViewerProps {
  files: FileChange[];
}

export function DiffViewer({ files }: DiffViewerProps) {
  const { t } = useI18n();
  const {
    isFilesAllExpanded,
    setIsFilesAllExpanded,
    diffViewTab,
    setDiffViewTab,
    selectedIssueId,
    collapsedFilesByThread,
    setFileCollapsed,
    setSelectedFilePath,
    repositoryGroups,
    loadFileChanges,
  } = useAgentsStore();

  const [discardTarget, setDiscardTarget] = useState<string | null>(null);
  const [isDiscarding, setIsDiscarding] = useState(false);
  const [splitView, setSplitView] = useState(false);

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
      {/* Header */}
      <div className="flex items-center justify-between px-4 h-14 bg-white dark:bg-background border-b border-zinc-200 dark:border-white/[0.03] shrink-0">
        <div className="flex items-center gap-6 h-full">
          <button
            onClick={() => setDiffViewTab("changes")}
            className={cn(
              "relative h-full flex items-center text-[9px] font-black uppercase tracking-[0.15em] transition-all cursor-pointer",
              diffViewTab === "changes" ? "text-purple-600 dark:text-purple-400" : "text-zinc-400 dark:text-zinc-500 hover:text-zinc-600 dark:hover:text-zinc-300"
            )}
          >
            {t("agents.diffViewer.changes")}
            {diffViewTab === "changes" && <div className="absolute bottom-0 left-0 right-0 h-[1.5px] bg-purple-500 shadow-[0_0_10px_rgba(168,85,247,0.5)]" />}
          </button>
          <button
            onClick={() => setDiffViewTab("files")}
            className={cn(
              "relative h-full flex items-center text-[9px] font-black uppercase tracking-[0.15em] transition-all cursor-pointer",
              diffViewTab === "files" ? "text-purple-600 dark:text-purple-400" : "text-zinc-400 dark:text-zinc-500 hover:text-zinc-600 dark:hover:text-zinc-300"
            )}
          >
            {t("agents.diffViewer.files")}
            {diffViewTab === "files" && <div className="absolute bottom-0 left-0 right-0 h-[1.5px] bg-purple-500 shadow-[0_0_10px_rgba(168,85,247,0.5)]" />}
          </button>
        </div>

        <div className="flex items-center gap-4">
          <button
            onClick={toggleAll}
            className="flex items-center gap-1.5 text-[8px] font-black text-zinc-400 dark:text-zinc-500 hover:text-zinc-600 dark:hover:text-zinc-300 transition-colors uppercase tracking-widest cursor-pointer"
          >
            <ChevronsUpDown className="h-2.5 w-2.5" />
            <span>{t("agents.diffViewer.toggleAll")}</span>
          </button>

          <div className="flex items-center gap-3">
            <span className="text-[9px] font-black text-zinc-300 dark:text-zinc-600 uppercase tracking-widest tabular-nums">
              {t("agents.diffViewer.filesCount").replace("{count}", String(files.length))}
            </span>
            <Monitor className="h-3 w-3 text-zinc-300 dark:text-zinc-600" />
          </div>
        </div>
      </div>

      {diffViewTab === "changes" ? (
        <>
          {/* Toolbar */}
          <div className="flex items-center justify-end px-4 py-2 shrink-0">
            <div className="flex items-center gap-1 rounded-md border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-900 p-0.5">
              <button
                onClick={() => setSplitView(false)}
                title={t("components.prDiff.unifiedView")}
                className={`flex items-center gap-1.5 px-2.5 py-1 rounded text-xs font-medium transition-colors cursor-pointer ${
                  !splitView
                    ? "bg-white dark:bg-zinc-800 text-zinc-900 dark:text-white shadow-sm"
                    : "text-zinc-500 dark:text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-300"
                }`}
              >
                <WrapText className="h-3 w-3" />
                {t("components.prDiff.unifiedView")}
              </button>
              <button
                onClick={() => setSplitView(true)}
                title={t("components.prDiff.splitView")}
                className={`flex items-center gap-1.5 px-2.5 py-1 rounded text-xs font-medium transition-colors cursor-pointer ${
                  splitView
                    ? "bg-white dark:bg-zinc-800 text-zinc-900 dark:text-white shadow-sm"
                    : "text-zinc-500 dark:text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-300"
                }`}
              >
                <Columns2 className="h-3 w-3" />
                {t("components.prDiff.splitView")}
              </button>
            </div>
          </div>
          <div className="flex-1 overflow-y-auto m-0 p-4 custom-scrollbar">
          <div className="flex flex-col gap-2 max-w-5xl mx-auto">
            {files.map((file) => (
              <Card key={file.filename} className={cn("gap-0 border-zinc-200 dark:border-white/[0.05] shadow-none transition-opacity", storeKey && isViewed(storeKey, file.filename) && "opacity-60")}>
                <CardHeader
                  className="flex flex-row items-center justify-between p-2.5 cursor-pointer select-none transition-colors rounded-t-2xl"
                  onClick={() => toggleCollapse(file.filename)}
                >
                  <div className="flex items-center gap-3">
                    <div className={cn("transition-transform duration-200", isCollapsed(file.filename) ? "-rotate-90" : "rotate-0")}>
                      <ChevronDown className="h-4 w-4 text-zinc-400 dark:text-muted-foreground/40" />
                    </div>
                    <div className="h-6 w-6 rounded-md flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-purple-500/10 text-purple-600 dark:text-purple-400">
                      <FileCode2 className="h-3 w-3" />
                    </div>
                    <div className="flex flex-col">
                      <CardTitle className="text-sm font-bold tracking-tight">
                        {file.filename}
                      </CardTitle>
                      <CardDescription className="text-[9px] uppercase tracking-wider font-black opacity-40 leading-none">
                        {file.status}
                      </CardDescription>
                    </div>
                  </div>

                  <div className="flex items-center gap-2">
                    <div className="flex items-center gap-3 text-[10px] font-mono font-bold tracking-tight">
                      {file.diff != null && (() => {
                        const lines = file.diff.split("\n");
                        const additions = lines.filter((l) => l.startsWith("+") && !l.startsWith("+++")).length;
                        const deletions = lines.filter((l) => l.startsWith("-") && !l.startsWith("---")).length;
                        return (
                          <>
                            <span className="text-emerald-500/70">+{additions}</span>
                            <span className="text-red-500/70">-{deletions}</span>
                          </>
                        );
                      })()}
                    </div>

                    <div
                      onClick={(e) => {
                        e.stopPropagation();
                        if (storeKey) {
                          const wasViewed = isViewed(storeKey, file.filename);
                          toggleViewedFile(storeKey, file.filename);
                          if (!wasViewed && selectedIssueId) {
                            setFileCollapsed(selectedIssueId, file.filename, true);
                          }
                        }
                      }}
                      className={cn(
                        "h-3.5 w-3.5 rounded-sm border flex items-center justify-center transition-colors cursor-pointer shrink-0",
                        storeKey && isViewed(storeKey, file.filename)
                          ? "bg-emerald-500 border-emerald-500 text-white"
                          : "border-zinc-300 dark:border-zinc-600 bg-transparent"
                      )}
                    >
                      {storeKey && isViewed(storeKey, file.filename) && <Check className="h-2.5 w-2.5" strokeWidth={3} />}
                    </div>

                    <DropdownMenu>
                      <DropdownMenuTrigger asChild onClick={(e) => e.stopPropagation()}>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-6 w-6 rounded-md text-zinc-400 hover:text-foreground dark:hover:bg-white/5 hover:bg-black/5 border-none shrink-0"
                        >
                          <MoreVertical className="h-3.5 w-3.5" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent
                        align="end"
                        className="dark:bg-[#0D0D0D] bg-popover dark:border-white/[0.05] border-border p-1 shadow-2xl rounded-md backdrop-blur-3xl"
                        onClick={(e) => e.stopPropagation()}
                      >
                        <DropdownMenuItem
                          className="flex items-center gap-2.5 px-3 py-2 text-[11px] font-medium text-foreground/70 dark:focus:bg-white/5 focus:bg-black/5 rounded-md cursor-pointer"
                          onSelect={() => setSelectedFilePath(file.filename)}
                        >
                          <Pencil className="h-3.5 w-3.5 text-zinc-400" />
                          <span>{t("agents.diffViewer.edit")}</span>
                        </DropdownMenuItem>
                        <DropdownMenuItem
                          className="flex items-center gap-2.5 px-3 py-2 text-[11px] font-medium text-foreground/70 dark:focus:bg-white/5 focus:bg-black/5 rounded-md cursor-pointer"
                          onSelect={() => setDiscardTarget(file.filename)}
                        >
                          <RotateCcw className="h-3.5 w-3.5 text-zinc-400" />
                          <span>{t("agents.diffViewer.discard")}</span>
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </div>
                </CardHeader>

                <div className={cn(
                  "transition-all duration-300",
                  isCollapsed(file.filename) ? "max-h-0 overflow-hidden" : "max-h-none overflow-visible"
                )}>
                  <CardContent className="p-0 border-t border-zinc-100 dark:border-zinc-800">
                    {file.diff && <PatchViewer patch={file.diff} splitView={splitView} filename={file.filename} />}
                  </CardContent>
                </div>
              </Card>
            ))}
          </div>
        </div>
        </>
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
