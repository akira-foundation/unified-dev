import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";

import type { IssueColumnId } from "@/types/issue";

export type IssueViewMode = "list" | "kanban";

interface IssueViewState {
  viewMode: IssueViewMode;
  setViewMode: (mode: IssueViewMode) => void;
  insightsOpen: boolean;
  toggleInsights: () => void;
  setInsightsOpen: (open: boolean) => void;
  hiddenColumns: IssueColumnId[];
  hideColumn: (id: IssueColumnId) => void;
  showColumn: (id: IssueColumnId) => void;
}

export const useIssueViewStore = create<IssueViewState>()(
  persist(
    (set) => ({
      viewMode: "list",
      setViewMode: (mode) => set({ viewMode: mode }),
      insightsOpen: false,
      toggleInsights: () => set((s) => ({ insightsOpen: !s.insightsOpen })),
      setInsightsOpen: (open) => set({ insightsOpen: open }),
      hiddenColumns: [],
      hideColumn: (id) => set((s) => ({ hiddenColumns: [...new Set([...s.hiddenColumns, id])] })),
      showColumn: (id) => set((s) => ({ hiddenColumns: s.hiddenColumns.filter((c) => c !== id) })),
    }),
    {
      name: "unified_dev_issue_view",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({ viewMode: state.viewMode, hiddenColumns: state.hiddenColumns }),
    },
  ),
);
