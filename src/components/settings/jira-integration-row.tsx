import { Link2, RefreshCw, Loader2, MoreHorizontal, Unlink } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { SettingsItem } from "./settings-item";
import { OUTLINE_BUTTON, cleanError } from "./integration-utils";
import { trackerService } from "@/services/trackerService";

const JIRA = "jira";

export function JiraRow() {
  const [connected, setConnected] = useState(false);
  const [account, setAccount] = useState<string | null>(null);
  const [count, setCount] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    trackerService
      .status(JIRA)
      .then(setConnected)
      .catch(() => {});
  }, []);

  async function connect() {
    setBusy(true);
    try {
      const user = await trackerService.connectJiraOauth();
      setConnected(true);
      setAccount(user.name);
      toast.success(`Jira connected as ${user.name}`);
    } catch (err) {
      toast.error(cleanError(err));
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
    : "Authorize Atlassian to sync your Jira issues into local storage.";

  return (
    <SettingsItem
      label="Jira"
      description={description}
      action={
        connected ? (
          <div className="flex items-center gap-2">
            <Button variant="outline" disabled={busy} onClick={sync} className={OUTLINE_BUTTON}>
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
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
          <Button variant="outline" disabled={busy} onClick={connect} className={OUTLINE_BUTTON}>
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Link2 className="h-4 w-4" />}
            {busy ? "Connecting…" : "Connect with Atlassian"}
          </Button>
        )
      }
    />
  );
}
