import { useState } from "react";
import { useIntersectionObserver } from "@uidotdev/usehooks";
import { Check, ChevronRight, Columns2, FileCode, WrapText } from "lucide-react";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "../ui/collapsible";
import { Skeleton } from "../ui/skeleton";
import { cn } from "../../lib/utils";
import { useI18n } from "../../i18n/i18n";
import { PatchViewer } from "../shared/patch-viewer";
import { useViewedFilesStore } from "../../stores/useViewedFilesStore";
import type { PrFileDto } from "../../types/organization";

function useIntersected(rootMargin = "200px") {
  const [sentinelRef, entry] = useIntersectionObserver({ rootMargin, threshold: 0 });
  const [intersected, setIntersectedOnce] = useState(false);
  if (entry?.isIntersecting && !intersected) setIntersectedOnce(true);
  return { ref: sentinelRef, intersected };
}

function FileDiffBlock({
  file,
  splitView,
  viewed,
  onViewedChange,
}: {
  file: PrFileDto;
  splitView: boolean;
  viewed: boolean;
  onViewedChange: (viewed: boolean) => void;
}) {
  const { t } = useI18n();
  const [open, setOpen] = useState(!viewed);
  const { ref: sentinelRef, intersected } = useIntersected("300px");

  const handleViewed = (e: React.MouseEvent) => {
    e.stopPropagation();
    const next = !viewed;
    onViewedChange(next);
    if (next) setOpen(false);
  };

  return (
    <Collapsible open={open} onOpenChange={setOpen}>
      <div className={cn(viewed && "opacity-60")}>
        <CollapsibleTrigger className="w-full cursor-pointer" asChild>
          <div className="flex items-center gap-2.5 rounded-md px-3 py-2.5 select-none transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.03]">
            <ChevronRight className={cn("h-3.5 w-3.5 shrink-0 text-zinc-400 transition-transform", open && "rotate-90")} />
            <FileCode className="h-3.5 w-3.5 shrink-0 text-zinc-400" />
            <span className="min-w-0 flex-1 truncate text-left font-mono text-[12px] text-zinc-700 dark:text-zinc-200">
              {file.filename}
            </span>
            {file.additions > 0 && (
              <span className="shrink-0 text-[11px] font-medium tabular-nums text-emerald-600 dark:text-emerald-400">+{file.additions}</span>
            )}
            {file.deletions > 0 && (
              <span className="shrink-0 text-[11px] font-medium tabular-nums text-red-500 dark:text-red-400">−{file.deletions}</span>
            )}
            <button
              onClick={handleViewed}
              title={t("components.prDiff.viewedCount").replace("{viewed}", viewed ? "1" : "0").replace("{total}", "1")}
              className={cn(
                "flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-sm border transition-colors",
                viewed ? "border-emerald-500 bg-emerald-500 text-white" : "border-zinc-300 dark:border-zinc-600",
              )}
            >
              {viewed && <Check className="h-2.5 w-2.5" strokeWidth={3} />}
            </button>
          </div>
        </CollapsibleTrigger>
        <CollapsibleContent>
          <div>
            <div ref={sentinelRef} />
            {intersected && (
              file.patch ? (
                <PatchViewer patch={file.patch} splitView={splitView} filename={file.filename} />
              ) : (
                <p className="px-3 pb-1.5 text-[12px] text-zinc-400 dark:text-zinc-500 italic">{t("components.prDiff.binary")}</p>
              )
            )}
          </div>
        </CollapsibleContent>
      </div>
    </Collapsible>
  );
}

export function PrDiffView({
  files,
  loading,
  prNumber,
}: {
  files: PrFileDto[];
  loading: boolean;
  prNumber: number;
}) {
  const { t } = useI18n();
  const [splitView, setSplitView] = useState(false);
  const storeKey = `pr:${prNumber}`;
  const { isViewed, setViewed } = useViewedFilesStore();

  const viewedCount = files.filter((f) => isViewed(storeKey, f.filename)).length;

  if (loading) {
    return (
      <div className="flex flex-col gap-2 p-3">
        <Skeleton className="h-9 w-full rounded-lg" />
        <Skeleton className="h-32 w-full rounded-lg" />
        <Skeleton className="h-9 w-full rounded-lg" />
      </div>
    );
  }

  if (files.length === 0) {
    return (
      <div className="flex h-full items-center justify-center">
        <p className="text-sm text-zinc-400 dark:text-zinc-500 italic">{t("components.prDiff.noFiles")}</p>
      </div>
    );
  }

  const toggleBtn = (active: boolean) =>
    cn(
      "flex items-center gap-1.5 rounded px-2 py-1 text-[11px] font-medium transition-colors cursor-pointer",
      active
        ? "bg-white text-zinc-900 shadow-sm dark:bg-zinc-800 dark:text-white"
        : "text-zinc-500 hover:text-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-300",
    );

  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center justify-between px-3 py-2">
        <div className="flex items-center gap-3 text-[10px] font-bold uppercase tracking-widest">
          <span className="text-zinc-400 dark:text-zinc-500">
            {t("components.prDiff.filesCount").replace("{count}", String(files.length))}
          </span>
          {viewedCount > 0 && (
            <span className="text-emerald-600 dark:text-emerald-400">
              {t("components.prDiff.viewedCount").replace("{viewed}", String(viewedCount)).replace("{total}", String(files.length))}
            </span>
          )}
        </div>
        <div className="flex items-center gap-1 rounded-md border border-zinc-200 bg-zinc-50 p-0.5 dark:border-zinc-700 dark:bg-zinc-900">
          <button onClick={() => setSplitView(false)} title={t("components.prDiff.unifiedView")} className={toggleBtn(!splitView)}>
            <WrapText className="h-3 w-3" />
            {t("components.prDiff.unifiedView")}
          </button>
          <button onClick={() => setSplitView(true)} title={t("components.prDiff.splitView")} className={toggleBtn(splitView)}>
            <Columns2 className="h-3 w-3" />
            {t("components.prDiff.splitView")}
          </button>
        </div>
      </div>

      {files.map((file) => (
        <FileDiffBlock
          key={file.filename}
          file={file}
          splitView={splitView}
          viewed={isViewed(storeKey, file.filename)}
          onViewedChange={(v) => setViewed(storeKey, file.filename, v)}
        />
      ))}
    </div>
  );
}
