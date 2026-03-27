import { Keyboard } from "lucide-react";
import { useI18n } from "@/i18n/i18n";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";

const SHORTCUTS = [
  { labelKey: "settings.shortcuts.toggleTerminal", keys: "⌘`" },
  { labelKey: "settings.shortcuts.toggleSidebar", keys: "⌘B" },
  { labelKey: "settings.shortcuts.toggleChanges", keys: "⌘D" },
  { labelKey: "settings.shortcuts.toggleDiff", keys: "⌘⇧D" },
  { labelKey: "settings.shortcuts.togglePreview", keys: "⌘P" },
  { labelKey: "settings.shortcuts.mergePr", keys: "⌘⇧M" },
  { labelKey: "settings.shortcuts.addAttachment", keys: "⌘⇧A" },
  { labelKey: "settings.shortcuts.togglePlan", keys: "⌘⇧P" },
  { labelKey: "settings.shortcuts.toggleOpinions", keys: "⌘⇧O" },
  { labelKey: "settings.shortcuts.toggleDictation", keys: "⌘⇧V" },
  { labelKey: "settings.shortcuts.focusPrompt", keys: "⌘L" },
] as const;

export function ShortcutsTab() {
  const { t } = useI18n();

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection title={t("settings.shortcuts.title")} description={t("settings.shortcuts.description")} icon={Keyboard}>
        {SHORTCUTS.map((shortcut) => (
          <SettingsItem
            key={shortcut.labelKey}
            label={t(shortcut.labelKey)}
            action={
              <div className="w-48 flex justify-end">
                <div className="bg-zinc-100 dark:bg-white/5 border border-zinc-200 dark:border-white/10 rounded h-8 px-4 flex items-center justify-center font-mono text-[12px] text-zinc-600 dark:text-zinc-300 tracking-widest">
                  {shortcut.keys}
                </div>
              </div>
            }
          />
        ))}
      </SettingsSection>
    </div>
  );
}
