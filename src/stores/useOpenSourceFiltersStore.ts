import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";

import type { OssContributionType } from "@/types/openSource";

interface OpenSourceFiltersState {
  year: number | undefined;
  org: string | undefined;
  repo: string | undefined;
  type: OssContributionType | undefined;
  state: string | undefined;
  setYear: (year: number | undefined) => void;
  setOrg: (org: string | undefined) => void;
  setRepo: (repo: string | undefined) => void;
  setType: (type: OssContributionType | undefined) => void;
  setState: (state: string | undefined) => void;
  reset: () => void;
}

const initial = {
  year: undefined,
  org: undefined,
  repo: undefined,
  type: undefined,
  state: undefined,
};

export const useOpenSourceFiltersStore = create<OpenSourceFiltersState>()(
  persist(
    (set) => ({
      ...initial,
      setYear: (year) => set({ year }),
      setOrg: (org) => set({ org }),
      setRepo: (repo) => set({ repo }),
      setType: (type) => set({ type }),
      setState: (state) => set({ state }),
      reset: () => set({ ...initial }),
    }),
    {
      name: "unified_dev_open_source_filters",
      storage: createJSONStorage(() => localStorage),
    },
  ),
);
