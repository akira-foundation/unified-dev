import { Blocks, Link2, RefreshCw, KeyRound } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { useI18n } from "@/i18n/i18n";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
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

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <div className="flex items-center gap-3">
              <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-purple-500/10 text-purple-500">
                <KeyRound className="h-4 w-4" />
              </div>
              <div>
                <DialogTitle>Connect Linear</DialogTitle>
                <DialogDescription>
                  Paste a Linear personal API key to sync your workspace.
                </DialogDescription>
              </div>
            </div>
          </DialogHeader>

          <div className="space-y-2 py-2">
            <Label htmlFor="linear-token">API key</Label>
            <Input
              id="linear-token"
              type="password"
              autoFocus
              placeholder="lin_api_..."
              value={token}
              onChange={(event) => setToken(event.target.value)}
              onKeyDown={(event) => event.key === "Enter" && connect()}
            />
            <p className="text-xs text-zinc-500 dark:text-zinc-400">
              Create one in Linear → Settings → Security &amp; access → Personal API keys. The key
              is encrypted and stored only on this device.
            </p>
          </div>

          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" className={OUTLINE_BUTTON}>
                Cancel
              </Button>
            </DialogClose>
            <Button disabled={busy || !token.trim()} onClick={connect} className="h-8 gap-2">
              <Link2 className="h-4 w-4" /> Connect
            </Button>
          </DialogFooter>
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
