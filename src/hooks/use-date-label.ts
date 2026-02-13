import type { Locale } from "@/i18n/translations";

export function useDateLabel(locale: Locale, date = new Date()) {
  const formatter = new Intl.DateTimeFormat(locale, {
    weekday: "long",
    day: "2-digit",
    month: "short",
  });

  return formatter.format(date);
}
