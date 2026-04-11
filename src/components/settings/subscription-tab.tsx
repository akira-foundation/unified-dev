import { useState } from "react";
import { CreditCard } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { useI18n } from "@/i18n/i18n";
import { useLicense } from "@/hooks/useLicense";
import { useLicenseStore } from "@/stores/license-store";
import { useCheckoutPoller } from "@/hooks/useCheckoutPoller";
import { SettingsSection } from "./settings-section";

interface CheckoutDto {
  url: string;
  sessionId: string;
}

type BillingCycle = "monthly" | "yearly";

const PLAN_PRICE: Record<string, Record<BillingCycle, string>> = {
  free: { monthly: "€0", yearly: "€0" },
  pro: { monthly: "€15", yearly: "€150" },
  ultimate: { monthly: "€29", yearly: "€290" },
};

const PLAN_FEATURES: Record<string, string[]> = {
  free: [
    "upgrade.feature.free.1",
    "upgrade.feature.free.2",
    "upgrade.feature.free.3",
    "upgrade.feature.free.4",
    "upgrade.feature.free.5",
    "upgrade.feature.free.6",
    "upgrade.feature.free.7",
    "upgrade.feature.free.8",
  ],
  pro: [
    "upgrade.feature.pro.1",
    "upgrade.feature.pro.2",
    "upgrade.feature.pro.3",
    "upgrade.feature.pro.4",
    "upgrade.feature.pro.5",
    "upgrade.feature.pro.6",
  ],
  ultimate: [
    "upgrade.feature.ultimate.1",
    "upgrade.feature.ultimate.2",
    "upgrade.feature.ultimate.3",
    "upgrade.feature.ultimate.4",
  ],
};

const PLAN_COLOR: Record<string, string> = {
  free: "bg-zinc-500/10 text-zinc-400 border-zinc-500/20",
  pro: "bg-blue-500/10 text-blue-400 border-blue-500/20",
  ultimate: "bg-purple-500/10 text-purple-400 border-purple-500/20",
};

const FEATURE_CHECK_COLOR: Record<string, string> = {
  free: "text-zinc-400",
  pro: "text-blue-400",
  ultimate: "text-purple-400",
};

