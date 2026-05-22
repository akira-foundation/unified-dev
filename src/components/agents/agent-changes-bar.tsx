import { useMemo } from "react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { useAgentsStore } from "@/stores/useAgentsStore";

export function AgentChangesBar({ className }: { className?: string }) {
  const { t } = useI18n();
  const fileChanges = useAgentsStore((s) => s.fileChanges);
  const isRightSidebarOpen = useAgentsStore((s) => s.isRightSidebarOpen);
  const islandPanel = useAgentsStore((s) => s.islandPanel);
  const setIslandPanel = useAgentsStore((s) => s.setIslandPanel);
  const setDiffViewTab = useAgentsStore((s) => s.setDiffViewTab);
  const setIsRightSidebarOpen = useAgentsStore((s) => s.setIsRightSidebarOpen);

  const { additions, deletions } = useMemo(() => {
    let additions = 0;
    let deletions = 0;
    for (const file of fileChanges) {
      if (!file.diff) continue;
      for (const line of file.diff.split("\n")) {
        if (line.startsWith("+") && !line.startsWith("+++")) additions++;
        else if (line.startsWith("-") && !line.startsWith("---")) deletions++;
      }
    }
    return { additions, deletions };
  }, [fileChanges]);

  const diffPanelOpen = isRightSidebarOpen && islandPanel === "diff";
  if (fileChanges.length === 0 || diffPanelOpen) return null;

  const summaryKey = fileChanges.length === 1 ? "agents.changesBar.summaryOne" : "agents.changesBar.summary";

  const review = () => {
    setIslandPanel("diff");
    setDiffViewTab("changes");
    setIsRightSidebarOpen(true);
  };

  return (
    <button
      type="button"
      onClick={review}
      className={cn(
        "group relative mx-auto flex w-[calc(100%-2.5rem)] items-center justify-between gap-3 rounded-xl border border-zinc-200 bg-zinc-100 px-4 pt-2.5 pb-6 text-left transition-colors hover:bg-zinc-200/70 dark:border-white/[0.07] dark:bg-[#2e2e2e] dark:hover:bg-[#343434]",
        className,
      )}
    >
      <span className="flex items-center gap-2.5 text-[12.5px] font-medium text-foreground/70">
        {t(summaryKey).replace("{count}", String(fileChanges.length))}
        <span className="flex items-center gap-1.5 font-mono text-[11px] font-semibold tabular-nums">
          <span className="text-emerald-500">+{additions}</span>
          <span className="text-red-500">-{deletions}</span>
        </span>
      </span>
      <span className="text-[12.5px] font-medium text-foreground/60 transition-colors group-hover:text-foreground">
        {t("agents.changesBar.review")}
      </span>
    </button>
  );
}
