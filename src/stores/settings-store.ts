import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";

import type { Locale } from "@/i18n/translations";
import type { Appearance } from "@/hooks/use-appearance";

interface SettingsState {
  locale: Locale;
  setLocale: (locale: Locale) => void;
  appearance: Appearance;
  setAppearance: (appearance: Appearance) => void;
  sidebarOpen: boolean;
  setSidebarOpen: (open: boolean) => void;
}

export const useSettingsStore = create<SettingsState>()(
  persist(
    (set) => ({
      locale: "en",
      setLocale: (locale) => set({ locale }),
      appearance: "system",
      setAppearance: (appearance) => set({ appearance }),
      sidebarOpen: true,
      setSidebarOpen: (open) => set({ sidebarOpen: open }),
    }),
    {
      name: "unified_dev_settings",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({
        locale: state.locale,
        appearance: state.appearance,
        sidebarOpen: state.sidebarOpen,
      }),
    },
  ),
);
