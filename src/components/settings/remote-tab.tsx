import { useState, useMemo, useOptimistic, use, Suspense, Component, type ReactNode } from "react";
import { Wifi, ShieldCheck, Copy, RotateCw, Smartphone, Trash2 } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { QRCodeSVG } from "qrcode.react";
import { useI18n } from "@/i18n/i18n";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Badge } from "@/components/ui/badge";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";

interface RemoteDevice {
  id: string;
  name: string;
  lastSeen: string;
  status: "connected" | "idle";
}

interface RemoteSettingsDto {
  enabled: boolean;
  hostName: string;
  hostFingerprint: string;
  bindAddress: string;
  port: number;
  tailscaleRequired: boolean;
  pairingCode: string;
  pairingCodeExpiresAt: string;
  devices: RemoteDevice[];
}

function PairingQrCode({ value }: { value: string }) {
  return (
    <div className="rounded-3xl border border-zinc-200/80 bg-white p-4 shadow-sm dark:border-white/10 dark:bg-zinc-950">
      <QRCodeSVG value={value} size={220} bgColor="transparent" fgColor="currentColor" className="h-[220px] w-[220px] rounded-2xl text-zinc-950 dark:text-white" />
    </div>
  );
}

function RemoteTabContent({ settingsPromise }: { settingsPromise: Promise<RemoteSettingsDto> }) {
  const { t } = useI18n();
  const initial = use(settingsPromise);

  const [settings, setSettings] = useState<RemoteSettingsDto>(initial);
  const [optimisticEnabled, setOptimisticEnabled] = useOptimistic(settings.enabled);
  const [showPairingModal, setShowPairingModal] = useState(false);
  const [deviceToRemove, setDeviceToRemove] = useState<RemoteDevice | null>(null);

  const pairingUrl = useMemo(
    () => `unified://pair?host=${encodeURIComponent(settings.hostName)}&code=${encodeURIComponent(settings.pairingCode)}`,
    [settings.hostName, settings.pairingCode],
  );

  const copyValue = async (value: string, successMessage: string) => {
    try {
      await navigator.clipboard.writeText(value);
      toast.success(successMessage);
    } catch {
      toast.success(t("common.copy"));
    }
  };

  const handleToggle = async (checked: boolean) => {
    setOptimisticEnabled(checked);
    const updated = await invoke<RemoteSettingsDto>("set_remote_enabled", { enabled: checked });
    setSettings(updated);
    if (checked) setShowPairingModal(true);
  };

  const handleRegeneratePairingCode = async () => {
    const updated = await invoke<RemoteSettingsDto>("regenerate_remote_pairing_code");
    setSettings(updated);
    toast.success(t("settings.remote.toast.codeRegenerated"));
  };

  const handleRevokeDevice = async (deviceId: string) => {
    const updated = await invoke<RemoteSettingsDto>("revoke_remote_device", { deviceId });
    setSettings(updated);
    toast.success(t("settings.remote.toast.deviceRevoked"));
  };

  return (
    <>
      <SettingsSection title={t("settings.remote.title")} description={t("settings.remote.description")} icon={Wifi}>
        <SettingsItem
          label={t("settings.remote.enable.label")}
          description={t("settings.remote.enable.description")}
          action={<Switch checked={optimisticEnabled} onCheckedChange={handleToggle} />}
        />
        <SettingsItem
          label={t("settings.remote.network.label")}
          description={t("settings.remote.network.description")}
          action={<Badge variant="secondary" className="bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-200">Tailscale</Badge>}
        />
        <SettingsItem
          label={t("settings.remote.host.label")}
          description={t("settings.remote.host.description")}
          action={
            <Button
              variant="outline"
              className="h-8 gap-2 bg-transparent hover:bg-zinc-100 dark:hover:bg-white/5 border-zinc-200 dark:border-white/10 dark:text-zinc-300"
              onClick={() => copyValue(settings.hostName, t("settings.remote.toast.hostCopied"))}
            >
              <Copy className="h-4 w-4" />
              {settings.hostName}
            </Button>
          }
        />
        <SettingsItem
          label={t("settings.remote.pairing.entryLabel")}
          description={t("settings.remote.pairing.entryDescription")}
          action={
            <Button
              variant="outline"
              className="h-8 gap-2 bg-transparent hover:bg-zinc-100 dark:hover:bg-white/5 border-zinc-200 dark:border-white/10 dark:text-zinc-300"
              onClick={() => setShowPairingModal(true)}
              disabled={!optimisticEnabled}
            >
              <Smartphone className="h-4 w-4" />
              {t("settings.remote.pairing.open")}
            </Button>
          }
        />
      </SettingsSection>

      <div className="flex flex-col gap-6">
        <SettingsSection title={t("settings.remote.devices.title")} description={t("settings.remote.devices.description")} icon={ShieldCheck}>
          {settings.devices.length === 0 ? (
            <div className="px-4 py-10 text-sm text-zinc-500 dark:text-zinc-400">
              {t("settings.remote.devices.empty")}
            </div>
          ) : (
            settings.devices.map((device) => (
              <SettingsItem
                key={device.id}
                label={device.name}
                description={t("settings.remote.devices.lastSeen").replace("{time}", device.lastSeen)}
                action={
                  <div className="flex items-center gap-3">
                    <Badge
                      variant="secondary"
                      className={cn(
                        "capitalize",
                        device.status === "connected"
                          ? "bg-emerald-500/10 text-emerald-500"
                          : "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-300",
                      )}
                    >
                      {device.status === "connected" ? t("common.connected") : t("settings.remote.devices.idle")}
                    </Badge>
                    <button
                      onClick={() => setDeviceToRemove(device)}
                      className="flex h-8 w-8 items-center justify-center rounded-full bg-red-500/10 text-red-500 transition-colors hover:bg-red-500/20"
                      title={t("settings.remote.devices.revoke")}
                    >
                      <Trash2 size={16} />
                    </button>
                  </div>
                }
              />
            ))
          )}
        </SettingsSection>
      </div>

      <Dialog open={showPairingModal} onOpenChange={setShowPairingModal}>
        <DialogContent className="max-w-lg border-zinc-200 dark:border-white/10 bg-background">
          <DialogHeader>
            <DialogTitle>{t("settings.remote.pairing.title")}</DialogTitle>
            <DialogDescription>{t("settings.remote.pairing.description")}</DialogDescription>
          </DialogHeader>

          <div className="space-y-6">
            <div className="space-y-3">
              <div className="text-sm font-medium text-zinc-900 dark:text-white">
                {t("settings.remote.pairing.codeLabel")}
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <div className="rounded-xl border border-zinc-200 bg-white px-4 py-3 font-mono text-xl font-black tracking-[0.18em] text-zinc-900 dark:border-white/10 dark:bg-zinc-950 dark:text-white">
                  {settings.pairingCode}
                </div>
                <Button variant="outline" size="sm" className="gap-2" onClick={() => copyValue(settings.pairingCode, t("settings.remote.toast.codeCopied"))}>
                  <Copy className="h-4 w-4" />
                  {t("common.copy")}
                </Button>
                <Button variant="outline" size="sm" className="gap-2" onClick={handleRegeneratePairingCode}>
                  <RotateCw className="h-4 w-4" />
                  {t("settings.remote.pairing.regenerate")}
                </Button>
              </div>
              <p className="text-xs leading-relaxed text-zinc-500 dark:text-zinc-400">
                {t("settings.remote.pairing.helper")}
              </p>
            </div>

            <div className="flex flex-col items-center gap-3 rounded-2xl border border-zinc-200 dark:border-white/10 bg-zinc-50/40 dark:bg-white/[0.02] p-5">
              <PairingQrCode value={pairingUrl} />
              <div className="text-center text-xs leading-relaxed text-zinc-500 dark:text-zinc-400">
                {t("settings.remote.pairing.qrHelper")}
              </div>
            </div>

            <div className="space-y-2">
              <div className="text-sm font-medium text-zinc-900 dark:text-white">
                {t("settings.remote.pairing.urlLabel")}
              </div>
              <div className="flex items-center gap-2">
                <div className="flex-1 truncate rounded-xl border border-zinc-200 bg-zinc-50 px-3 py-2 text-xs text-zinc-600 dark:border-white/10 dark:bg-white/[0.03] dark:text-zinc-300">
                  {pairingUrl}
                </div>
                <Button variant="outline" size="sm" className="gap-2" onClick={() => copyValue(pairingUrl, t("settings.remote.toast.urlCopied"))}>
                  <Copy className="h-4 w-4" />
                  {t("common.copy")}
                </Button>
              </div>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={!!deviceToRemove} onOpenChange={(open) => !open && setDeviceToRemove(null)}>
        <DialogContent className="max-w-md border-zinc-200 dark:border-white/10 bg-background">
          <DialogHeader>
            <DialogTitle>{t("settings.remote.devices.removeTitle")}</DialogTitle>
            <DialogDescription>
              {t("settings.remote.devices.removeDescription").replace("{name}", deviceToRemove?.name ?? "")}
            </DialogDescription>
          </DialogHeader>
          <div className="flex items-center justify-end gap-3 pt-2">
            <Button variant="ghost" onClick={() => setDeviceToRemove(null)}>
              {t("common.cancel")}
            </Button>
            <Button
              variant="destructive"
              onClick={() => {
                if (!deviceToRemove) return;
                void handleRevokeDevice(deviceToRemove.id);
                setDeviceToRemove(null);
              }}
            >
              {t("common.remove")}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}

function RemoteTabSkeleton() {
  const { t } = useI18n();
  return (
    <div className="px-4 py-10 text-sm text-zinc-500 dark:text-zinc-400">
      {t("settings.remote.loading")}
    </div>
  );
}

interface ErrorBoundaryState { error: Error | null }

class RemoteTabErrorBoundary extends Component<{ children: ReactNode }, ErrorBoundaryState> {
  state: ErrorBoundaryState = { error: null };

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { error };
  }

  render() {
    if (this.state.error) {
      return (
        <div className="px-4 py-10 text-sm text-red-500 dark:text-red-400">
          {this.state.error.message}
        </div>
      );
    }
    return this.props.children;
  }
}

export function RemoteTab() {
  const settingsPromise = useMemo(() => invoke<RemoteSettingsDto>("get_remote_settings"), []);

  return (
    <div className="animate-in fade-in duration-300">
      <RemoteTabErrorBoundary>
        <Suspense fallback={<RemoteTabSkeleton />}>
          <RemoteTabContent settingsPromise={settingsPromise} />
        </Suspense>
      </RemoteTabErrorBoundary>
    </div>
  );
}
