import { Blocks, Link2, RefreshCw, Loader2, MoreHorizontal, Unlink } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { useI18n } from "@/i18n/i18n";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Dialog,
  DialogContent,
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
const FIELD_INPUT =
  "h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs text-zinc-600 placeholder:text-zinc-400 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300 dark:placeholder:text-zinc-500";

function cleanError(error: unknown): string {
  return String(error).replace(/^provider error:\s*/i, "");
}

function LinearRow() {
  const [connected, setConnected] = useState(false);
  const [account, setAccount] = useState<string | null>(null);
  const [count, setCount] = useState<number | null>(null);
  const [open, setOpen] = useState(false);
  const [token, setToken] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

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
    setError(null);
    try {
      const user = await trackerService.connect(LINEAR, value);
      setConnected(true);
      setAccount(user.name);
      setToken("");
      setOpen(false);
      toast.success(`Linear connected as ${user.name}`);
    } catch (err) {
      setError(cleanError(err));
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
    } catch (err) {
      toast.error(cleanError(err));
    } finally {
      setBusy(false);
    }
  }

  async function disconnect() {
    setBusy(true);
    try {
      await trackerService.disconnect(LINEAR);
      setConnected(false);
      setAccount(null);
      setCount(null);
      toast.success("Linear disconnected");
    } catch (err) {
      toast.error(cleanError(err));
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
            <div className="flex items-center gap-2">
              <Button variant="outline" disabled={busy} onClick={sync} className={OUTLINE_BUTTON}>
                {busy ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <RefreshCw className="h-4 w-4" />
                )}
                {busy ? "Syncing…" : "Sync"}
              </Button>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="outline" size="icon" disabled={busy} className={OUTLINE_BUTTON}>
                    <MoreHorizontal className="h-4 w-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuItem onClick={disconnect} className="text-destructive focus:text-destructive">
                    <Unlink className="h-4 w-4" />
                    Disconnect
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          ) : (
            <Button
              variant="outline"
              onClick={() => {
                setError(null);
                setOpen(true);
              }}
              className={OUTLINE_BUTTON}
            >
              <Link2 className="h-4 w-4" /> Connect
            </Button>
          )
        }
      />

      <Dialog
        open={open}
        onOpenChange={(value) => {
          if (!value) {
            setOpen(false);
            setToken("");
            setError(null);
          }
        }}
      >
        <DialogContent className="max-w-[420px] p-0 gap-0 overflow-hidden">
          <DialogHeader className="px-5 pt-5 pb-4 border-b border-border">
            <div className="flex items-center gap-2">
              <Blocks className="h-4 w-4 text-purple-500" />
              <DialogTitle className="text-base">Connect Linear</DialogTitle>
            </div>
            <p className="mt-1.5 text-sm text-muted-foreground">
              Paste a Linear personal API key. It is encrypted and stored only on this device.
            </p>
          </DialogHeader>

          <div className="px-5 py-4 space-y-3">
            <div className="space-y-1">
              <p className="text-[11px] text-muted-foreground">API key</p>
              <Input
                type="password"
                autoFocus
                placeholder="lin_api_..."
                value={token}
                onChange={(event) => {
                  setToken(event.target.value);
                  if (error) setError(null);
                }}
                onKeyDown={(event) => {
                  if (event.key === "Enter") connect();
                }}
                className={FIELD_INPUT}
              />
            </div>
            {error && <p className="text-xs text-destructive">{error}</p>}
          </div>

          <DialogFooter className="px-5 pb-5 pt-0 flex gap-2">
            <Button variant="outline" size="sm" onClick={() => setOpen(false)} disabled={busy}>
              Cancel
            </Button>
            <Button
              size="sm"
              onClick={connect}
              disabled={busy || !token.trim()}
              className="flex-1 gap-2 bg-purple-600 hover:bg-purple-700 text-white"
            >
              <Link2 className="h-3.5 w-3.5" />
              {busy ? "Connecting…" : "Connect"}
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
