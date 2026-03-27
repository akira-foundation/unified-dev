import { FolderGit2 } from "lucide-react";
import { useI18n } from "@/i18n/i18n";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";

export function WorkspacesTab() {
  const { t } = useI18n();

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection
        title={t("settings.workspaces.title")}
        description={t("settings.workspaces.description")}
        icon={FolderGit2}
      >
        <SettingsItem
          label={t("settings.workspaces.defaultDir.label")}
          description={t("settings.workspaces.defaultDir.description")}
          action={
            <input
              type="text"
              defaultValue="~/Developer/Akira"
              className="w-64 h-8 px-3 rounded-md bg-zinc-50 dark:bg-white/5 border border-zinc-200 dark:border-white/10 text-[13px] text-zinc-900 dark:text-white focus:outline-none focus:border-purple-500 transition-colors"
            />
          }
        />
      </SettingsSection>
    </div>
  );
}
