export const OUTLINE_BUTTON =
  "h-8 gap-2 bg-transparent hover:bg-zinc-100 dark:hover:bg-white/5 border-zinc-200 dark:border-white/10 dark:text-zinc-300";

export const FIELD_INPUT =
  "h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs text-zinc-600 placeholder:text-zinc-400 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300 dark:placeholder:text-zinc-500";

export function cleanError(error: unknown): string {
  return String(error).replace(/^provider error:\s*/i, "");
}
