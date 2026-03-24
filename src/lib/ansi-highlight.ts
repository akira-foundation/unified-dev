/**
 * Minimal ANSI escape code parser for GitHub Actions log output.
 * Produces an array of segments, each with text and an optional CSS class.
 *
 * Supported SGR codes (the subset GitHub Actions actually emits):
 *   0          reset
 *   1          bold
 *   2          dim
 *   22         normal intensity
 *   30-37      standard foreground colors
 *   38;2;r;g;b truecolor foreground
 *   38;5;n     256-color foreground
 *   39         default foreground
 *   90-97      bright foreground colors
 *   40-47      standard background colors
 *   49         default background
 */

export interface AnsiSegment {
  text: string;
  className: string;
  style?: React.CSSProperties;
}

interface AnsiState {
  bold: boolean;
  dim: boolean;
  fgClass: string | null;
  fgStyle: React.CSSProperties | null;
}

const STANDARD_FG: Record<number, string> = {
  30: "text-zinc-500",
  31: "text-red-400",
  32: "text-emerald-400",
  33: "text-yellow-400",
  34: "text-blue-400",
  35: "text-purple-400",
  36: "text-cyan-400",
  37: "text-zinc-200",
  39: "",
  90: "text-zinc-400",
  91: "text-red-300",
  92: "text-emerald-300",
  93: "text-yellow-300",
  94: "text-blue-300",
  95: "text-purple-300",
  96: "text-cyan-300",
  97: "text-white",
};

// Converts a 256-color index to a CSS hex color string (approx)
function color256ToHex(n: number): string {
  if (n < 8) {
    const BASIC = ["#3f3f46", "#ef4444", "#22c55e", "#eab308", "#3b82f6", "#a855f7", "#06b6d4", "#d4d4d8"];
    return BASIC[n] ?? "#d4d4d8";
  }
  if (n < 16) {
    const BRIGHT = ["#71717a", "#f87171", "#4ade80", "#facc15", "#60a5fa", "#c084fc", "#22d3ee", "#ffffff"];
    return BRIGHT[n - 8] ?? "#ffffff";
  }
  if (n < 232) {
    const idx = n - 16;
    const r = Math.floor(idx / 36) * 51;
    const g = (Math.floor(idx / 6) % 6) * 51;
    const b = (idx % 6) * 51;
    return `rgb(${r},${g},${b})`;
  }
  const gray = 8 + (n - 232) * 10;
  return `rgb(${gray},${gray},${gray})`;
}

function applyCode(codes: number[], state: AnsiState): void {
  let i = 0;
  while (i < codes.length) {
    const code = codes[i];
    if (code === 0) {
      state.bold = false;
      state.dim = false;
      state.fgClass = null;
      state.fgStyle = null;
    } else if (code === 1) {
      state.bold = true;
    } else if (code === 2) {
      state.dim = true;
    } else if (code === 22) {
      state.bold = false;
      state.dim = false;
    } else if (code === 39 || code === 49) {
      state.fgClass = null;
      state.fgStyle = null;
    } else if ((code >= 30 && code <= 37) || (code >= 90 && code <= 97)) {
      state.fgClass = STANDARD_FG[code] ?? null;
      state.fgStyle = null;
    } else if (code === 38) {
      const mode = codes[i + 1];
      if (mode === 2 && i + 4 < codes.length) {
        const r = codes[i + 2], g = codes[i + 3], b = codes[i + 4];
        state.fgStyle = { color: `rgb(${r},${g},${b})` };
        state.fgClass = null;
        i += 4;
      } else if (mode === 5 && i + 2 < codes.length) {
        const hex = color256ToHex(codes[i + 2]);
        state.fgStyle = { color: hex };
        state.fgClass = null;
        i += 2;
      }
    }
    i++;
  }
}

function buildClassName(state: AnsiState): string {
  const parts: string[] = [];
  if (state.bold) parts.push("font-bold");
  if (state.dim) parts.push("opacity-50");
  if (state.fgClass) parts.push(state.fgClass);
  return parts.join(" ");
}

// ESC [ ... m  (CSI SGR sequence)
const ANSI_RE = /\x1b\[([0-9;]*)m/g;

export function parseAnsiLine(line: string): AnsiSegment[] {
  const segments: AnsiSegment[] = [];
  const state: AnsiState = { bold: false, dim: false, fgClass: null, fgStyle: null };
  let lastIndex = 0;

  let match: RegExpExecArray | null;
  ANSI_RE.lastIndex = 0;

  while ((match = ANSI_RE.exec(line)) !== null) {
    if (match.index > lastIndex) {
      segments.push({
        text: line.slice(lastIndex, match.index),
        className: buildClassName(state),
        style: state.fgStyle ?? undefined,
      });
    }

    const raw = match[1];
    const codes = raw === "" ? [0] : raw.split(";").map(Number);
    applyCode(codes, state);
    lastIndex = match.index + match[0].length;
  }

  if (lastIndex < line.length) {
    segments.push({
      text: line.slice(lastIndex),
      className: buildClassName(state),
      style: state.fgStyle ?? undefined,
    });
  }

  return segments;
}

// --- Keyword highlighting (applied to plain-text segments) ---

interface KeywordRule {
  pattern: RegExp;
  className: string;
}

const KEYWORD_RULES: KeywordRule[] = [
  { pattern: /\b(ERROR|FATAL|FAILED|FAILURE|error|fatal|failed|failure)\b/g, className: "text-red-400 font-semibold" },
  { pattern: /\b(WARNING|WARN|warning|warn)\b/g, className: "text-yellow-400" },
  { pattern: /\b(SUCCESS|PASSED|PASS|success|passed|pass)\b/g, className: "text-emerald-400 font-semibold" },
  { pattern: /\b(INFO|info|notice|NOTICE)\b/g, className: "text-blue-400" },
  { pattern: /\b(SKIP|SKIPPED|skipped|skip)\b/g, className: "text-zinc-400 italic" },
];

function applyKeywords(text: string, baseClass: string): AnsiSegment[] {
  // Merge all rules into one pass by building an ordered list of ranges
  interface Range { start: number; end: number; className: string }
  const ranges: Range[] = [];

  for (const rule of KEYWORD_RULES) {
    rule.pattern.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = rule.pattern.exec(text)) !== null) {
      ranges.push({ start: m.index, end: m.index + m[0].length, className: rule.className });
    }
  }

  if (ranges.length === 0) return [{ text, className: baseClass }];

  ranges.sort((a, b) => a.start - b.start);

  const result: AnsiSegment[] = [];
  let cursor = 0;
  for (const range of ranges) {
    if (range.start < cursor) continue; // overlapping — skip
    if (range.start > cursor) {
      result.push({ text: text.slice(cursor, range.start), className: baseClass });
    }
    result.push({ text: text.slice(range.start, range.end), className: range.className });
    cursor = range.end;
  }
  if (cursor < text.length) {
    result.push({ text: text.slice(cursor), className: baseClass });
  }
  return result;
}

/**
 * Full pipeline: parse ANSI codes first, then apply keyword highlighting
 * to segments that have no explicit color from ANSI.
 */
export function highlightLine(line: string): AnsiSegment[] {
  const ansiSegments = parseAnsiLine(line);
  const hasAnsiColor = ansiSegments.some((s) => s.className.includes("text-") || s.style);

  if (hasAnsiColor) return ansiSegments;

  // No ANSI color — apply keyword highlighting
  return ansiSegments.flatMap((seg) => applyKeywords(seg.text, seg.className));
}
