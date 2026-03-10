import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";

import type { AppPage } from "../types/navigation";

interface NavigationState {
  currentPage: AppPage;
  activeProviderId: string | null;
  activeOrganizationId: string | null;
  history: AppPage[];
  canGoBack: boolean;
  isAgentMode: boolean;
  setCurrentPage: (page: AppPage) => void;
  navigateTo: (page: AppPage) => void;
  setIsAgentMode: (enabled: boolean) => void;
  goBack: () => void;
  setActiveProviderId: (providerId: string | null) => void;
  setActiveOrganizationId: (organizationId: string | null) => void;
}

export const useNavigationStore = create<NavigationState>()(
  persist(
    (set, get) => ({
      currentPage: "dashboard",
      activeProviderId: null,
      activeOrganizationId: null,
      history: [],
      canGoBack: false,
      isAgentMode: false,
      setCurrentPage: (page) => set({ currentPage: page }),
      navigateTo: (page) => {
        const { currentPage, history } = get();
        if (currentPage === page) {
          if (page === "agents") {
            set({ isAgentMode: true });
          }
          return;
        }

        const nextHistory = [...history, currentPage].slice(-20);
        const updates: Partial<NavigationState> = {
          currentPage: page,
          history: nextHistory,
          canGoBack: nextHistory.length > 0,
        };

        if (page === "agents") {
          updates.isAgentMode = true;
        } else {
          updates.isAgentMode = false;
        }

        set(updates);
      },
      setIsAgentMode: (enabled) => set({ isAgentMode: enabled }),
      goBack: () => {
        const { history } = get();
        if (history.length === 0) {
          return;
        }
        const nextHistory = history.slice(0, -1);
        const previous = history[history.length - 1];
        set({ currentPage: previous, history: nextHistory, canGoBack: nextHistory.length > 0 });
      },
      setActiveProviderId: (providerId) => set({ activeProviderId: providerId }),
      setActiveOrganizationId: (organizationId) => set({ activeOrganizationId: organizationId }),
    }),
    {
      name: "unified_dev_navigation",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({
        currentPage: state.currentPage,
        activeProviderId: state.activeProviderId,
        activeOrganizationId: state.activeOrganizationId,
        history: state.history,
      }),
      onRehydrateStorage: () => (state) => {
        if (state) {
          state.canGoBack = state.history.length > 0;
        }
      },
    },
  ),
);
