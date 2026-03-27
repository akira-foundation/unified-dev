import { Bell } from "lucide-react";
import { useI18n } from "@/i18n/i18n";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";

export function NotificationsTab() {
  const { t } = useI18n();

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection title={t("settings.notifications.title")} description={t("settings.notifications.description")} icon={Bell}>
        <SettingsItem
          label={t("settings.notifications.agentFinish.label")}
          description={t("settings.notifications.agentFinish.description")}
          action={<Switch defaultChecked />}
        />
        <SettingsItem
          label={t("settings.notifications.dockBadge.label")}
          description={t("settings.notifications.dockBadge.description")}
          action={<Switch defaultChecked />}
        />
        <SettingsItem
          label={t("settings.notifications.completionSound.label")}
          description={t("settings.notifications.completionSound.description")}
          action={
            <Select defaultValue="unfocused">
              <SelectTrigger className="w-48 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="unfocused">{t("settings.notifications.completionSound.unfocused")}</SelectItem>
                <SelectItem value="always">{t("settings.notifications.completionSound.always")}</SelectItem>
                <SelectItem value="never">{t("settings.notifications.completionSound.never")}</SelectItem>
              </SelectContent>
            </Select>
          }
        />
        <SettingsItem
          label={t("settings.notifications.sound.label")}
          description={t("settings.notifications.sound.description")}
          action={
            <Select defaultValue="sparkle">
              <SelectTrigger className="w-48 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="sparkle">{t("settings.notifications.sound.sparkleDing")}</SelectItem>
                <SelectItem value="chime">{t("settings.notifications.sound.chime")}</SelectItem>
                <SelectItem value="pop">{t("settings.notifications.sound.pop")}</SelectItem>
              </SelectContent>
            </Select>
          }
        />
      </SettingsSection>
    </div>
  );
}
