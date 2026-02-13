import { useCallback, useEffect, useState } from "react";

import { useSettingsStore } from "@/stores/settings-store";

export type Appearance = "light" | "dark" | "system";

const prefersDark = () => {
  if (typeof window === "undefined") {
    return false;
  }

  return window.matchMedia("(prefers-color-scheme: dark)").matches;
};

const setCookie = (name: string, value: string, days = 365) => {
  if (typeof document === "undefined") {
    return;
  }

  const maxAge = days * 24 * 60 * 60;
  document.cookie = `${name}=${value};path=/;max-age=${maxAge};SameSite=Lax`;
};

const applyTheme = (appearance: Appearance) => {
  const isDark = appearance === "dark" || (appearance === "system" && prefersDark());

  document.documentElement.classList.toggle("dark", isDark);
  document.documentElement.style.colorScheme = isDark ? "dark" : "light";
};

const mediaQuery = () => {
  if (typeof window === "undefined") {
    return null;
  }

  return window.matchMedia("(prefers-color-scheme: dark)");
};

const handleSystemThemeChange = () => {
  const currentAppearance = localStorage.getItem("appearance") as Appearance;
  applyTheme(currentAppearance || "system");
};

export function initializeTheme() {
  const savedAppearance = useSettingsStore.getState().appearance;

  applyTheme(savedAppearance || "system");
  mediaQuery()?.addEventListener("change", handleSystemThemeChange);
}

export function useAppearance() {
  const storedAppearance = useSettingsStore((state) => state.appearance);
  const setStoredAppearance = useSettingsStore((state) => state.setAppearance);
  const [appearance, setAppearance] = useState<Appearance>(storedAppearance ?? "system");

  const updateAppearance = useCallback(
    (mode: Appearance) => {
      setAppearance(mode);
      setStoredAppearance(mode);
      setCookie("appearance", mode);
      applyTheme(mode);
    },
    [setStoredAppearance],
  );

  useEffect(() => {
    updateAppearance(storedAppearance || "system");

    return () => mediaQuery()?.removeEventListener("change", handleSystemThemeChange);
  }, [updateAppearance, storedAppearance]);

  return { appearance, updateAppearance } as const;
}
