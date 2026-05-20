import { User } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { useI18n } from "@/i18n/i18n";
import { useLicense } from "@/hooks/useLicense";
import { useLicenseStore } from "@/stores/license-store";
import { useOnboardingStore } from "@/stores/onboarding-store";
import { useAvatar } from "@/hooks/useAvatar";
// import { useNavigationStore } from "@/stores/navigation-store";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useAutostart } from "@/hooks/useAutostart";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";

const PLAN_COLOR: Record<string, string> = {
  free: "bg-zinc-500/10 text-zinc-400",
  pro: "bg-blue-500/10 text-blue-400",
  ultimate: "bg-purple-500/10 text-purple-400",
};

// Plan features + colors moved to Subscription tab (dynamic via billing SDK).
// Kept commented for future use if Account ever shows the current plan again.
// const PLAN_FEATURES: Record<string, string[]> = {
//   free: [
//     "settings.general.account.plan.limit.runs",
//     "settings.general.account.plan.limit.threads",
//     "settings.general.account.plan.limit.repos",
//     "settings.general.account.plan.limit.orgs",
//     "settings.general.account.plan.limit.local",
//     "settings.general.account.plan.limit.kanban",
//     "settings.general.account.plan.limit.pr_review",
//     "settings.general.account.plan.limit.community",
//   ],
//   pro: [
//     "settings.general.account.plan.limit.unlimited_runs",
//     "settings.general.account.plan.limit.unlimited_threads",
//     "settings.general.account.plan.limit.kanban",
//     "settings.general.account.plan.limit.pr_review",
//     "settings.general.account.plan.limit.priority",
//   ],
//   ultimate: [
//     "settings.general.account.plan.limit.unlimited_runs",
//     "settings.general.account.plan.limit.unlimited_threads",
//     "settings.general.account.plan.limit.remote",
//     "settings.general.account.plan.limit.pairing",
//   ],
// };
//
// const FEATURE_COLOR: Record<string, string> = {
//   free: "text-zinc-400",
//   pro: "text-blue-400",
//   ultimate: "text-purple-400",
// };

export function GeneralTab() {
  const { t, locale, setLocale } = useI18n();
  const { currentPlan, license, load } = useLicense();
  const avatarUrl = useAvatar(license?.email);
  const { clear } = useLicenseStore();
  const { enabled: autostartEnabled, loading: autostartLoading, toggle: toggleAutostart } = useAutostart();
  // const setSettingsTab = useNavigationStore((s) => s.setSettingsTab);

  // const handleManage = () => {
  //   setSettingsTab("subscription");
  // };

  const handleLogout = async () => {
    try {
      await invoke("oauth_logout");
      await load();
      useOnboardingStore.getState().requireAuth();
    } catch {
    }
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
              <span className={`text-[10px] px-1.5 py-0.5 rounded font-medium self-start ${PLAN_COLOR[currentPlan]}`}>
                {t(`settings.general.account.plan.${currentPlan}`)}
              </span>
              {license?.email && (
                <span className="text-[13px] text-zinc-500">{license.email}</span>
              )}
            </div>
            {license?.email && (
              <button
                onClick={() => void handleLogout()}
                className="ml-auto text-[11px] text-zinc-400 hover:text-red-400 underline underline-offset-2 transition-colors"
              >
                {t("settings.general.account.plan.logout")}
              </button>
            )}
          </div>

          {/* Current plan block moved to Subscription tab — keep here commented for future reuse.
          <div className="p-4 rounded-md border border-zinc-100 dark:border-white/5 bg-zinc-50 dark:bg-white/[0.02]">
            <div className="flex items-center justify-between mb-3">
              <span className="text-[13px] font-medium text-zinc-500 dark:text-zinc-400">
                {t("settings.general.account.plan.label")}
              </span>
              <div className="flex items-center gap-2">
                <span className={`text-[11px] font-bold px-2 py-0.5 rounded ${PLAN_COLOR[currentPlan]}`}>
                  {t(`settings.general.account.plan.${currentPlan}`)}
                </span>
                {currentPlan !== "free" && (
                  <button
                    onClick={handleManage}
                    className="text-[11px] text-zinc-400 hover:text-zinc-200 underline underline-offset-2 transition-colors"
                  >
                    {t("settings.general.account.plan.manage")}
                  </button>
                )}
              </div>
            </div>

            <ul className="space-y-1.5">
              {PLAN_FEATURES[currentPlan].map((key) => (
                <li key={key} className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-400">
                  <span className={FEATURE_COLOR[currentPlan]}>✓</span>
                  {t(key)}
                </li>
              ))}
            </ul>
          </div>
          */}
        </div>

        {import.meta.env.DEV && currentPlan !== "free" && (
          <div className="px-4 py-3 border-b border-zinc-100 dark:border-zinc-800/50 flex items-center justify-between">
            <span className="text-[12px] text-zinc-400">Dev: reset license</span>
            <button
              onClick={() => void clear()}
              className="text-[11px] text-red-400 hover:text-red-500 transition-colors font-medium"
            >
              Clear
            </button>
          </div>
        )}

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
