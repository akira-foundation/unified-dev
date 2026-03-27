import { Mic } from "lucide-react";
import { useI18n } from "@/i18n/i18n";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";

export function DictationTab() {
  const { t } = useI18n();

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection title={t("settings.dictation.title")} description={t("settings.dictation.description")} icon={Mic}>
        <SettingsItem
          label={t("settings.dictation.method.label")}
          description={t("settings.dictation.method.description")}
          action={
            <Select defaultValue="web_speech">
              <SelectTrigger className="w-40 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="web_speech">{t("settings.dictation.method.webSpeech")}</SelectItem>
                <SelectItem value="custom">{t("settings.dictation.method.custom")}</SelectItem>
              </SelectContent>
            </Select>
          }
        />
      </SettingsSection>
    </div>
  );
}
