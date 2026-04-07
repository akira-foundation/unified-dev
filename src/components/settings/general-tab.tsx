import { useState } from "react";
import { useToggle } from "@uidotdev/usehooks";
import { User, Check } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { useI18n } from "@/i18n/i18n";
import { useLicense } from "@/hooks/useLicense";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";

export function GeneralTab() {
  const { t, locale, setLocale } = useI18n();
  const { currentPlan, license } = useLicense();
  const [showPlans, toggleShowPlans] = useToggle(false);
  const [billingCycle, setBillingCycle] = useState<"monthly" | "yearly">("monthly");

  const handleUpgrade = async (plan: "pro" | "ultimate") => {
    const url = await invoke<string>("checkout_license", { plan, cycle: billingCycle });
    await openUrl(url);
  };

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection
        title={t("settings.general.account.title")}
        description={t("settings.general.account.description")}
        icon={User}
      >
        <div className="px-4 py-6 border-b border-zinc-100 dark:border-zinc-800/50">
          <div className="flex items-center justify-between mb-6">
            <div className="flex flex-row items-center gap-4">
              <div className="h-10 w-10 rounded-full bg-zinc-800 overflow-hidden shrink-0">
                <img src="https://github.com/shadcn.png" alt="Avatar" className="object-cover" />
              </div>
              <div className="flex flex-col">
                <div className="flex items-center gap-2">
                  <span className="text-[14px] text-zinc-900 dark:text-white font-medium">kid(akira)</span>
                  <span className={`text-[10px] px-1.5 py-0.5 rounded font-medium ${
                    currentPlan === "ultimate"
                      ? "bg-purple-500/10 text-purple-400"
                      : currentPlan === "pro"
                      ? "bg-blue-500/10 text-blue-400"
                      : "bg-zinc-500/10 text-zinc-400"
                  }`}>
                    {t(`settings.general.account.plan.${currentPlan}`)}
                  </span>
                </div>
                <span className="text-[13px] text-zinc-500">{license?.email ?? "kidiatoliny@akira-io.com"}</span>
              </div>
            </div>

          </div>

          <div className="p-5 rounded-md border border-zinc-100 bg-zinc-50 dark:border-white/5 dark:bg-white/[0.02]">
            <div className="flex items-center justify-between mb-3">
              <span className="text-[13px] text-zinc-500 dark:text-zinc-400 font-medium">
                {t("settings.general.account.plan.label")}
              </span>
              <span className={`text-[12px] font-bold px-2 py-0.5 rounded ${
                currentPlan === "ultimate"
                  ? "bg-purple-500/10 text-purple-400"
                  : currentPlan === "pro"
                  ? "bg-blue-500/10 text-blue-400"
                  : "bg-zinc-500/10 text-zinc-400"
              }`}>
                {t(`settings.general.account.plan.${currentPlan}`)}
              </span>
            </div>

            <ul className="space-y-2 mb-4">
              {currentPlan === "free" && (
                <>
                  <li className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-400">
                    <span className="text-zinc-500">–</span> {t("settings.general.account.plan.limit.runs")}
                  </li>
                  <li className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-400">
                    <span className="text-zinc-500">–</span> {t("settings.general.account.plan.limit.threads")}
                  </li>
                  <li className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-400">
                    <span className="text-zinc-500">–</span> {t("settings.general.account.plan.limit.local")}
                  </li>
                </>
              )}
              {currentPlan === "pro" && (
                <>
                  <li className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-300">
                    <span className="text-blue-500">✓</span> {t("settings.general.account.plan.limit.unlimited_runs")}
                  </li>
                  <li className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-300">
                    <span className="text-blue-500">✓</span> {t("settings.general.account.plan.limit.unlimited_threads")}
                  </li>
                  <li className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-400">
                    <span className="text-zinc-500">–</span> {t("settings.general.account.plan.limit.local")}
                  </li>
                </>
              )}
              {currentPlan === "ultimate" && (
                <>
                  <li className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-300">
                    <span className="text-purple-500">✓</span> {t("settings.general.account.plan.limit.unlimited_runs")}
                  </li>
                  <li className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-300">
                    <span className="text-purple-500">✓</span> {t("settings.general.account.plan.limit.unlimited_threads")}
                  </li>
                  <li className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-300">
                    <span className="text-purple-500">✓</span> {t("settings.general.account.plan.limit.remote")}
                  </li>
                  <li className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-300">
                    <span className="text-purple-500">✓</span> {t("settings.general.account.plan.limit.pairing")}
                  </li>
                </>
              )}
            </ul>

            {currentPlan !== "ultimate" && !showPlans && (
              <Button
                className="w-full"
                variant="default"
                onClick={() => toggleShowPlans(true)}
              >
                {t("settings.general.account.plan.upgrade")}
              </Button>
            )}

            {showPlans && (
              <div className="mt-4 animate-in fade-in duration-200">
                <div className="flex items-center justify-end gap-3 mb-4">
                  <span className={cn("text-xs font-medium transition-colors", billingCycle !== "yearly" ? "text-zinc-900 dark:text-white" : "text-zinc-400")}>
                    {t("upgrade.billing.monthly")}
                  </span>
                  <button
                    onClick={() => setBillingCycle(billingCycle === "yearly" ? "monthly" : "yearly")}
                    className={cn(
                      "relative inline-flex h-5 w-9 shrink-0 items-center rounded-full border transition-colors",
                      billingCycle === "yearly" ? "bg-primary border-primary" : "bg-zinc-700 border-zinc-600"
                    )}
                  >
                    <span className={cn(
                      "inline-block h-3.5 w-3.5 rounded-full bg-white shadow-sm transition-transform duration-200",
                      billingCycle === "yearly" ? "translate-x-[18px]" : "translate-x-0.5"
                    )} />
                  </button>
                  <span className={cn("text-xs font-medium flex items-center gap-1.5 transition-colors", billingCycle === "yearly" ? "text-zinc-900 dark:text-white" : "text-zinc-400")}>
                    {t("upgrade.billing.yearly")}
                    <span className="text-[10px] font-bold text-emerald-500 bg-emerald-500/10 px-1.5 py-0.5 rounded-full">
                      {t("upgrade.billing.discount")}
                    </span>
                  </span>
                </div>

                <div className="grid grid-cols-3 divide-x divide-zinc-100 dark:divide-white/5 rounded-md border border-zinc-100 dark:border-white/5 overflow-hidden">
                  {(["free", "pro", "ultimate"] as const).map((key) => {
                    const yearly = billingCycle === "yearly";
                    const planData = {
                      free:     { price: "0",  period: null, features: [t("upgrade.feature.free.1"), t("upgrade.feature.free.2"), t("upgrade.feature.free.3")] },
                      pro:      { price: yearly ? "12" : "15",  period: yearly ? t("upgrade.billing.billed_annually") : t("upgrade.billing.monthly"), features: [t("upgrade.feature.pro.1"), t("upgrade.feature.pro.2"), t("upgrade.feature.pro.3")] },
                      ultimate: { price: yearly ? "24" : "29",  period: yearly ? t("upgrade.billing.billed_annually") : t("upgrade.billing.monthly"), features: [t("upgrade.feature.ultimate.1"), t("upgrade.feature.ultimate.2"), t("upgrade.feature.ultimate.3"), t("upgrade.feature.ultimate.4")] },
                    }[key];
                    const isFeatured = key === "pro";
                    const isCurrent = currentPlan === key;

                    return (
                      <div key={key} className={cn("flex flex-col p-4", isFeatured && "bg-primary/[0.03]")}>
                        <div className="flex items-center gap-1.5 mb-3">
                          <span className="text-[13px] font-semibold text-zinc-900 dark:text-white">
                            {t(`upgrade.plan.${key}`)}
                          </span>
                          {isFeatured && (
                            <span className="text-[9px] font-black uppercase tracking-wider bg-primary text-primary-foreground px-1.5 py-0.5 rounded-full leading-none">
                              {t("upgrade.recommended")}
                            </span>
                          )}
                        </div>

                        <div className="flex items-baseline gap-0.5 mb-1">
                          <span className="text-xl font-black tracking-tight text-zinc-900 dark:text-white">{planData.price}</span>
                          <span className={cn("text-sm font-bold", isFeatured ? "text-primary" : "text-zinc-400")}>€</span>
                          {planData.period && (
                            <span className="text-[11px] text-zinc-500 ml-0.5">/{planData.period.toLowerCase()}</span>
                          )}
                        </div>

                        <ul className="space-y-1.5 mb-4 flex-1">
                          {planData.features.map((f) => (
                            <li key={f} className="flex items-start gap-1.5">
                              <Check size={11} className={cn("shrink-0 mt-0.5", isFeatured ? "text-primary" : "text-zinc-500")} strokeWidth={2.5} />
                              <span className={cn("text-[11px] leading-snug", isFeatured ? "text-zinc-900 dark:text-zinc-200" : "text-zinc-500")}>{f}</span>
                            </li>
                          ))}
                        </ul>

                        <button
                          disabled={isCurrent || key === "free"}
                          onClick={() => key !== "free" && !isCurrent && void handleUpgrade(key)}
                          className={cn(
                            "w-full h-7 rounded-md text-[11px] font-semibold transition-all active:scale-95",
                            isFeatured
                              ? "bg-primary text-primary-foreground hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed"
                              : "border border-zinc-200 dark:border-white/10 bg-transparent text-zinc-500 hover:text-zinc-900 dark:hover:text-white hover:bg-zinc-100 dark:hover:bg-white/5 disabled:opacity-40 disabled:cursor-not-allowed"
                          )}
                        >
                          {isCurrent ? t("upgrade.cta.free") : t(`upgrade.cta.${key}`)}
                        </button>
                      </div>
                    );
                  })}
                </div>

                <button
                  onClick={() => toggleShowPlans(false)}
                  className="mt-3 w-full text-[12px] text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 transition-colors"
                >
                  {t("common.cancel")}
                </button>
              </div>
            )}
          </div>
        </div>

        <SettingsItem
          label={t("settings.general.launchAtLogin.label")}
          description={t("settings.general.launchAtLogin.description")}
          action={<Switch />}
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
