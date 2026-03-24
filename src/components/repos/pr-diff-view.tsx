import { useState } from "react";
import { Check, ChevronDown, Columns2, FileCode, WrapText } from "lucide-react";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "../ui/collapsible";
import { Card, CardContent, CardTitle } from "../ui/card";
import { Skeleton } from "../ui/skeleton";
import { useI18n } from "../../i18n/i18n";
import { PatchViewer } from "../shared/patch-viewer";
import type { PrFileDto } from "../../types/organization";

function FileDiffCard({
  file,
  splitView,
  defaultOpen = false,
  viewed,
  onViewedChange,
}: {
  file: PrFileDto;
  splitView: boolean;
  defaultOpen?: boolean;
  viewed: boolean;
  onViewedChange: (viewed: boolean) => void;
}) {
  const { t } = useI18n();
  const [open, setOpen] = useState(defaultOpen);
  const [everOpened, setEverOpened] = useState(defaultOpen);

  const handleOpenChange = (next: boolean) => {
    setOpen(next);
    if (next) setEverOpened(true);
  };

  return (
    <Collapsible open={open} onOpenChange={handleOpenChange}>
      <Card className={`overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm transition-opacity ${viewed ? "opacity-60" : ""}`}>
        <CollapsibleTrigger className="w-full cursor-pointer" asChild>
          <div className="flex flex-row items-center gap-3 px-4 py-3 select-none">
            <div className={`h-7 w-7 flex items-center justify-center rounded-lg border shrink-0 transition-colors ${viewed ? "bg-emerald-500/10 text-emerald-500 border-emerald-500/20" : "bg-purple-500/10 text-purple-500 border-purple-500/10"}`}>
              {viewed ? <Check size={14} strokeWidth={2.5} /> : <FileCode size={14} strokeWidth={2} />}
            </div>
            <CardTitle className={`text-sm font-semibold leading-none flex-1 text-left font-mono truncate min-w-0 transition-colors ${viewed ? "text-zinc-400 dark:text-zinc-500" : "text-zinc-900 dark:text-white/95"}`}>
              {file.filename}
            </CardTitle>
            <div className="flex items-center gap-2 shrink-0">
              {file.additions > 0 && (
                <span className="text-xs font-medium tabular-nums text-emerald-600 dark:text-emerald-400">
                  +{file.additions}
                </span>
              )}
              {file.deletions > 0 && (
                <span className="text-xs font-medium tabular-nums text-red-500 dark:text-red-400">
                  -{file.deletions}
                </span>
              )}
              <button
                onClick={(e) => { e.stopPropagation(); onViewedChange(!viewed); }}
                className={`h-3.5 w-3.5 rounded-sm border flex items-center justify-center transition-colors cursor-pointer shrink-0 ${
                  viewed
                    ? "bg-emerald-500 border-emerald-500 text-white"
                    : "border-zinc-300 dark:border-zinc-600 bg-transparent"
                }`}
              >
                {viewed && <Check className="h-2.5 w-2.5" strokeWidth={3} />}
              </button>
            </div>
            <ChevronDown
              className={`h-3.5 w-3.5 text-zinc-400 transition-transform duration-200 shrink-0 ${open ? "rotate-180" : ""}`}
            />
          </div>
        </CollapsibleTrigger>
        <CollapsibleContent>
          <CardContent className="px-0 py-0 border-t border-zinc-100 dark:border-zinc-800 bg-zinc-50/50 dark:bg-zinc-900/30">
            {everOpened && (
              file.patch ? (
                <PatchViewer patch={file.patch} splitView={splitView} />
              ) : (
                <p className="px-4 py-3 text-sm text-zinc-400 dark:text-zinc-500 italic">
                  {t("components.prDiff.binary")}
                </p>
              )
            )}
          </CardContent>
        </CollapsibleContent>
      </Card>
    </Collapsible>
  );
}

export function PrDiffView({
  files,
  loading,
}: {
  files: PrFileDto[];
  loading: boolean;
}) {
  const { t } = useI18n();
  const [splitView, setSplitView] = useState(true);
  const [viewedFiles, setViewedFiles] = useState<Set<string>>(new Set());

  const toggleViewed = (filename: string, viewed: boolean) => {
    setViewedFiles((prev) => {
      const next = new Set(prev);
      if (viewed) next.add(filename);
      else next.delete(filename);
      return next;
    });
  };

  if (loading) {
    return (
      <div className="flex flex-col gap-3 p-3">
        <Skeleton className="h-12 w-full rounded-lg" />
        <Skeleton className="h-40 w-full rounded-lg" />
        <Skeleton className="h-12 w-full rounded-lg" />
        <Skeleton className="h-32 w-full rounded-lg" />
      </div>
    );
  }

  if (files.length === 0) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-sm text-zinc-400 dark:text-zinc-500 italic">
          {t("components.prDiff.noFiles")}
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3 p-3">
      {/* Toolbar */}
      <div className="flex items-center justify-between px-1">
        <div className="flex items-center gap-3">
          <p className="text-[10px] font-bold uppercase tracking-widest text-zinc-400 dark:text-zinc-500">
            {t("components.prDiff.filesCount").replace("{count}", String(files.length))}
          </p>
          {viewedFiles.size > 0 && (
            <p className="text-[10px] font-bold uppercase tracking-widest text-emerald-600 dark:text-emerald-400">
              {t("components.prDiff.viewedCount")
                .replace("{viewed}", String(viewedFiles.size))
                .replace("{total}", String(files.length))}
            </p>
          )}
        </div>
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

      {/* File cards */}
      {files.map((file, index) => (
        <FileDiffCard
          key={file.filename}
          file={file}
          splitView={splitView}
          defaultOpen={index === 0}
          viewed={viewedFiles.has(file.filename)}
          onViewedChange={(v) => toggleViewed(file.filename, v)}
        />
      ))}
    </div>
  );
}
