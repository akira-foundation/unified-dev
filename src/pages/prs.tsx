import { openUrl } from "@tauri-apps/plugin-opener";
import { LayoutGrid, List } from "lucide-react";
import { useEffect } from "react";

import { AppbarActions } from "@/components/layout/appbar-actions";
import { PageLayout } from "@/components/layout/page-layout";
import { Skeleton } from "@/components/ui/skeleton";
import { PrKanban } from "@/components/prs/pr-kanban";
import { PrList } from "@/components/prs/pr-list";
import { PrToolbar } from "@/components/prs/pr-toolbar";
import { PrInsightsPanel } from "@/components/prs/pr-insights-panel";
import { usePrCards, type PrCardType } from "@/hooks/usePrCards";
import { useHotkey } from "@/hooks/useHotkey";
import { PrStatusIcon } from "@/lib/pr-column";
import { useI18n } from "@/i18n/i18n";
import { useNavigationStore } from "@/stores/navigation-store";
import { useSearchStore } from "@/stores/search-store";
import { usePrViewStore } from "@/stores/pr-view-store";

export function PrsPage() {
  const { t } = useI18n();
  const { setActiveRepo, setActivePr, navigateTo, setDashboardTab } = useNavigationStore();
  const { cards, allPrs, isLoading } = usePrCards();

  const viewMode = usePrViewStore((s) => s.viewMode);
  const setViewMode = usePrViewStore((s) => s.setViewMode);
  const insightsOpen = usePrViewStore((s) => s.insightsOpen);
  const toggleInsights = usePrViewStore((s) => s.toggleInsights);

  function handleSelect(card: PrCardType) {
    setDashboardTab("prs");
    setActiveRepo({ name: card.repoName, owner: card.owner, organizationId: card.organizationId });
    setActivePr(card.pr);
    navigateTo("pr-detail");
  }

  async function handleOpenUrl(url: string) {
    try {
      await openUrl(url);
    } catch {
      window.open(url, "_blank");
    }
  }

  const registerSearch = useSearchStore((s) => s.registerProvider);
  useEffect(() => {
    registerSearch({
      placeholder: t("prs.table.search"),
      items: cards.map((card) => ({
        id: card.id,
        title: card.pr.title,
        subtitle: `#${card.pr.number}`,
        icon: <PrStatusIcon column={card.columnId} />,
        onSelect: () => handleSelect(card),
      })),
    });
    return () => registerSearch(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cards]);

  useHotkey("f", toggleInsights);

  return (
    <PageLayout className="!p-0 !space-y-0 h-[calc(100vh-4rem)] overflow-hidden">
      <AppbarActions>
        <div className="flex items-center overflow-hidden rounded-md border border-zinc-200 dark:border-zinc-800">
          <button
            className={`px-2.5 py-1.5 transition-colors ${viewMode === "list" ? "bg-zinc-200 text-zinc-900 dark:bg-zinc-700 dark:text-white" : "text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"}`}
            onClick={() => setViewMode("list")}
            title={t("prs.page.listView")}
          >
            <List className="h-4 w-4" />
          </button>
          <button
            className={`px-2.5 py-1.5 transition-colors ${viewMode === "kanban" ? "bg-zinc-200 text-zinc-900 dark:bg-zinc-700 dark:text-white" : "text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300"}`}
            onClick={() => setViewMode("kanban")}
            title={t("prs.page.kanbanView")}
          >
            <LayoutGrid className="h-4 w-4" />
          </button>
        </div>
        <PrToolbar />
      </AppbarActions>

      <div className="flex h-full min-h-0">
        <div className="min-w-0 flex-1 overflow-y-auto custom-scrollbar p-4 md:p-6">
          {isLoading ? (
            <div className="space-y-3">
              <Skeleton className="h-24 w-full" />
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
            </div>
          ) : viewMode === "list" ? (
            <PrList cards={cards} onSelect={handleSelect} onOpenUrl={handleOpenUrl} />
          ) : (
            <PrKanban cards={cards} onSelect={handleSelect} />
          )}
        </div>

        {insightsOpen && <PrInsightsPanel prs={allPrs} className="w-72 shrink-0" />}
      </div>
    </PageLayout>
  );
}