export function SubscriptionTab() {
  const { t } = useI18n();
  const { currentPlan, license } = useLicense();
  const { load } = useLicenseStore();
  const [cycle, setCycle] = useState<BillingCycle>("monthly");
  const [loadingPlan, setLoadingPlan] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pollSessionId, setPollSessionId] = useState<string | null>(null);

  useCheckoutPoller(pollSessionId, () => {
    setPollSessionId(null);
    void load();
  });

  const handleManage = async () => {
    try {
      const url = await invoke<string>("manage_license");
      await openUrl(url);
    } catch {
    }
  };

  const handleUpgrade = async (plan: "pro" | "ultimate") => {
    setLoadingPlan(plan);
    setError(null);
    try {
      const checkout = await invoke<CheckoutDto>("checkout_license", { plan, cycle });
      await openUrl(checkout.url);
      setPollSessionId(checkout.sessionId);
    } catch {
      setError(t("upgrade.error.checkout"));
    } finally {
      setLoadingPlan(null);
    }
  };

  const plans = ["free", "pro", "ultimate"] as const;
  const planOrder = { free: 0, pro: 1, ultimate: 2 };

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection
        title={t("settings.tabs.subscription")}
        description={t("settings.subscription.description")}
        icon={CreditCard}
      >
        <div className="px-4 py-5 border-b border-zinc-100 dark:border-zinc-800/50">
          <div className="flex items-center gap-3 mb-4">
            <div className="h-9 w-9 rounded-full bg-zinc-800 overflow-hidden shrink-0">
              <img src="https://github.com/shadcn.png" alt="Avatar" className="object-cover" />
            </div>
            <div className="flex flex-col gap-0.5">
              <span className={`text-[10px] px-1.5 py-0.5 rounded font-medium self-start border ${PLAN_COLOR[currentPlan]}`}>
                {t(`settings.general.account.plan.${currentPlan}`)}
              </span>
              {license?.email && (
                <span className="text-[13px] text-zinc-500">{license.email}</span>
              )}
            </div>
            {currentPlan !== "free" && (
              <button
                onClick={() => void handleManage()}
                className="ml-auto text-[11px] text-zinc-400 hover:text-zinc-200 underline underline-offset-2 transition-colors"
              >
                {t("settings.general.account.plan.manage")}
              </button>
            )}
          </div>

          <div className="flex items-center justify-center gap-1 p-1 rounded-lg bg-zinc-100 dark:bg-zinc-800/60 w-fit mx-auto mb-5">
            <button
              onClick={() => setCycle("monthly")}
              className={`px-4 py-1.5 rounded-md text-[12px] font-medium transition-all ${
                cycle === "monthly"
                  ? "bg-white dark:bg-zinc-700 text-zinc-900 dark:text-white shadow-sm"
                  : "text-zinc-500 dark:text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-300"
              }`}
            >
              {t("upgrade.billing.monthly")}
            </button>
            <button
              onClick={() => setCycle("yearly")}
              className={`px-4 py-1.5 rounded-md text-[12px] font-medium transition-all flex items-center gap-1.5 ${
                cycle === "yearly"
                  ? "bg-white dark:bg-zinc-700 text-zinc-900 dark:text-white shadow-sm"
                  : "text-zinc-500 dark:text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-300"
              }`}
            >
              {t("upgrade.billing.yearly")}
              <span className="text-[10px] font-semibold text-green-500">{t("upgrade.billing.discount")}</span>
            </button>
          </div>

          <div className="grid grid-cols-3 gap-3">
            {plans.map((plan) => {
              const isCurrentPlan = currentPlan === plan;
              const isUpgradeable = planOrder[plan] > planOrder[currentPlan];
              const price = PLAN_PRICE[plan][cycle];
              const isLoading = loadingPlan === plan;

              return (
                <div
                  key={plan}
                  className={`relative flex flex-col rounded-lg border bg-white dark:bg-zinc-900 p-4 ${isCurrentPlan ? "border-purple-500/40 ring-1 ring-purple-500/30" : "border-zinc-200 dark:border-zinc-800"}`}
                >
                  {plan === "pro" && (
                    <span className="absolute -top-2.5 left-1/2 -translate-x-1/2 text-[10px] font-bold px-2 py-0.5 rounded-full bg-purple-500 text-white whitespace-nowrap">
                      {t("upgrade.recommended")}
                    </span>
                  )}

                  <div className="mb-3">
                    <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded border ${PLAN_COLOR[plan]}`}>
                      {t(`upgrade.plan.${plan}`)}
                    </span>
                  </div>

                  <div className="mb-1">
                    <span className="text-[22px] font-bold text-zinc-900 dark:text-white">{price}</span>
                    {plan !== "free" && (
                      <span className="text-[11px] text-zinc-400 ml-1">
                        {cycle === "yearly" ? `/${t("upgrade.billing.billed_annually")}` : "/mo"}
                      </span>
                    )}
                  </div>

                  <p className="text-[12px] text-zinc-500 dark:text-zinc-400 mb-4 leading-snug">
                    {t(`upgrade.desc.${plan}`)}
                  </p>

                  <ul className="space-y-1.5 mb-5 flex-1">
                    {PLAN_FEATURES[plan].map((key) => (
                      <li key={key} className="flex items-start gap-1.5 text-[12px] text-zinc-600 dark:text-zinc-400">
                        <span className={`mt-px shrink-0 ${FEATURE_CHECK_COLOR[plan]}`}>✓</span>
                        {t(key)}
                      </li>
                    ))}
                  </ul>

                  {isCurrentPlan ? (
                    <div className="text-center text-[12px] font-medium text-purple-400 py-1.5 rounded-md border border-purple-500/30 bg-purple-500/5">
                      {t("upgrade.cta.free")}
                    </div>
                  ) : isUpgradeable ? (
                    <button
                      onClick={() => void handleUpgrade(plan as "pro" | "ultimate")}
                      disabled={isLoading}
                      className="text-[12px] font-semibold py-1.5 px-3 rounded-md bg-purple-500 hover:bg-purple-600 text-white transition-colors disabled:opacity-60"
                    >
                      {isLoading ? t("upgrade.cta.loading") : t(`upgrade.cta.${plan}`)}
                    </button>
                  ) : null}
                </div>
              );
            })}
          </div>

          {error && (
            <p className="text-center text-[11px] text-red-500 mt-3">{error}</p>
          )}
        </div>
      </SettingsSection>
    </div>
  );
}
