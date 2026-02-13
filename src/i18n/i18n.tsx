import { createContext, useContext, useMemo } from "react";

import { useSettingsStore } from "@/stores/settings-store";
import type { Locale } from "./translations";
import { translations } from "./translations";

type I18nContextValue = {
  locale: Locale;
  setLocale: (locale: Locale) => void;
  t: (key: string) => string;
};

const I18nContext = createContext<I18nContextValue | null>(null);

export function I18nProvider({ children }: { children: React.ReactNode }) {
  const locale = useSettingsStore((state) => state.locale);
  const setLocale = useSettingsStore((state) => state.setLocale);

  const t = (key: string) => {
    return translations[locale][key] ?? key;
  };

  const value = useMemo(() => ({ locale, setLocale, t }), [locale, setLocale]);

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n() {
  const ctx = useContext(I18nContext);
  if (!ctx) {
    throw new Error("useI18n must be used within I18nProvider");
  }
  return ctx;
}
