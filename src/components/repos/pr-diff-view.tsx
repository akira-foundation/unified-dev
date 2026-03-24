import { useEffect, useState } from "react";
import ReactDiffViewer from "react-diff-viewer-continued";
import { Check, ChevronDown, Columns2, FileCode, WrapText } from "lucide-react";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "../ui/collapsible";
import { Card, CardContent, CardTitle } from "../ui/card";
import { Skeleton } from "../ui/skeleton";
import { useI18n } from "../../i18n/i18n";
import type { PrFileDto } from "../../types/organization";

function useDarkMode(): boolean {
  const [isDark, setIsDark] = useState(() =>
    document.documentElement.classList.contains("dark"),
  );

  useEffect(() => {
    const observer = new MutationObserver(() => {
      setIsDark(document.documentElement.classList.contains("dark"));
    });
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class"],
    });
    return () => observer.disconnect();
  }, []);

  return isDark;
}

function parsePatch(patch: string): { oldValue: string; newValue: string } {
  const lines = patch.split("\n");
  const oldLines: string[] = [];
  const newLines: string[] = [];

  for (const line of lines) {
    if (line.startsWith("@@") || line.startsWith("\\ No newline")) {
      continue;
    } else if (line.startsWith("-")) {
      oldLines.push(line.slice(1));
    } else if (line.startsWith("+")) {
      newLines.push(line.slice(1));
    } else {
      const context = line.startsWith(" ") ? line.slice(1) : line;
      oldLines.push(context);
      newLines.push(context);
    }
  }

  return { oldValue: oldLines.join("\n"), newValue: newLines.join("\n") };
}

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
  const isDark = useDarkMode();

  const parsed = file.patch ? parsePatch(file.patch) : null;

  const handleOpenChange = (next: boolean) => {
    setOpen(next);
    if (next) setEverOpened(true);
  };

  const lightStyles = {
    variables: {
      light: {
        diffViewerBackground: "transparent",
        diffViewerTitleBackground: "transparent",
        addedBackground: "#dcfce7",
        addedColor: "#18181b",
        removedBackground: "#fee2e2",
        removedColor: "#18181b",
        wordAddedBackground: "#86efac",
        wordRemovedBackground: "#fca5a5",
        gutterBackground: "#f4f4f5",
        gutterBackgroundDark: "#e4e4e7",
        gutterColor: "#a1a1aa",
        addedGutterBackground: "#dcfce7",
        removedGutterBackground: "#fee2e2",
        codeFoldBackground: "#f4f4f5",
        codeFoldContentColor: "#71717a",
        emptyLineBackground: "transparent",
        diffViewerColor: "#18181b",
        codeFoldGutterBackground: "#e4e4e7",
      },
    },
  };

  const darkStyles = {
    variables: {
      dark: {
        diffViewerBackground: "transparent",
        diffViewerTitleBackground: "transparent",
        addedBackground: "#14532d40",
        addedColor: "#e4e4e7",
        removedBackground: "#7f1d1d40",
        removedColor: "#e4e4e7",
        wordAddedBackground: "#166534",
        wordRemovedBackground: "#991b1b",
        gutterBackground: "#18181b",
        gutterBackgroundDark: "#09090b",
        gutterColor: "#52525b",
        addedGutterBackground: "#14532d40",
        removedGutterBackground: "#7f1d1d40",
        codeFoldBackground: "#18181b",
        codeFoldContentColor: "#71717a",
        emptyLineBackground: "transparent",
        diffViewerColor: "#e4e4e7",
        codeFoldGutterBackground: "#27272a",
      },
    },
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
                className={`flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-bold uppercase tracking-widest border transition-colors cursor-pointer ${
                  viewed
                    ? "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border-emerald-500/20 hover:bg-emerald-500/20"
                    : "bg-transparent text-zinc-400 dark:text-zinc-500 border-zinc-200 dark:border-zinc-700 hover:border-zinc-300 dark:hover:border-zinc-600 hover:text-zinc-600 dark:hover:text-zinc-400"
                }`}
              >
                {viewed && <Check className="h-2.5 w-2.5 shrink-0" />}
                {t("components.prDiff.markViewed")}
              </button>
            </div>
            <ChevronDown
              className={`h-3.5 w-3.5 text-zinc-400 transition-transform duration-200 shrink-0 ${open ? "rotate-180" : ""}`}
            />
          </div>
        </CollapsibleTrigger>
        <CollapsibleContent>
          <CardContent className="px-0 py-0 overflow-x-auto">
            {everOpened && (
              parsed ? (
                <div className="text-xs [&_table]:w-full [&_td]:text-xs [&_pre]:text-xs [&_pre]:leading-5 [&_table]:border-collapse [&_td:nth-child(3)]:border-l [&_td:nth-child(3)]:border-zinc-200 dark:[&_td:nth-child(3)]:border-zinc-700">
                  <ReactDiffViewer
                    oldValue={parsed.oldValue}
                    newValue={parsed.newValue}
                    splitView={splitView}
                    hideLineNumbers={false}
                    showDiffOnly={true}
                    useDarkTheme={isDark}
                    styles={isDark ? darkStyles : lightStyles}
                  />
                </div>
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
