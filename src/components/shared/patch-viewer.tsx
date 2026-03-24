import { cn } from "../../lib/utils";

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
    if (
      raw.startsWith("diff ") ||
      raw.startsWith("index ") ||
      raw.startsWith("--- ") ||
      raw.startsWith("+++ ")
    ) {
      // skip file header lines — not useful in the viewer
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

export function PatchViewer({ patch, splitView = false }: { patch: string; splitView?: boolean }) {
  const lines = parsePatchLines(patch);

  if (splitView) {
    type SplitRow =
      | { kind: "hunk"; content: string }
      | { kind: "meta"; content: string }
      | { kind: "pair"; left: PatchLine | null; right: PatchLine | null };

    const rows: SplitRow[] = [];
    let i = 0;
    while (i < lines.length) {
      const l = lines[i];
      if (l.type === "hunk") { rows.push({ kind: "hunk", content: l.content }); i++; continue; }
      if (l.type === "meta") { rows.push({ kind: "meta", content: l.content }); i++; continue; }
      if (l.type === "removed") {
        const next = lines[i + 1];
        if (next?.type === "added") {
          rows.push({ kind: "pair", left: l, right: next });
          i += 2;
        } else {
          rows.push({ kind: "pair", left: l, right: null });
          i++;
        }
        continue;
      }
      if (l.type === "added") {
        rows.push({ kind: "pair", left: null, right: l });
        i++;
        continue;
      }
      rows.push({ kind: "pair", left: l, right: l });
      i++;
    }

    const cellCls = (line: PatchLine | null) => cn(
      "flex-1 flex gap-0",
      line?.type === "added" && "bg-emerald-500/10 dark:bg-emerald-500/8",
      line?.type === "removed" && "bg-red-500/10 dark:bg-red-500/8",
    );

    const markerCls = (line: PatchLine | null) => cn(
      "select-none w-5 shrink-0 text-center",
      line?.type === "added" && "text-emerald-500 dark:text-emerald-400",
      line?.type === "removed" && "text-red-500 dark:text-red-400",
      (!line || line.type === "context") && "text-transparent",
    );

    const contentCls = (line: PatchLine | null) => cn(
      "flex-1 whitespace-pre-wrap break-all pl-1 pr-3",
      (line?.type === "added" || line?.type === "removed") && "text-zinc-800 dark:text-zinc-200",
      (!line || line.type === "context") && "text-zinc-600 dark:text-zinc-400",
    );

    return (
      <div className="py-1 font-mono text-[11px] leading-5">
        {rows.map((row, idx) => {
          if (row.kind === "hunk") {
            return (
              <div key={idx} className="flex">
                <span className="select-none w-8 shrink-0 border-r border-zinc-200/60 dark:border-zinc-700/40" />
                <span className="w-px shrink-0 bg-zinc-200/60 dark:bg-zinc-700/40" />
                <span className="pl-3 text-zinc-400/50 dark:text-zinc-600/50 italic flex-1">{row.content}</span>
              </div>
            );
          }
          if (row.kind === "meta") {
            return (
              <div key={idx} className="flex text-zinc-400 dark:text-zinc-600 italic">
                <span className="select-none w-8 shrink-0 border-r border-zinc-200/60 dark:border-zinc-700/40" />
                <span className="pl-3 flex-1">{row.content}</span>
              </div>
            );
          }
          const { left, right } = row;
          return (
            <div key={idx} className="flex">
              <div className={cellCls(left)}>
                <span className="select-none w-8 shrink-0 text-right pr-1.5 tabular-nums text-zinc-400 dark:text-zinc-600 border-r border-zinc-200/60 dark:border-zinc-700/40">
                  {left?.oldLineNo ?? ""}
                </span>
                <span className={markerCls(left)}>{left?.type === "removed" ? "−" : ""}</span>
                <span className={contentCls(left)}>{left?.content ?? ""}</span>
              </div>
              <span className="w-px shrink-0 bg-zinc-200/60 dark:bg-zinc-700/40" />
              <div className={cellCls(right)}>
                <span className="select-none w-8 shrink-0 text-right pr-1.5 tabular-nums text-zinc-400 dark:text-zinc-600 border-r border-zinc-200/60 dark:border-zinc-700/40">
                  {right?.newLineNo ?? ""}
                </span>
                <span className={markerCls(right)}>{right?.type === "added" ? "+" : ""}</span>
                <span className={contentCls(right)}>{right?.content ?? ""}</span>
              </div>
            </div>
          );
        })}
      </div>
    );
  }

  return (
    <div className="py-1 font-mono text-[11px] leading-5">
      {lines.map((line, i) => {
        if (line.type === "hunk") {
          return (
            <div key={i} className="flex gap-0">
              <span className="select-none w-20 shrink-0 border-r border-zinc-200/60 dark:border-zinc-700/40" />
              <span className="pl-3 text-zinc-400/50 dark:text-zinc-600/50 italic">{line.content}</span>
            </div>
          );
        }

        if (line.type === "meta") {
          return (
            <div key={i} className="flex gap-0 text-zinc-400 dark:text-zinc-600 italic">
              <span className="select-none w-20 shrink-0 border-r border-zinc-200/60 dark:border-zinc-700/40" />
              <span className="pl-3">{line.content}</span>
            </div>
          );
        }

        const isAdded = line.type === "added";
        const isRemoved = line.type === "removed";

        return (
          <div
            key={i}
            className={cn(
              "flex gap-0 group/line",
              isAdded && "bg-emerald-500/10 dark:bg-emerald-500/8",
              isRemoved && "bg-red-500/10 dark:bg-red-500/8",
            )}
          >
            <span className={cn(
              "select-none w-10 shrink-0 text-right pr-2 tabular-nums border-r border-zinc-200/60 dark:border-zinc-700/40",
              isAdded ? "text-transparent" : "text-zinc-400 dark:text-zinc-600",
              isRemoved && "text-red-400/60 dark:text-red-500/40",
            )}>
              {line.oldLineNo ?? ""}
            </span>
            <span className={cn(
              "select-none w-10 shrink-0 text-right pr-2 tabular-nums border-r border-zinc-200/60 dark:border-zinc-700/40",
              isRemoved ? "text-transparent" : "text-zinc-400 dark:text-zinc-600",
              isAdded && "text-emerald-400/60 dark:text-emerald-500/40",
            )}>
              {line.newLineNo ?? ""}
            </span>
            <span className={cn(
              "select-none w-6 shrink-0 text-center",
              isAdded && "text-emerald-500 dark:text-emerald-400",
              isRemoved && "text-red-500 dark:text-red-400",
              !isAdded && !isRemoved && "text-transparent",
            )}>
              {isAdded ? "+" : isRemoved ? "−" : ""}
            </span>
            <span className={cn(
              "flex-1 whitespace-pre-wrap break-all pl-1 pr-4",
              (isAdded || isRemoved) && "text-zinc-800 dark:text-zinc-200",
              !isAdded && !isRemoved && "text-zinc-600 dark:text-zinc-400",
            )}>
              {line.content}
            </span>
          </div>
        );
      })}
    </div>
  );
}
