import { FileText } from "lucide-react";
import { useToggle } from "@uidotdev/usehooks";

import { PageLayout } from "@/components/layout/page-layout";
import { PageHeader, PageHeaderActions, PageHeaderTitle } from "@/components/layout/page-header";
import { KanbanBoard, KanbanFilterPopover } from "@/components/kanban-board";
import { useI18n } from "@/i18n/i18n";
import { cn } from "@/lib/utils";

export function PrsPage() {
  const { t } = useI18n();
  const [kanbanCompact, toggleKanbanCompact] = useToggle(false);

  return (
    <PageLayout scroll={false}>
      <PageHeader>
        <PageHeaderTitle>{t("nav.prs")}</PageHeaderTitle>
        <PageHeaderActions>
          <button
            onClick={() => toggleKanbanCompact()}
            className={cn(
              "cursor-pointer flex items-center gap-1.5 rounded-md border px-2.5 py-1.5 text-[11px] font-semibold uppercase tracking-wider transition-colors",
              kanbanCompact
                ? "border-zinc-600 bg-zinc-800 text-zinc-200"
                : "border-zinc-200 bg-zinc-100/50 text-zinc-500 dark:border-zinc-800 dark:bg-zinc-900/50 dark:text-zinc-500 hover:border-zinc-600 hover:text-zinc-300",
            )}
          >
            <FileText size={13} />
            Compact
          </button>
          <KanbanFilterPopover />
        </PageHeaderActions>
      </PageHeader>

      <div className="flex min-h-0 flex-1 flex-col px-4 md:px-6">
        <div className="min-h-0 flex-1 overflow-auto custom-scrollbar">
          <KanbanBoard compact={kanbanCompact} />
        </div>
      </div>
    </PageLayout>
  );
}
