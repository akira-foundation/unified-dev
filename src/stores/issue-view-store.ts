import { create } from "zustand";

interface IssueViewState {
  insightsOpen: boolean;
  toggleInsights: () => void;
  setInsightsOpen: (open: boolean) => void;
}

export const useIssueViewStore = create<IssueViewState>((set) => ({
  insightsOpen: false,
  toggleInsights: () => set((s) => ({ insightsOpen: !s.insightsOpen })),
  setInsightsOpen: (open) => set({ insightsOpen: open }),
}));
