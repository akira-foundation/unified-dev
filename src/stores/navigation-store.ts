import { create } from "zustand";

import type { AppPage } from "../types/navigation";

interface NavigationState {
  currentPage: AppPage;
  activeOrganizationId: string | null;
  setCurrentPage: (page: AppPage) => void;
  setActiveOrganizationId: (organizationId: string | null) => void;
}

export const useNavigationStore = create<NavigationState>((set) => ({
  currentPage: "dashboard",
  activeOrganizationId: null,
  setCurrentPage: (page) => set({ currentPage: page }),
  setActiveOrganizationId: (organizationId) => set({ activeOrganizationId: organizationId }),
}));
