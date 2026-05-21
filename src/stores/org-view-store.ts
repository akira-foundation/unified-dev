import { create } from "zustand";

interface OrgViewState {
  insightsOpen: boolean;
  toggleInsights: () => void;
  setInsightsOpen: (open: boolean) => void;
}

export const useOrgViewStore = create<OrgViewState>((set) => ({
  insightsOpen: false,
  toggleInsights: () => set((s) => ({ insightsOpen: !s.insightsOpen })),
  setInsightsOpen: (open) => set({ insightsOpen: open }),
}));
