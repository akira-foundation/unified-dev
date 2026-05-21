import { create } from "zustand";

import type { ProviderOrg } from "../types/provider";

interface ImportViewState {
  selectedOrg: ProviderOrg | null;
  setSelectedOrg: (org: ProviderOrg | null) => void;
}

export const useImportViewStore = create<ImportViewState>((set) => ({
  selectedOrg: null,
  setSelectedOrg: (org) => set({ selectedOrg: org }),
}));
