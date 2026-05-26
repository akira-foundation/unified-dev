import { Blocks, Link2, RefreshCw } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { useI18n } from "@/i18n/i18n";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";
import { trackerService } from "@/services/trackerService";

const LINEAR = "linear";
const OUTLINE_BUTTON =
  "h-8 gap-2 bg-transparent hover:bg-zinc-100 dark:hover:bg-white/5 border-zinc-200 dark:border-white/10 dark:text-zinc-300";

function LinearRow() {
  const [connected, setConnected] = useState(false);
  const [account, setAccount] = useState<string | null>(null);
  const [count, setCount] = useState<number | null>(null);
  const [open, setOpen] = useState(false);
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
      setOpen(false);
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

  const description = connected
    ? account
      ? `Connected as ${account}${count !== null ? ` · ${count} synced` : ""}`
      : "Connected"
    : "Sync your Linear workspace issues into local storage.";

  return (
    <>
      <SettingsItem
        label="Linear"
        description={description}
        action={
          connected ? (
            <Button variant="outline" disabled={busy} onClick={sync} className={OUTLINE_BUTTON}>
              <RefreshCw className="h-4 w-4" /> Sync
            </Button>
          ) : (
            <Button variant="outline" onClick={() => setOpen(true)} className={OUTLINE_BUTTON}>
              <Link2 className="h-4 w-4" /> Connect
            </Button>
          )
        }
      />

      <Dialog
        open={open}
        onOpenChange={(value) => {
          if (!value) setOpen(false);
        }}
      >
        <DialogContent className="sm:max-w-[420px]">
          <DialogHeader>
            <DialogTitle>Connect Linear</DialogTitle>
            <DialogDescription>
              Paste a Linear personal API key to sync your workspace. The key is encrypted and
              stored only on this device.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4 pt-2">
            <input
              type="password"
              autoFocus
              value={token}
              onChange={(event) => setToken(event.target.value)}
              placeholder="lin_api_..."
              className="w-full rounded-md border border-zinc-200 dark:border-zinc-700 bg-transparent px-3 py-2 text-[13px] text-zinc-900 dark:text-zinc-100 placeholder:text-zinc-400 focus:outline-none focus:ring-1 focus:ring-zinc-400 dark:focus:ring-zinc-600"
              onKeyDown={(event) => {
                if (event.key === "Enter") connect();
              }}
            />
            <div className="flex gap-3 justify-end">
              <Button variant="outline" onClick={() => setOpen(false)} disabled={busy}>
                Cancel
              </Button>
              <Button onClick={connect} disabled={busy || !token.trim()}>
                {busy ? "Connecting…" : "Connect"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
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
