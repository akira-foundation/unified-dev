import { create } from "zustand";

interface RepoViewState {
  insightsOpen: boolean;
  toggleInsights: () => void;
  setInsightsOpen: (open: boolean) => void;
}

export const useRepoViewStore = create<RepoViewState>((set) => ({
  insightsOpen: false,
  toggleInsights: () => set((s) => ({ insightsOpen: !s.insightsOpen })),
  setInsightsOpen: (open) => set({ insightsOpen: open }),
}));
