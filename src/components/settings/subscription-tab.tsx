import { useEffect, useState } from "react";
import { CreditCard, User } from "lucide-react";
import { toast } from "sonner";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { useI18n } from "@/i18n/i18n";
import { useLicense } from "@/hooks/useLicense";
import { useLicenseStore } from "@/stores/license-store";
import { useOnboardingStore } from "@/stores/onboarding-store";
import { useAvatar } from "@/hooks/useAvatar";
import { SettingsSection } from "./settings-section";
import { PlanCard } from "./subscription/plan-card";
import { InvoicesSection } from "./subscription/invoices-section";
import {
  BillingCycle,
  extractTier,
  findPlan,
  InvoiceDto,
  InvoicesPageDto,
  PLAN_COLOR,
  ProductPlansDto,
  TIER_ORDER,
} from "./subscription/subscription-types";

export function SubscriptionTab() {
  const { t, locale } = useI18n();
  const { currentPlan, license } = useLicense();
  const { load, verify } = useLicenseStore();
  const avatarUrl = useAvatar(license?.email);
  const [cycle, setCycle] = useState<BillingCycle>("monthly");
  const [loadingPlan, setLoadingPlan] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [downgrading, setDowngrading] = useState<"free" | "pro" | null>(null);
  const [resuming, setResuming] = useState(false);
  const [productPlans, setProductPlans] = useState<ProductPlansDto | null>(null);

  useEffect(() => {
    invoke<ProductPlansDto>("get_product_plans")
      .then(setProductPlans)
      .catch(() => setProductPlans(null));
  }, []);

  const tiers = productPlans
    ? Array.from(new Set(productPlans.plans.map((p) => extractTier(p.key)))).sort(
        (a, b) => (TIER_ORDER[a] ?? 99) - (TIER_ORDER[b] ?? 99),
      )
    : [];

  const cancelAtPeriodEnd = license?.cancelAtPeriodEnd ?? false;
  const cancelAt = license?.cancelAt ?? null;
  const targetPlan = license?.targetPlan ?? null;

  const [invoices, setInvoices] = useState<InvoiceDto[]>([]);
  const [invoicesLoading, setInvoicesLoading] = useState(false);
  const [invoicesError, setInvoicesError] = useState<string | null>(null);
  const [invoicesHasMore, setInvoicesHasMore] = useState(false);
  const [invoicesCursor, setInvoicesCursor] = useState<string | null>(null);

  const fetchInvoices = (cursor: string | null) => {
    setInvoicesLoading(true);
    setInvoicesError(null);
    invoke<InvoicesPageDto>("list_invoices", { cursor })
      .then((page) => {
        setInvoices((prev) => cursor ? [...prev, ...page.invoices] : page.invoices);
        setInvoicesHasMore(page.hasMore);
        setInvoicesCursor(page.nextCursor);
      })
      .catch((err: unknown) => setInvoicesError(String(err)))
      .finally(() => setInvoicesLoading(false));
  };

  useEffect(() => {
    if (currentPlan === "free") return;
    fetchInvoices(null);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentPlan]);

  useEffect(() => {
    void verify();
  }, [verify]);

  const handleManage = async () => {
    try {
      const url = await invoke<string>("manage_license");
      await openUrl(url);
    } catch {
      toast.error(t("settings.subscription.manage.error"));
    }
  };

  const handleLogout = async () => {
    try {
      await invoke("oauth_logout");
      await load();
      useOnboardingStore.getState().requireAuth();
    } catch {
    }
  };

  const handleDowngrade = async (target: "free" | "pro") => {
    setDowngrading(target);
    setError(null);
    try {
      await invoke("downgrade_license", { targetPlan: target });
      await load();
      toast.success(t("settings.subscription.downgrade.success"));
    } catch {
      setError(t("settings.subscription.downgrade.error"));
      toast.error(t("settings.subscription.downgrade.error"));
    } finally {
      setDowngrading(null);
    }
  };

  const handleResume = async () => {
    setResuming(true);
    try {
      await invoke("resume_license");
      await load();
      toast.success(t("settings.subscription.resume.success"));
    } catch {
      toast.error(t("settings.subscription.resume.error"));
    } finally {
      setResuming(false);
    }
  };

  const handleUpgrade = async (tier: "pro" | "ultimate") => {
    const plan = productPlans ? findPlan(tier, cycle, productPlans.plans) : undefined;
    if (!plan) return;
    setLoadingPlan(tier);
    setError(null);
    try {
      const url = await invoke<string>("checkout_url", { planKey: plan.key });
      await openUrl(url);
    } catch {
      setError(t("upgrade.error.checkout"));
    } finally {
      setLoadingPlan(null);
    }
  };

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection
        title={t("settings.tabs.subscription")}
        description={t("settings.subscription.description")}
        icon={CreditCard}
      >
        <div className="px-4 py-5 border-b border-zinc-100 dark:border-zinc-800/50">
          <div className="flex items-start gap-3 mb-4">
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
              <div className="flex items-center gap-1.5">
                <span className={`text-[10px] px-1.5 py-0.5 rounded font-medium self-start border ${PLAN_COLOR[currentPlan]}`}>
                  {t(`settings.general.account.plan.${currentPlan}`)}
                </span>
                {cancelAtPeriodEnd && cancelAt && (
                  <span className="text-[10px] px-1.5 py-0.5 rounded font-medium border bg-amber-500/10 text-amber-400 border-amber-500/20 whitespace-nowrap">
                    {targetPlan === "pro"
                      ? t("settings.subscription.downgrade.to_pro") + " · " + new Date(cancelAt).toLocaleDateString()
                      : t("settings.subscription.downgrade.cancels_on", { date: new Date(cancelAt).toLocaleDateString() })}
                  </span>
                )}
                {cancelAtPeriodEnd && (
                  <button
                    onClick={() => void handleResume()}
                    disabled={resuming}
                    className="text-[10px] px-1.5 py-0.5 rounded font-medium border border-zinc-300 dark:border-zinc-700 text-zinc-600 dark:text-zinc-300 hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors disabled:opacity-50"
                  >
                    {resuming ? t("settings.subscription.resume.resuming") : t("settings.subscription.resume.action")}
                  </button>
                )}
              </div>
              {license?.validUntil && currentPlan !== "free" && !cancelAtPeriodEnd && (
                <span className="text-[11px] text-zinc-500">
                  {t("settings.subscription.downgrade.renews_on", { date: new Date(license.validUntil).toLocaleDateString() })}
                </span>
              )}
              {license?.email && (
                <span className="text-[13px] text-zinc-500">{license.email}</span>
              )}
            </div>
            <div className="ml-auto flex items-center gap-3">
              {currentPlan !== "free" && (
                <button
                  onClick={() => void handleManage()}
                  className="text-[11px] text-zinc-400 hover:text-zinc-200 underline underline-offset-2 transition-colors"
                >
                  {t("settings.general.account.plan.manage")}
                </button>
              )}
              {license?.email && (
                <button
                  onClick={() => void handleLogout()}
                  className="text-[11px] text-zinc-400 hover:text-red-400 underline underline-offset-2 transition-colors"
                >
                  {t("settings.general.account.plan.logout")}
                </button>
              )}
            </div>
          </div>

          <div className="flex items-center justify-center gap-1 p-1 rounded-md bg-zinc-100 dark:bg-zinc-800/60 w-fit mx-auto mb-5">
            <button
              onClick={() => setCycle("monthly")}
              className={`px-4 py-1.5 rounded text-[12px] font-medium transition-all ${
                cycle === "monthly"
                  ? "bg-white dark:bg-zinc-700 text-zinc-900 dark:text-white shadow-sm"
                  : "text-zinc-500 dark:text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-300"
              }`}
            >
              {t("upgrade.billing.monthly")}
            </button>
            <button
              onClick={() => setCycle("yearly")}
              className={`px-4 py-1.5 rounded text-[12px] font-medium transition-all flex items-center gap-1.5 ${
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
            {tiers.map((tier) => {
              const plan = productPlans ? findPlan(tier, cycle, productPlans.plans) : undefined;
              if (!plan) return null;
              return (
                <PlanCard
                  key={tier}
                  tier={tier}
                  plan={plan}
                  currentPlan={currentPlan}
                  locale={locale}
                  loadingPlan={loadingPlan}
                  downgrading={downgrading}
                  cancelAtPeriodEnd={cancelAtPeriodEnd}
                  onUpgrade={handleUpgrade}
                  onDowngrade={handleDowngrade}
                />
              );
            })}
          </div>

          {error && (
            <p className="text-center text-[11px] text-red-500 mt-3">{error}</p>
          )}
        </div>

        {currentPlan !== "free" && (
          <InvoicesSection
            invoices={invoices}
            loading={invoicesLoading}
            error={invoicesError}
            hasMore={invoicesHasMore}
            onLoadMore={() => fetchInvoices(invoicesCursor)}
          />
        )}
      </SettingsSection>
    </div>
  );
}
