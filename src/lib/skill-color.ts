const SKILL_COLORS = [
  "bg-red-500/15 text-red-400",
  "bg-rose-500/15 text-rose-400",
  "bg-pink-500/15 text-pink-400",
  "bg-fuchsia-500/15 text-fuchsia-400",
  "bg-purple-500/15 text-purple-400",
  "bg-violet-500/15 text-violet-400",
  "bg-indigo-500/15 text-indigo-400",
  "bg-blue-500/15 text-blue-400",
  "bg-sky-500/15 text-sky-400",
  "bg-cyan-500/15 text-cyan-400",
  "bg-teal-500/15 text-teal-400",
  "bg-emerald-500/15 text-emerald-400",
  "bg-green-500/15 text-green-400",
  "bg-lime-500/15 text-lime-400",
  "bg-yellow-500/15 text-yellow-400",
  "bg-amber-500/15 text-amber-400",
  "bg-orange-500/15 text-orange-400",
];

export function skillColor(id: string): string {
  let hash = 0;
  for (let i = 0; i < id.length; i++) {
    hash = (hash * 31 + id.charCodeAt(i)) >>> 0;
  }
  return SKILL_COLORS[hash % SKILL_COLORS.length];
}
