import { useEffect, useState } from "react";
import { Bell } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { useI18n } from "@/i18n/i18n";
import { Switch } from "@/components/ui/switch";
import { SettingsSection } from "./settings-section";

interface NotificationPref {
  category: string;
  in_app: boolean;
  os_notify: boolean;
  updated_at: string;
}

interface CategoryMeta {
  key: string;
  label: string;
  description: string;
}

const CATEGORIES: CategoryMeta[] = [
  { key: "autopilot", label: "Autopilot", description: "Job started, completed, or failed." },
  { key: "pull_request", label: "Pull requests", description: "Review requests, comments, CI status." },
  { key: "issue", label: "Issues", description: "Assignments, comments, status changes." },
  { key: "sync", label: "Sync", description: "Repository, organization, and provider sync events." },
  { key: "workspace", label: "Workspace", description: "Long-running commands and draft PRs." },
  { key: "update", label: "Updates", description: "App and CLI tool updates available." },
  { key: "license", label: "License & billing", description: "Trial expiry, plan changes, payment issues." },
  { key: "auth", label: "Authentication", description: "Session expired, App reinstall needed." },
  { key: "skill", label: "Skills", description: "Skill discovery and installation events." },
  { key: "usage_limit", label: "Usage limits", description: "Free tier limit warnings and reached." },
];

export function NotificationsTab() {
  const { t } = useI18n();
  const [prefs, setPrefs] = useState<Record<string, NotificationPref>>({});
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    void load();
  }, []);

  async function load() {
    setLoading(true);
    try {
      const rows = await invoke<NotificationPref[]>("get_notification_prefs");
      const map: Record<string, NotificationPref> = {};
      for (const row of rows) map[row.category] = row;
      setPrefs(map);
    } finally {
      setLoading(false);
    }
  }

  function getPref(category: string): NotificationPref {
    return (
      prefs[category] ?? {
        category,
        in_app: true,
        os_notify: true,
        updated_at: "",
      }
    );
  }

  async function setPref(category: string, in_app: boolean, os_notify: boolean) {
    setPrefs((prev) => ({
      ...prev,
      [category]: { category, in_app, os_notify, updated_at: new Date().toISOString() },
    }));
    try {
      await invoke("set_notification_prefs", { category, inApp: in_app, osNotify: os_notify });
    } catch {
      void load();
    }
  }

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection
        title={t("settings.notifications.title")}
        description={t("settings.notifications.description")}
        icon={Bell}
      >
        <div className="px-4 py-3 border-b border-zinc-100 dark:border-zinc-800/50 grid grid-cols-[1fr_auto_auto] gap-x-6 text-[10px] uppercase font-bold tracking-wider text-zinc-500">
          <span>Category</span>
          <span className="text-center w-16">In-app</span>
          <span className="text-center w-16">System</span>
        </div>

        {loading ? (
          <div className="px-4 py-6 text-[12px] text-zinc-500">Loading…</div>
        ) : (
          CATEGORIES.map((cat) => {
            const pref = getPref(cat.key);
            return (
              <div
                key={cat.key}
                className="px-4 py-3 border-b border-zinc-100 dark:border-zinc-800/50 last:border-0 grid grid-cols-[1fr_auto_auto] gap-x-6 items-center"
              >
                <div>
                  <p className="text-[13px] font-medium text-zinc-200">{cat.label}</p>
                  <p className="text-[11px] text-zinc-500 mt-0.5">{cat.description}</p>
                </div>
                <div className="w-16 flex justify-center">
                  <Switch
                    checked={pref.in_app}
                    onCheckedChange={(checked) => void setPref(cat.key, checked, pref.os_notify)}
                  />
                </div>
                <div className="w-16 flex justify-center">
                  <Switch
                    checked={pref.os_notify}
                    onCheckedChange={(checked) => void setPref(cat.key, pref.in_app, checked)}
                  />
                </div>
              </div>
            );
          })
        )}
      </SettingsSection>
    </div>
  );
}
