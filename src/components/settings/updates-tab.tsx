import { useEffect, useState } from "react";
import { Download, Folder } from "lucide-react";
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import { toast } from "sonner";
import { useI18n } from "@/i18n/i18n";
import { Switch } from "@/components/ui/switch";
import {
  backupDatabaseNow,
  getUpdateSettings,
  setUpdateSettings,
  type UpdateSettings,
} from "@/services/updateSettingsService";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";

export function UpdatesTab() {
  const { t } = useI18n();
  const [settings, setSettings] = useState<UpdateSettings | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [backingUp, setBackingUp] = useState(false);

  useEffect(() => {
    let mounted = true;
    getUpdateSettings()
      .then((s) => {
        if (mounted) setSettings(s);
      })
      .catch(() => {
        if (mounted) toast.error(t("settings.updates.loadError"));
      })
      .finally(() => {
        if (mounted) setLoading(false);
      });
    return () => {
      mounted = false;
    };
  }, [t]);

  const persist = async (next: UpdateSettings) => {
    setBusy(true);
    try {
      const saved = await setUpdateSettings(next);
      setSettings(saved);
    } catch (error) {
      toast.error(`${t("settings.updates.saveError")} (${String(error)})`);
    } finally {
      setBusy(false);
    }
  };

  const handleToggle = (checked: boolean) => {
    if (!settings) return;
    void persist({ ...settings, backupBeforeUpdate: checked });
  };

  const handlePickPath = async () => {
    const selected = await openDialog({
      directory: true,
      multiple: false,
      title: t("settings.updates.pickPath"),
    });
    if (typeof selected !== "string" || !selected) return;
    if (!settings) return;
    void persist({ ...settings, backupPath: selected });
  };

  const handleResetPath = () => {
    if (!settings) return;
    void persist({ ...settings, backupPath: null });
  };

  const handleBackupNow = async () => {
    setBackingUp(true);
    try {
      const dest = await backupDatabaseNow();
      if (dest) {
        toast.success(t("settings.updates.backupCreated"), { description: dest });
      } else {
        toast.message(t("settings.updates.backupSkipped"));
      }
    } catch (error) {
      toast.error(`${t("settings.updates.backupError")} (${String(error)})`);
    } finally {
      setBackingUp(false);
    }
  };

  const pathLabel = settings?.backupPath ?? t("settings.updates.pathDefault");

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection
        title={t("settings.updates.title")}
        description={t("settings.updates.description")}
        icon={Download}
      >
        <SettingsItem
          label={t("settings.updates.backupToggle.label")}
          description={t("settings.updates.backupToggle.description")}
          action={
            <Switch
              checked={settings?.backupBeforeUpdate ?? true}
              onCheckedChange={handleToggle}
              disabled={loading || busy}
            />
          }
        />

        <SettingsItem
          label={t("settings.updates.backupPath.label")}
          description={pathLabel}
          action={
            <div className="flex items-center gap-2">
              {settings?.backupPath && (
                <button
                  type="button"
                  onClick={handleResetPath}
                  disabled={loading || busy}
                  className="text-[11px] text-zinc-400 hover:text-zinc-200 underline underline-offset-2 transition-colors disabled:opacity-50"
                >
                  {t("settings.updates.backupPath.reset")}
                </button>
              )}
              <button
                type="button"
                onClick={() => void handlePickPath()}
                disabled={loading || busy}
                className="inline-flex items-center gap-1.5 h-8 px-3 rounded-md border border-zinc-200 bg-zinc-100 text-xs font-medium text-zinc-700 hover:bg-zinc-200 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-200 dark:hover:bg-zinc-700 transition-colors disabled:opacity-50"
              >
                <Folder className="h-3.5 w-3.5" />
                {t("settings.updates.backupPath.choose")}
              </button>
            </div>
          }
        />

        <SettingsItem
          label={t("settings.updates.backupNow.label")}
          description={t("settings.updates.backupNow.description")}
          action={
            <button
              type="button"
              onClick={() => void handleBackupNow()}
              disabled={loading || backingUp || !(settings?.backupBeforeUpdate ?? true)}
              className="inline-flex items-center gap-1.5 h-8 px-3 rounded-md bg-purple-600 text-xs font-medium text-white hover:bg-purple-500 transition-colors disabled:opacity-50"
            >
              {backingUp ? t("settings.updates.backupNow.running") : t("settings.updates.backupNow.action")}
            </button>
          }
        />
      </SettingsSection>
    </div>
  );
}
