import { FileCode2, ChevronDown, Monitor, ChevronsUpDown, MoreVertical, Pencil, RotateCcw } from "lucide-react";
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

  const toggleCollapse = (filename: string) => {
    if (!selectedIssueId) return;
    setFileCollapsed(selectedIssueId, filename, !collapsedFiles[filename]);
  };

  const toggleAll = () => {
    if (diffViewTab === "files") {
      setIsFilesAllExpanded(!isFilesAllExpanded);
      return;
    }
    if (!selectedIssueId) return;

    const allCollapsed = files.length > 0 && files.every(f => collapsedFiles[f.filename]);
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

        <div className="flex items-center gap-6">
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
        <div className="flex-1 overflow-y-auto m-0 p-4 custom-scrollbar bg-zinc-50 dark:bg-background">
          <div className="flex flex-col gap-2 max-w-5xl mx-auto">
            {files.map((file) => (
              <Card key={file.filename} className="gap-0 border-zinc-200 dark:border-white/[0.05] shadow-none">
                <CardHeader
                  className="flex flex-row items-center justify-between p-2.5 cursor-pointer select-none transition-colors rounded-t-2xl"
                  onClick={() => toggleCollapse(file.filename)}
                >
                  <div className="flex items-center gap-3">
                    <div className={cn("transition-transform duration-200", collapsedFiles[file.filename] ? "-rotate-90" : "rotate-0")}>
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
                      <span className="text-emerald-500/70">+12</span>
                      <span className="text-red-500/70">-4</span>
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
                  "overflow-hidden transition-all duration-300",
                  collapsedFiles[file.filename] ? "max-h-0" : "max-h-none"
                )}>
                  <CardContent className="p-0 border-t border-zinc-100 dark:border-zinc-800 dark:bg-[#0A0A0A]/30 bg-zinc-50">
                    <div className="py-2 font-mono text-[10.5px] leading-relaxed overflow-x-auto custom-scrollbar">
                      {file.diff?.split('\n').map((line, i) => (
                        <div
                          key={i}
                          className={cn(
                            "px-4 py-0 whitespace-pre min-h-[16px] flex gap-4 transition-colors group/line",
                            line.startsWith('+') ? "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400/90" :
                              line.startsWith('-') ? "bg-red-500/10 text-red-600 dark:text-red-400/80" :
                                "text-zinc-400 dark:text-white/20"
                          )}
                        >
                          <span className="select-none opacity-20 w-8 text-right shrink-0 tabular-nums border-r border-zinc-100 dark:border-white/5 pr-4">{i + 1}</span>
                          <span className="flex-1 pl-1">{line}</span>
                        </div>
                      ))}
                    </div>
                  </CardContent>
                </div>
              </Card>
            ))}
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
