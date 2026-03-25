/**
 * Semantic label coloring — independent of GitHub hex colors.
 * Colors are derived from the label name using keyword matching so they
 * adapt to light/dark theme via Tailwind classes instead of inline styles.
 */

type LabelVariant =
  | "bug"
  | "feature"
  | "enhancement"
  | "docs"
  | "chore"
  | "security"
  | "performance"
  | "question"
  | "wontfix"
  | "duplicate"
  | "blocked"
  | "default";

const VARIANT_CLASSES: Record<LabelVariant, string> = {
  bug:         "bg-red-500/10 border-red-500/30 text-red-600 dark:text-red-400",
  security:    "bg-red-500/10 border-red-500/30 text-red-600 dark:text-red-400",
  blocked:     "bg-red-500/10 border-red-500/30 text-red-600 dark:text-red-400",
  feature:     "bg-purple-500/10 border-purple-500/30 text-purple-600 dark:text-purple-400",
  enhancement: "bg-blue-500/10 border-blue-500/30 text-blue-600 dark:text-blue-400",
  performance: "bg-amber-500/10 border-amber-500/30 text-amber-600 dark:text-amber-400",
  docs:        "bg-zinc-500/10 border-zinc-500/30 text-zinc-600 dark:text-zinc-400",
  chore:       "bg-zinc-500/10 border-zinc-500/30 text-zinc-600 dark:text-zinc-400",
  question:    "bg-sky-500/10 border-sky-500/30 text-sky-600 dark:text-sky-400",
  wontfix:     "bg-zinc-500/10 border-zinc-500/30 text-zinc-500 dark:text-zinc-500",
  duplicate:   "bg-zinc-500/10 border-zinc-500/30 text-zinc-500 dark:text-zinc-500",
  default:     "bg-zinc-500/10 border-zinc-500/30 text-zinc-600 dark:text-zinc-400",
};

const KEYWORD_MAP: [string[], LabelVariant][] = [
  [["bug", "error", "fix", "crash", "broken", "defect", "regression"], "bug"],
  [["security", "vulnerability", "cve", "xss", "csrf", "injection"],   "security"],
  [["blocked", "blocking", "blocker"],                                   "blocked"],
  [["feature", "feat", "new"],                                           "feature"],
  [["enhancement", "improve", "improvement", "refactor"],                "enhancement"],
  [["perf", "performance", "optimize", "optimization", "speed"],         "performance"],
  [["doc", "docs", "documentation", "readme", "changelog"],              "docs"],
  [["chore", "ci", "cd", "build", "release", "deps", "dependency"],      "chore"],
  [["question", "help", "support", "discussion"],                        "question"],
  [["wontfix", "won't fix", "invalid"],                                  "wontfix"],
  [["duplicate", "dupe"],                                                 "duplicate"],
  [["compat", "compatibility"],                                           "chore"],
  [["task", "infra", "infrastructure"],                                   "chore"],
];

function resolveVariant(name: string): LabelVariant {
  const lower = name.toLowerCase();
  for (const [keywords, variant] of KEYWORD_MAP) {
    if (keywords.some((kw) => lower.includes(kw))) {
      return variant;
    }
  }
  return "default";
}

export function LabelBadge({ name }: { name: string }) {
  const variant = resolveVariant(name);
  const classes = VARIANT_CLASSES[variant];
  return (
    <span
      className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-medium ${classes}`}
    >
      {name}
    </span>
  );
}

/** Smaller variant for kanban cards */
export function LabelBadgeSmall({ name }: { name: string }) {
  const variant = resolveVariant(name);
  const classes = VARIANT_CLASSES[variant];
  return (
    <span
      className={`inline-flex items-center rounded-full border px-1.5 py-0.5 text-[9px] font-medium ${classes}`}
    >
      {name}
    </span>
  );
}
