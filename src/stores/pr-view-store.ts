import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";

import type { PrColumnId } from "@/lib/pr-column";

export type PrViewMode = "list" | "kanban";

interface PrViewState {
  viewMode: PrViewMode;
  setViewMode: (mode: PrViewMode) => void;
  insightsOpen: boolean;
  toggleInsights: () => void;
  setInsightsOpen: (open: boolean) => void;
  hiddenColumns: PrColumnId[];
  hideColumn: (id: PrColumnId) => void;
  showColumn: (id: PrColumnId) => void;
}

export const usePrViewStore = create<PrViewState>()(
  persist(
    (set) => ({
      viewMode: "kanban",
      setViewMode: (mode) => set({ viewMode: mode }),
      insightsOpen: false,
      toggleInsights: () => set((s) => ({ insightsOpen: !s.insightsOpen })),
      setInsightsOpen: (open) => set({ insightsOpen: open }),
      hiddenColumns: [],
      hideColumn: (id) => set((s) => ({ hiddenColumns: [...new Set([...s.hiddenColumns, id])] })),
      showColumn: (id) => set((s) => ({ hiddenColumns: s.hiddenColumns.filter((c) => c !== id) })),
    }),
    {
      name: "unified_dev_pr_view",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({ viewMode: state.viewMode, hiddenColumns: state.hiddenColumns }),
    },
  ),
);
