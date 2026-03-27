import { Blocks, Unplug, Link2 } from "lucide-react";
import { useI18n } from "@/i18n/i18n";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";

export function IntegrationsTab() {
  const { t } = useI18n();

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection title={t("settings.integrations.title")} description={t("settings.integrations.description")} icon={Blocks}>
        <SettingsItem
          label={t("settings.integrations.nightwatch.label")}
          description={t("settings.integrations.nightwatch.description")}
          action={
            <Button variant="outline" className="h-8 gap-2 bg-transparent hover:bg-zinc-100 dark:hover:bg-white/5 border-zinc-200 dark:border-white/10 dark:text-zinc-300">
              <Unplug className="h-4 w-4" /> {t("common.disconnect")}
            </Button>
          }
        />
        <SettingsItem
          label={t("settings.integrations.sentry.label")}
          description={t("settings.integrations.sentry.description")}
          action={
            <Button variant="outline" className="h-8 gap-2 bg-transparent hover:bg-zinc-100 dark:hover:bg-white/5 border-zinc-200 dark:border-white/10 dark:text-zinc-300">
              <Link2 className="h-4 w-4" /> {t("common.connect")}
            </Button>
          }
        />
        <SettingsItem
          label={t("settings.integrations.defaultIde.label")}
          description={t("settings.integrations.defaultIde.description")}
          action={
            <Select defaultValue="phpstorm">
              <SelectTrigger className="w-32 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="vscode">VS Code</SelectItem>
                <SelectItem value="cursor">Cursor</SelectItem>
                <SelectItem value="phpstorm">PhpStorm</SelectItem>
                <SelectItem value="webstorm">WebStorm</SelectItem>
                <SelectItem value="intellij">IntelliJ IDEA</SelectItem>
                <SelectItem value="zed">Zed</SelectItem>
                <SelectItem value="sublime">Sublime Text</SelectItem>
                <SelectItem value="rustrover">RustRover</SelectItem>
              </SelectContent>
            </Select>
          }
        />
        <SettingsItem
          label={t("settings.integrations.defaultTerminal.label")}
          description={t("settings.integrations.defaultTerminal.description")}
          action={
            <Select defaultValue="ghostty">
              <SelectTrigger className="w-32 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="terminal">Terminal</SelectItem>
                <SelectItem value="iterm2">iTerm2</SelectItem>
                <SelectItem value="warp">Warp</SelectItem>
                <SelectItem value="ghostty">Ghostty</SelectItem>
                <SelectItem value="kitty">Kitty</SelectItem>
                <SelectItem value="alacritty">Alacritty</SelectItem>
              </SelectContent>
            </Select>
          }
        />
      </SettingsSection>
    </div>
  );
}
