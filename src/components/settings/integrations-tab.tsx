import { Blocks, Unplug, Link2, RefreshCw } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { useI18n } from "@/i18n/i18n";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";
import { trackerService } from "@/services/trackerService";

const LINEAR = "linear";

function LinearIntegration() {
  const [token, setToken] = useState("");
  const [connected, setConnected] = useState(false);
  const [account, setAccount] = useState<string | null>(null);
  const [count, setCount] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    trackerService
      .status(LINEAR)
      .then(setConnected)
      .catch(() => {});
  }, []);

  async function connect() {
    const value = token.trim();
    if (!value) return;
    setBusy(true);
    try {
      const user = await trackerService.connect(LINEAR, value);
      setConnected(true);
      setAccount(user.name);
      setToken("");
      toast.success(`Linear connected as ${user.name}`);
    } catch (error) {
      toast.error(`Linear connect failed: ${error}`);
    } finally {
      setBusy(false);
    }
  }

  async function sync() {
    setBusy(true);
    try {
      const synced = await trackerService.sync(LINEAR);
      setCount(synced);
      toast.success(`Synced ${synced} Linear issue(s)`);
    } catch (error) {
      toast.error(`Linear sync failed: ${error}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <SettingsSection
      title="Linear"
      description="Connect your Linear workspace to sync issues into local storage."
      icon={Blocks}
    >
      {connected ? (
        <SettingsItem
          label={account ? `Connected as ${account}` : "Connected"}
          description={count !== null ? `${count} issue(s) synced` : "Pull your workspace issues."}
          action={
            <Button
              variant="outline"
              disabled={busy}
              onClick={sync}
              className="h-8 gap-2 bg-transparent hover:bg-zinc-100 dark:hover:bg-white/5 border-zinc-200 dark:border-white/10 dark:text-zinc-300"
            >
              <RefreshCw className="h-4 w-4" /> Sync
            </Button>
          }
        />
      ) : (
        <div className="flex items-center gap-2 px-1 py-2">
          <Input
            type="password"
            placeholder="lin_api_..."
            value={token}
            onChange={(event) => setToken(event.target.value)}
            className="h-8 flex-1"
          />
          <Button disabled={busy || !token.trim()} onClick={connect} className="h-8 gap-2">
            <Link2 className="h-4 w-4" /> Connect
          </Button>
        </div>
      )}
    </SettingsSection>
  );
}

export function IntegrationsTab() {
  const { t } = useI18n();

  return (
    <div className="animate-in fade-in duration-300 space-y-6">
      <LinearIntegration />
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
