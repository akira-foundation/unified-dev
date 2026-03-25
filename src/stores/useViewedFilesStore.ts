import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";

interface ViewedFilesState {
  // key: "pr:{prNumber}" or "issue:{issueId}" → set of viewed filenames
  viewedByKey: Record<string, string[]>;
  isViewed: (key: string, filename: string) => boolean;
  toggleViewed: (key: string, filename: string) => void;
  setViewed: (key: string, filename: string, viewed: boolean) => void;
}

export const useViewedFilesStore = create<ViewedFilesState>()(
  persist(
    (set, get) => ({
      viewedByKey: {},

      isViewed: (key, filename) => {
        return get().viewedByKey[key]?.includes(filename) ?? false;
      },

      toggleViewed: (key, filename) => {
        const current = get().viewedByKey[key] ?? [];
        const next = current.includes(filename)
          ? current.filter((f) => f !== filename)
          : [...current, filename];
        set((state) => ({ viewedByKey: { ...state.viewedByKey, [key]: next } }));
      },

      setViewed: (key, filename, viewed) => {
        const current = get().viewedByKey[key] ?? [];
        const next = viewed
          ? current.includes(filename) ? current : [...current, filename]
          : current.filter((f) => f !== filename);
        set((state) => ({ viewedByKey: { ...state.viewedByKey, [key]: next } }));
      },
    }),
    {
      name: "unified_dev_viewed_files",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({ viewedByKey: state.viewedByKey }),
    },
  ),
);
