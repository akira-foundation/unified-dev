import { useMemo } from "react";
import { cn } from "../../lib/utils";
import { getLanguageFromFilename, highlightLine } from "../../lib/highlight";
import { diffWords, type WordSeg } from "../../lib/word-diff";
import { useSettingsStore } from "../../stores/settings-store";

export interface PatchLine {
  type: "added" | "removed" | "context" | "hunk" | "meta";
  content: string;
  oldLineNo: number | null;
  newLineNo: number | null;
}

export function parsePatchLines(patch: string): PatchLine[] {
  const lines = patch.split("\n");
  const result: PatchLine[] = [];
  let oldLine = 0;
  let newLine = 0;

  for (const raw of lines) {
    if (raw.startsWith("diff ") || raw.startsWith("index ") || raw.startsWith("--- ") || raw.startsWith("+++ ")) {
      continue;
    } else if (raw.startsWith("@@")) {
      const match = raw.match(/@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
      if (match) {
        oldLine = parseInt(match[1], 10);
        newLine = parseInt(match[2], 10);
      }
      result.push({ type: "hunk", content: raw, oldLineNo: null, newLineNo: null });
    } else if (raw.startsWith("+")) {
      result.push({ type: "added", content: raw.slice(1), oldLineNo: null, newLineNo: newLine });
      newLine++;
    } else if (raw.startsWith("-")) {
      result.push({ type: "removed", content: raw.slice(1), oldLineNo: oldLine, newLineNo: null });
      oldLine++;
    } else if (raw.startsWith("\\ No newline")) {
      result.push({ type: "meta", content: raw, oldLineNo: null, newLineNo: null });
    } else {
      const content = raw.startsWith(" ") ? raw.slice(1) : raw;
      result.push({ type: "context", content, oldLineNo: oldLine, newLineNo: newLine });
      oldLine++;
      newLine++;
    }
  }

  return result;
}

function computeWordDiffs(lines: PatchLine[]): Map<number, WordSeg[]> {
  const map = new Map<number, WordSeg[]>();
  let i = 0;
  while (i < lines.length) {
    if (lines[i].type === "removed") {
      let r = i;
      while (r < lines.length && lines[r].type === "removed") r++;
      let a = r;
      while (a < lines.length && lines[a].type === "added") a++;
      const pairs = Math.min(r - i, a - r);
      for (let k = 0; k < pairs; k++) {
        const { oldSegs, newSegs } = diffWords(lines[i + k].content, lines[r + k].content);
        map.set(i + k, oldSegs);
        map.set(r + k, newSegs);
      }
      i = a;
    } else {
      i++;
    }
  }
  return map;
}

const ROW = "font-mono text-[11px] leading-[18px]";
const GUTTER = "select-none shrink-0 text-right tabular-nums text-zinc-400 dark:text-zinc-600 border-r border-zinc-200/70 dark:border-zinc-800/70";
const CONTENT = "flex-1 whitespace-pre-wrap break-all pl-2 pr-3";

function wordSpans(segs: WordSeg[], added: boolean) {
  const hl = added ? "bg-emerald-500/30 dark:bg-emerald-500/30" : "bg-red-500/30 dark:bg-red-500/35";
  return segs.map((s, k) =>
    s.changed ? <span key={k} className={cn("rounded-[2px]", hl)}>{s.text}</span> : <span key={k}>{s.text}</span>,
  );
}

export function PatchViewer({
  patch,
  splitView = false,
  filename,
}: {
  patch: string;
  splitView?: boolean;
  filename?: string;
}) {
  const syntaxHighlight = useSettingsStore((s) => s.diffSyntaxHighlight);
  const lines = parsePatchLines(patch);
  const language = syntaxHighlight && filename ? getLanguageFromFilename(filename) : null;
  const wordDiffs = useMemo(() => computeWordDiffs(lines), [patch]);

  const highlighted = useMemo(() => {
    if (!language) return null;
    return lines.map((l) =>
      l.type === "context" || l.type === "added" || l.type === "removed"
        ? highlightLine(l.content, language)
        : null,
    );
  }, [patch, language]);

  const renderContent = (line: PatchLine | null, idx: number) => {
    if (!line) return <span className={CONTENT} />;
    const segs = wordDiffs.get(idx);
    if (segs) return <span className={CONTENT}>{wordSpans(segs, line.type === "added")}</span>;
    const html = highlighted?.[idx] ?? null;
    if (html !== null) return <span className={cn(CONTENT, "hljs")} dangerouslySetInnerHTML={{ __html: html }} />;
    return <span className={CONTENT}>{line.content}</span>;
  };

  if (splitView) {
    type SplitRow =
      | { kind: "hunk"; content: string }
      | { kind: "meta"; content: string }
      | { kind: "pair"; left: PatchLine | null; right: PatchLine | null; leftIdx: number; rightIdx: number };

    const rows: SplitRow[] = [];
    let i = 0;
    while (i < lines.length) {
      const l = lines[i];
      if (l.type === "hunk") { rows.push({ kind: "hunk", content: l.content }); i++; continue; }
      if (l.type === "meta") { rows.push({ kind: "meta", content: l.content }); i++; continue; }
      if (l.type === "removed") {
        const next = lines[i + 1];
        if (next?.type === "added") { rows.push({ kind: "pair", left: l, right: next, leftIdx: i, rightIdx: i + 1 }); i += 2; }
        else { rows.push({ kind: "pair", left: l, right: null, leftIdx: i, rightIdx: -1 }); i++; }
        continue;
      }
      if (l.type === "added") { rows.push({ kind: "pair", left: null, right: l, leftIdx: -1, rightIdx: i }); i++; continue; }
      rows.push({ kind: "pair", left: l, right: l, leftIdx: i, rightIdx: i });
      i++;
    }

    const cell = (line: PatchLine | null) => cn(
      "flex-1 flex min-w-0 border-l-2 border-l-transparent",
      !line && "bg-zinc-100/40 dark:bg-white/[0.015]",
      line?.type === "added" && "border-l-emerald-500 bg-emerald-500/12 dark:bg-emerald-500/[0.14]",
      line?.type === "removed" && "border-l-red-500 bg-red-500/12 dark:bg-red-500/[0.14]",
    );
    const marker = (line: PatchLine | null) => cn(
      "select-none w-4 shrink-0 text-center",
      line?.type === "added" && "text-emerald-600 dark:text-emerald-400",
      line?.type === "removed" && "text-red-600 dark:text-red-400",
      (!line || line.type === "context") && "text-transparent",
    );

    return (
      <div className={ROW}>
        {rows.map((row, idx) => {
          if (row.kind === "hunk") {
            return (
              <div key={idx} className="flex bg-sky-500/[0.07] text-sky-700/80 dark:bg-sky-500/10 dark:text-sky-300/70">
                <span className="w-9 shrink-0 border-r border-zinc-200/70 dark:border-zinc-800/70" />
                <span className="flex-1 pl-2">{row.content}</span>
              </div>
            );
          }
          if (row.kind === "meta") {
            return <div key={idx} className="flex px-2 text-zinc-400 dark:text-zinc-600 italic">{row.content}</div>;
          }
          const { left, right, leftIdx, rightIdx } = row;
          return (
            <div key={idx} className="flex">
              <div className={cell(left)}>
                <span className={cn(GUTTER, "w-9 pr-1.5")}>{left?.oldLineNo ?? ""}</span>
                <span className={marker(left)}>{left?.type === "removed" ? "−" : ""}</span>
                {renderContent(left, leftIdx)}
              </div>
              <div className={cell(right)}>
                <span className={cn(GUTTER, "w-9 pr-1.5")}>{right?.newLineNo ?? ""}</span>
                <span className={marker(right)}>{right?.type === "added" ? "+" : ""}</span>
                {renderContent(right, rightIdx)}
              </div>
            </div>
          );
        })}
      </div>
    );
  }

  return (
    <div className={ROW}>
      {lines.map((line, i) => {
        if (line.type === "hunk") {
          return (
            <div key={i} className="flex bg-sky-500/[0.07] text-sky-700/80 dark:bg-sky-500/10 dark:text-sky-300/70">
              <span className="w-[5.25rem] shrink-0 border-r border-zinc-200/70 dark:border-zinc-800/70" />
              <span className="pl-2">{line.content}</span>
            </div>
          );
        }
        if (line.type === "meta") {
          return <div key={i} className="flex px-2 text-zinc-400 dark:text-zinc-600 italic">{line.content}</div>;
        }
        const isAdded = line.type === "added";
        const isRemoved = line.type === "removed";
        return (
          <div
            key={i}
            className={cn(
              "flex border-l-2 border-l-transparent",
              isAdded && "border-l-emerald-500 bg-emerald-500/12 dark:bg-emerald-500/[0.14]",
              isRemoved && "border-l-red-500 bg-red-500/12 dark:bg-red-500/[0.14]",
            )}
          >
            <span className={cn(GUTTER, "w-9 pr-1.5", isAdded && "text-transparent")}>{line.oldLineNo ?? ""}</span>
            <span className={cn(GUTTER, "w-9 pr-1.5", isRemoved && "text-transparent")}>{line.newLineNo ?? ""}</span>
            <span className={cn(
              "select-none w-4 shrink-0 text-center",
              isAdded && "text-emerald-600 dark:text-emerald-400",
              isRemoved && "text-red-600 dark:text-red-400",
              !isAdded && !isRemoved && "text-transparent",
            )}>
              {isAdded ? "+" : isRemoved ? "−" : ""}
            </span>
            {renderContent(line, i)}
          </div>
        );
      })}
    </div>
  );
}
