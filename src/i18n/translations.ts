import { en } from "./locales/en";
import { pt } from "./locales/pt";

export type Locale = "en" | "pt-PT";

type Dictionary = Record<string, string>;

export const translations: Record<Locale, Dictionary> = {
  en,
  "pt-PT": pt,
};
