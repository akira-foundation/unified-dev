import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";

export type FilterValue = string[];

export type FilterMap = Record<string, FilterValue>;

interface FiltersState {
  filters: Record<string, FilterMap>;
  setFilter: (namespace: string, key: string, value: FilterValue) => void;
  clearFilters: (namespace: string) => void;
}

export const useFiltersStore = create<FiltersState>()(
  persist(
    (set) => ({
      filters: {},

      setFilter: (namespace, key, value) =>
        set((state) => ({
          filters: {
            ...state.filters,
            [namespace]: {
              ...state.filters[namespace],
              [key]: value,
            },
          },
        })),

      clearFilters: (namespace) =>
        set((state) => ({
          filters: {
            ...state.filters,
            [namespace]: {},
          },
        })),
    }),
    {
      name: "unified_dev_filters",
      storage: createJSONStorage(() => localStorage),
    },
  ),
);
