import { create } from "zustand";

import type { AppPage } from "../types/navigation";

interface NavigationState {
  currentPage: AppPage;
  activeProviderId: string | null;
  activeOrganizationId: string | null;
  setCurrentPage: (page: AppPage) => void;
  setActiveProviderId: (providerId: string | null) => void;
  setActiveOrganizationId: (organizationId: string | null) => void;
}

export const useNavigationStore = create<NavigationState>((set) => ({
  currentPage: "dashboard",
  activeProviderId: null,
  activeOrganizationId: null,
  setCurrentPage: (page) => set({ currentPage: page }),
  setActiveProviderId: (providerId) => set({ activeProviderId: providerId }),
  setActiveOrganizationId: (organizationId) => set({ activeOrganizationId: organizationId }),
}));
