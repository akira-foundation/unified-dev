import { Blocks, Link2, RefreshCw } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { useI18n } from "@/i18n/i18n";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";
import { trackerService } from "@/services/trackerService";

const LINEAR = "linear";
const OUTLINE_BUTTON =
  "h-8 gap-2 bg-transparent hover:bg-zinc-100 dark:hover:bg-white/5 border-zinc-200 dark:border-white/10 dark:text-zinc-300";

function useLinearConnection() {
  const [connected, setConnected] = useState(false);
  const [account, setAccount] = useState<string | null>(null);
  const [count, setCount] = useState<number | null>(null);
  const [editing, setEditing] = useState(false);
  const [token, setToken] = useState("");
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
      setEditing(false);
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

  return {
    connected,
    account,
    count,
    editing,
    token,
    busy,
    setEditing,
    setToken,
    connect,
    sync,
  };
}

function LinearRow() {
  const linear = useLinearConnection();

  const description = linear.connected
    ? linear.account
      ? `Connected as ${linear.account}${linear.count !== null ? ` · ${linear.count} synced` : ""}`
      : "Connected"
    : "Sync your Linear workspace issues into local storage.";

  let action;
  if (linear.connected) {
    action = (
      <Button variant="outline" disabled={linear.busy} onClick={linear.sync} className={OUTLINE_BUTTON}>
        <RefreshCw className="h-4 w-4" /> Sync
      </Button>
    );
  } else if (linear.editing) {
    action = (
      <div className="flex items-center gap-2">
        <Input
          type="password"
          autoFocus
          placeholder="lin_api_..."
          value={linear.token}
          onChange={(event) => linear.setToken(event.target.value)}
          onKeyDown={(event) => event.key === "Enter" && linear.connect()}
          className="h-8 w-52"
        />
        <Button disabled={linear.busy || !linear.token.trim()} onClick={linear.connect} className="h-8 gap-2">
          <Link2 className="h-4 w-4" /> Connect
        </Button>
      </div>
    );
  } else {
    action = (
      <Button variant="outline" onClick={() => linear.setEditing(true)} className={OUTLINE_BUTTON}>
        <Link2 className="h-4 w-4" /> Connect
      </Button>
    );
  }

  return <SettingsItem label="Linear" description={description} action={action} />;
}

export function IntegrationsTab() {
  const { t } = useI18n();

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection title={t("settings.integrations.title")} description={t("settings.integrations.description")} icon={Blocks}>
        <LinearRow />
      </SettingsSection>
    </div>
  );
}
