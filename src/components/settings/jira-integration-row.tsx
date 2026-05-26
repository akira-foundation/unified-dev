import { Blocks, Link2, RefreshCw, Loader2, MoreHorizontal, Unlink } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
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
import { SettingsItem } from "./settings-item";
import { FIELD_INPUT, OUTLINE_BUTTON, cleanError } from "./integration-utils";
import { trackerService } from "@/services/trackerService";

const JIRA = "jira";

export function JiraRow() {
  const [connected, setConnected] = useState(false);
  const [account, setAccount] = useState<string | null>(null);
  const [count, setCount] = useState<number | null>(null);
  const [open, setOpen] = useState(false);
  const [siteUrl, setSiteUrl] = useState("");
  const [email, setEmail] = useState("");
  const [token, setToken] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    trackerService
      .status(JIRA)
      .then(setConnected)
      .catch(() => {});
  }, []);

  function reset() {
    setSiteUrl("");
    setEmail("");
    setToken("");
    setError(null);
  }

  const canConnect = !!siteUrl.trim() && !!email.trim() && !!token.trim();

  async function connect() {
    if (!canConnect) return;
    const credentials = `${siteUrl.trim()}|${email.trim()}|${token.trim()}`;
    setBusy(true);
    setError(null);
    try {
      const user = await trackerService.connect(JIRA, credentials);
      setConnected(true);
      setAccount(user.name);
      setOpen(false);
      reset();
      toast.success(`Jira connected as ${user.name}`);
    } catch (err) {
      setError(cleanError(err));
    } finally {
      setBusy(false);
    }
  }

  async function sync() {
    setBusy(true);
    try {
      const synced = await trackerService.sync(JIRA);
      setCount(synced);
      toast.success(`Synced ${synced} Jira issue(s)`);
    } catch (err) {
      toast.error(cleanError(err));
    } finally {
      setBusy(false);
    }
  }

  async function disconnect() {
    setBusy(true);
    try {
      await trackerService.disconnect(JIRA);
      setConnected(false);
      setAccount(null);
      setCount(null);
      toast.success("Jira disconnected");
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
    : "Sync your Jira project issues into local storage.";

  return (
    <>
      <SettingsItem
        label="Jira"
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
            reset();
          }
        }}
      >
        <DialogContent className="max-w-[420px] p-0 gap-0 overflow-hidden">
          <DialogHeader className="px-5 pt-5 pb-4 border-b border-border">
            <div className="flex items-center gap-2">
              <Blocks className="h-4 w-4 text-purple-500" />
              <DialogTitle className="text-base">Connect Jira</DialogTitle>
            </div>
            <p className="mt-1.5 text-sm text-muted-foreground">
              Enter your Jira Cloud site, account email and an API token. They are encrypted and stored only on this device.
            </p>
          </DialogHeader>

          <div className="px-5 py-4 space-y-3">
            <div className="space-y-1">
              <p className="text-[11px] text-muted-foreground">Site URL</p>
              <Input
                autoFocus
                placeholder="https://your-domain.atlassian.net"
                value={siteUrl}
                onChange={(event) => {
                  setSiteUrl(event.target.value);
                  if (error) setError(null);
                }}
                className={FIELD_INPUT}
              />
            </div>
            <div className="space-y-1">
              <p className="text-[11px] text-muted-foreground">Account email</p>
              <Input
                type="email"
                placeholder="you@example.com"
                value={email}
                onChange={(event) => {
                  setEmail(event.target.value);
                  if (error) setError(null);
                }}
                className={FIELD_INPUT}
              />
            </div>
            <div className="space-y-1">
              <p className="text-[11px] text-muted-foreground">API token</p>
              <Input
                type="password"
                placeholder="Atlassian API token"
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
              disabled={busy || !canConnect}
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
