import { useEffect, useState } from "react";
import { User } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { useI18n } from "@/i18n/i18n";
import { useOnboardingStore } from "@/stores/onboarding-store";
import { useAvatar } from "@/hooks/useAvatar";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useAutostart } from "@/hooks/useAutostart";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";

interface UserProfileDto {
  email: string;
}

export function GeneralTab() {
  const { t, locale, setLocale } = useI18n();
  const [email, setEmail] = useState<string | undefined>();
  const avatarUrl = useAvatar(email);
  const { enabled: autostartEnabled, loading: autostartLoading, toggle: toggleAutostart } = useAutostart();

  useEffect(() => {
    void (async () => {
      try {
        const profile = await invoke<UserProfileDto | null>("get_user_profile");
        setEmail(profile?.email);
      } catch {
      }
    })();
  }, []);

  const handleLogout = () => {
    toast.loading(t("settings.general.account.plan.signingOut"), { id: "logout" });
    setTimeout(() => {
      toast.dismiss("logout");
      useOnboardingStore.getState().requireAuth();
      void (async () => {
        try {
          await invoke("oauth_logout");
        } catch {
        }
      })();
    }, 500);
  };

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection
        title={t("settings.general.account.title")}
        description={t("settings.general.account.description")}
        icon={User}
      >
        <div className="px-4 py-5 border-b border-zinc-100 dark:border-zinc-800/50">
          <div className="flex items-center gap-3 mb-5">
            <div className="h-9 w-9 rounded-full bg-zinc-800 overflow-hidden shrink-0">
              {avatarUrl ? (
                <img src={avatarUrl} alt="Avatar" className="h-full w-full object-cover" />
              ) : (
                <div className="h-full w-full flex items-center justify-center text-zinc-500">
                  <User className="h-4 w-4" />
                </div>
              )}
            </div>
            <div className="flex flex-col gap-0.5">
              {email && (
                <span className="text-[13px] text-zinc-500">{email}</span>
              )}
            </div>
            {email && (
              <button
                onClick={() => void handleLogout()}
                className="ml-auto text-[11px] text-zinc-400 hover:text-red-400 underline underline-offset-2 transition-colors"
              >
                {t("settings.general.account.plan.logout")}
              </button>
            )}
          </div>
        </div>

        <SettingsItem
          label={t("settings.general.launchAtLogin.label")}
          description={t("settings.general.launchAtLogin.description")}
          action={
            <Switch
              checked={autostartEnabled}
              onCheckedChange={(v) => void toggleAutostart(v)}
              disabled={autostartLoading}
            />
          }
        />

        <SettingsItem
          label={t("settings.general.language")}
          description={t("settings.general.languageValue")}
          action={
            <Select value={locale} onValueChange={(value: string) => setLocale(value as any)}>
              <SelectTrigger className="h-8 w-40 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="en">{t("settings.general.languageEnglish")}</SelectItem>
                <SelectItem value="pt-PT">{t("settings.general.languagePortuguese")}</SelectItem>
              </SelectContent>
            </Select>
          }
        />
      </SettingsSection>
    </div>
  );
}
