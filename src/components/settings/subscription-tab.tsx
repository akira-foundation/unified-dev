import { useEffect, useRef, useState } from "react";
import { CreditCard } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { z } from "zod";
import { useI18n } from "@/i18n/i18n";
import { useLicense } from "@/hooks/useLicense";
import { useLicenseStore } from "@/stores/license-store";
import { useOnboardingStore } from "@/stores/onboarding-store";
import { useCheckoutPoller } from "@/hooks/useCheckoutPoller";
import { SettingsSection } from "./settings-section";

interface CheckoutDto {
  url: string;
  sessionId: string;
}

interface PlanFeatureDto {
  key: string;
  name: string;
  description: string | null;
}

interface PlanDto {
  id: string;
  key: string;
  name: string;
  description: string | null;
  amount: number | null;
  currency: string | null;
  billing_interval: string | null;
  trial_period_days: number;
  is_coming_soon: boolean;
  features: PlanFeatureDto[];
}

interface ProductPlansDto {
  product: string;
  name: string;
  description: string | null;
  landing_url: string | null;
  beta_ends_at: string | null;
  beta_active: boolean;
  plans: PlanDto[];
}

function extractTier(key: string): string {
  return key.replace(/_monthly$|_yearly$/, "");
}

function findPlan(tier: string, cycle: BillingCycle, plans: PlanDto[]): PlanDto | undefined {
  if (tier === "free") return plans.find((p) => p.key === "free");
  const interval = cycle === "yearly" ? "year" : "month";
  return plans.find((p) => extractTier(p.key) === tier && p.billing_interval === interval);
}

function formatPrice(amount: number | null | undefined, currency: string | null | undefined, locale: string): string {
  if (amount == null) return "—";
  const value = amount / 100;
  if (currency) {
    try {
      return new Intl.NumberFormat(locale, { style: "currency", currency: currency.toUpperCase(), maximumFractionDigits: 0 }).format(value);
    } catch {
    }
  }
  return value === 0 ? "€0" : `€${value}`;
}

const TIER_COLOR: Record<string, string> = {
  free: "bg-zinc-500/10 text-zinc-400 border-zinc-500/20",
  pro: "bg-blue-500/10 text-blue-400 border-blue-500/20",
  ultimate: "bg-purple-500/10 text-purple-400 border-purple-500/20",
};

const TIER_CHECK_COLOR: Record<string, string> = {
  free: "text-zinc-400",
  pro: "text-blue-400",
  ultimate: "text-purple-400",
};

const TIER_ORDER: Record<string, number> = { free: 0, pro: 1, ultimate: 2 };

const RECOMMENDED_TIER = "pro";

interface InvoiceDto {
  id: string;
  number: string | null;
  amount: number;
  currency: string;
  date: string;
  pdfUrl: string | null;
  hostedUrl: string | null;
}

interface InvoicesPageDto {
  invoices: InvoiceDto[];
  hasMore: boolean;
  nextCursor: string | null;
}

type BillingCycle = "monthly" | "yearly";
type ClaimStep = "idle" | "sending" | "sent" | "verifying";

const PLAN_COLOR: Record<string, string> = {
  free: "bg-zinc-500/10 text-zinc-400 border-zinc-500/20",
  pro: "bg-blue-500/10 text-blue-400 border-blue-500/20",
  ultimate: "bg-purple-500/10 text-purple-400 border-purple-500/20",
};

const RESEND_COOLDOWN = 60;

const emailSchema = z.string().email();

function resolveClaimError(err: unknown, t: (key: string, vars?: Record<string, string>) => string): string {
  const msg = String(err);
  if (msg.includes("rate_limit")) {
    const match = msg.match(/rate_limit_exceeded:(\d+)/);
    if (match) {
      const seconds = parseInt(match[1], 10);
      const minutes = Math.ceil(seconds / 60);
      return t("settings.subscription.claim.error.rate_limit_timed", { minutes: String(minutes) });
    }
    return t("settings.subscription.claim.error.rate_limit");
  }
  if (msg.includes("otp_invalid")) return t("settings.subscription.claim.error.otp_invalid");
  if (msg.includes("otp_expired")) return t("settings.subscription.claim.error.otp_expired");
  if (msg.includes("otp_brute_force")) return t("settings.subscription.claim.error.otp_brute_force");
  if (msg.includes("license_expired")) return t("settings.subscription.claim.error.license_expired");
  if (msg.includes("device_limit_reached")) return t("settings.subscription.claim.error.device_limit");
  return t("settings.subscription.claim.error.generic");
}

export function SubscriptionTab() {
  const { t, locale } = useI18n();
  const { currentPlan, license } = useLicense();
  const { load } = useLicenseStore();
  const [cycle, setCycle] = useState<BillingCycle>("monthly");
  const [loadingPlan, setLoadingPlan] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pollSessionId, setPollSessionId] = useState<string | null>(null);
  const [downgrading, setDowngrading] = useState<"free" | "pro" | null>(null);
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

  const [claimStep, setClaimStep] = useState<ClaimStep>("idle");
  const [claimEmail, setClaimEmail] = useState("");
  const [claimOtp, setClaimOtp] = useState("");
  const [claimError, setClaimError] = useState<string | null>(null);
  const [resendCountdown, setResendCountdown] = useState(0);
  const countdownRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useCheckoutPoller(pollSessionId, () => {
    setPollSessionId(null);
    void load();
  });

  useEffect(() => {
    return () => {
      if (countdownRef.current) clearInterval(countdownRef.current);
    };
  }, []);

  function startResendCountdown() {
    setResendCountdown(RESEND_COOLDOWN);
    countdownRef.current = setInterval(() => {
      setResendCountdown((prev) => {
        if (prev <= 1) {
          clearInterval(countdownRef.current!);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
  }

  const handleManage = async () => {
    try {
      const url = await invoke<string>("manage_license");
      await openUrl(url);
    } catch {
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

  const handleDowngrade = async (targetPlan: "free" | "pro") => {
    setDowngrading(targetPlan);
    setError(null);
    try {
      await invoke("downgrade_license", { targetPlan });
      await load();
    } catch {
      setError(t("settings.subscription.downgrade.error"));
    } finally {
      setDowngrading(null);
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

  const handleSendCode = async () => {
    const email = claimEmail.trim();
    if (!email) return;

    const result = emailSchema.safeParse(email);
    if (!result.success) {
      setClaimError(t("settings.subscription.claim.error.invalid_email"));
      return;
    }

    setClaimStep("sending");
    setClaimError(null);
    try {
      await invoke("claim_license_request", { email });
      setClaimStep("sent");
      startResendCountdown();
    } catch (err) {
      setClaimError(resolveClaimError(err, t));
      setClaimStep("idle");
    }
  };

  const handleVerifyOtp = async () => {
    const email = claimEmail.trim();
    const otp = claimOtp.trim();
    if (!email || !otp) return;
    setClaimStep("verifying");
    setClaimError(null);
    try {
      await invoke("claim_license_verify", { email, otp });
      await load();
      setClaimStep("idle");
      setClaimEmail("");
      setClaimOtp("");
    } catch (err) {
      setClaimError(resolveClaimError(err, t));
      setClaimStep("sent");
    }
  };

  const handleResend = async () => {
    if (resendCountdown > 0) return;
    setClaimError(null);
    setClaimOtp("");
    await handleSendCode();
  };

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

              const isCurrentPlan = currentPlan === tier;
              const isUpgradeable = (TIER_ORDER[tier] ?? 99) > (TIER_ORDER[currentPlan] ?? 0);
              const price = formatPrice(plan.amount, plan.currency, locale);
              const isLoading = loadingPlan === tier;
              const isFree = tier === "free";

              return (
                <div
                  key={tier}
                  className={`relative flex flex-col rounded-lg border bg-white dark:bg-zinc-900 p-4 ${isCurrentPlan ? "border-purple-500/40 ring-1 ring-purple-500/30" : "border-zinc-200 dark:border-zinc-800"}`}
                >
                  {tier === RECOMMENDED_TIER && (
                    <span className="absolute -top-2.5 left-1/2 -translate-x-1/2 text-[10px] font-bold px-2 py-0.5 rounded bg-purple-500 text-white whitespace-nowrap">
                      {t("upgrade.recommended")}
                    </span>
                  )}

                  <div className="mb-3">
                    <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded border ${TIER_COLOR[tier] ?? TIER_COLOR.free}`}>
                      {plan.name}
                    </span>
                  </div>

                  <div className="mb-1">
                    <span className="text-[22px] font-bold text-zinc-900 dark:text-white">{price}</span>
                    {!isFree && (
                      <span className="text-[11px] text-zinc-400 ml-1">
                        {plan.billing_interval === "year" ? `/${t("upgrade.billing.billed_annually")}` : "/mo"}
                      </span>
                    )}
                  </div>

                  {plan.description && (
                    <p className="text-[12px] text-zinc-500 dark:text-zinc-400 mb-4 leading-snug">
                      {plan.description}
                    </p>
                  )}

                  <ul className="space-y-1.5 mb-5 flex-1">
                    {plan.features.map((feature) => (
                      <li key={feature.key} className="flex items-start gap-1.5 text-[12px] text-zinc-600 dark:text-zinc-400">
                        <span className={`mt-px shrink-0 ${TIER_CHECK_COLOR[tier] ?? TIER_CHECK_COLOR.free}`}>✓</span>
                        {feature.name}
                      </li>
                    ))}
                  </ul>

                  {isCurrentPlan ? (
                    <div className="text-center text-[12px] font-medium text-purple-400 py-1.5 rounded-md border border-purple-500/30 bg-purple-500/5">
                      {t("upgrade.cta.free")}
                    </div>
                  ) : plan.is_coming_soon ? (
                    <button
                      disabled
                      className="text-[12px] font-semibold py-1.5 px-3 rounded-md bg-zinc-700/50 text-zinc-500 cursor-not-allowed border border-zinc-700"
                    >
                      Coming soon
                    </button>
                  ) : isUpgradeable ? (
                    <button
                      onClick={() => void handleUpgrade(tier as "pro" | "ultimate")}
                      disabled={isLoading}
                      className="text-[12px] font-semibold py-1.5 px-3 rounded-md bg-purple-500 hover:bg-purple-600 text-white transition-colors disabled:opacity-60"
                    >
                      {isLoading ? t("upgrade.cta.loading") : t(`upgrade.cta.${tier}`)}
                    </button>
                  ) : tier === "pro" && currentPlan === "ultimate" && !cancelAtPeriodEnd ? (
                    <button
                      onClick={() => void handleDowngrade("pro")}
                      disabled={downgrading !== null}
                      className="text-[12px] font-medium py-1.5 px-3 rounded-md border border-zinc-600 text-zinc-400 hover:text-zinc-200 hover:border-zinc-500 transition-colors disabled:opacity-60"
                    >
                      {downgrading === "pro" ? t("settings.subscription.downgrade.downgrading") : t("settings.subscription.downgrade.to_pro")}
                    </button>
                  ) : tier === "free" && currentPlan !== "free" && !cancelAtPeriodEnd ? (
                    <button
                      onClick={() => void handleDowngrade("free")}
                      disabled={downgrading !== null}
                      className="text-[12px] font-medium py-1.5 px-3 rounded-md border border-zinc-600 text-zinc-400 hover:text-zinc-200 hover:border-zinc-500 transition-colors disabled:opacity-60"
                    >
                      {downgrading === "free" ? t("settings.subscription.downgrade.downgrading") : t("settings.subscription.downgrade.confirm")}
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

        {currentPlan === "free" && (
          <div className="px-4 py-4">
            <p className="text-[12px] font-semibold text-zinc-500 dark:text-zinc-400 mb-3">
              {t("settings.subscription.claim.title")}
            </p>

            {claimStep === "idle" || claimStep === "sending" ? (
              <div className="flex flex-col gap-2">
                <label className="text-[11px] text-zinc-500">{t("settings.subscription.claim.email_label")}</label>
                <div className="flex gap-2">
                  <input
                    type="email"
                    value={claimEmail}
                    onChange={(e) => setClaimEmail(e.target.value)}
                    placeholder={t("settings.subscription.claim.email_placeholder")}
                    className="flex-1 text-[12px] px-3 py-1.5 rounded-md border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-zinc-900 dark:text-white placeholder-zinc-400 focus:outline-none focus:ring-1 focus:ring-purple-500/50"
                  />
                  <button
                    onClick={() => void handleSendCode()}
                    disabled={claimStep === "sending" || !claimEmail.trim()}
                    className="text-[12px] font-medium px-3 py-1.5 rounded-md bg-purple-500 hover:bg-purple-600 text-white transition-colors disabled:opacity-50 whitespace-nowrap"
                  >
                    {claimStep === "sending"
                      ? t("settings.subscription.claim.sending")
                      : t("settings.subscription.claim.send_code")}
                  </button>
                </div>
              </div>
            ) : (
              <div className="flex flex-col gap-2">
                <p className="text-[11px] text-zinc-500">
                  {t("settings.subscription.claim.code_sent_to")}{" "}
                  <span className="text-zinc-300 font-medium">{claimEmail}</span>
                </p>
                <label className="text-[11px] text-zinc-500">{t("settings.subscription.claim.otp_label")}</label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    inputMode="numeric"
                    maxLength={6}
                    value={claimOtp}
                    onChange={(e) => setClaimOtp(e.target.value.replace(/\D/g, ""))}
                    placeholder={t("settings.subscription.claim.otp_placeholder")}
                    className="flex-1 text-[12px] px-3 py-1.5 rounded-md border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-zinc-900 dark:text-white placeholder-zinc-400 focus:outline-none focus:ring-1 focus:ring-purple-500/50 tracking-widest"
                  />
                  <button
                    onClick={() => void handleVerifyOtp()}
                    disabled={claimStep === "verifying" || claimOtp.length !== 6}
                    className="text-[12px] font-medium px-3 py-1.5 rounded-md bg-purple-500 hover:bg-purple-600 text-white transition-colors disabled:opacity-50 whitespace-nowrap"
                  >
                    {claimStep === "verifying"
                      ? t("settings.subscription.claim.verifying")
                      : t("settings.subscription.claim.verify")}
                  </button>
                </div>
                <div className="flex items-center gap-3">
                  <button
                    onClick={() => void handleResend()}
                    disabled={resendCountdown > 0}
                    className="text-[11px] text-zinc-500 hover:text-zinc-300 transition-colors disabled:opacity-50"
                  >
                    {resendCountdown > 0
                      ? `${t("settings.subscription.claim.resend_in")} ${resendCountdown}s`
                      : t("settings.subscription.claim.resend")}
                  </button>
                  <span className="text-zinc-700 text-[10px]">·</span>
                  <button
                    onClick={() => { setClaimStep("idle"); setClaimOtp(""); setClaimError(null); }}
                    className="text-[11px] text-zinc-500 hover:text-zinc-300 transition-colors"
                  >
                    {t("settings.subscription.claim.change_email")}
                  </button>
                </div>
              </div>
            )}

            {claimError && (
              <p className="text-[11px] text-red-500 mt-2">{claimError}</p>
            )}
          </div>
        )}

        {currentPlan !== "free" && (
          <div className="px-4 py-4 border-t border-zinc-100 dark:border-zinc-800/50">
            <p className="text-[12px] font-semibold text-zinc-500 dark:text-zinc-400 mb-3">
              {t("settings.subscription.invoices.title")}
            </p>

            {invoicesLoading && (
              <p className="text-[11px] text-zinc-500">{t("settings.subscription.invoices.loading")}</p>
            )}

            {invoicesError && (
              <p className="text-[11px] text-red-500">{invoicesError}</p>
            )}

            {!invoicesLoading && !invoicesError && invoices.length === 0 && (
              <p className="text-[11px] text-zinc-500">{t("settings.subscription.invoices.empty")}</p>
            )}

            {invoices.length > 0 && (
              <div className="flex flex-col gap-1.5">
                {invoices.map((inv) => {
                  const amount = (inv.amount / 100).toLocaleString(undefined, {
                    style: "currency",
                    currency: inv.currency.toUpperCase(),
                  });
                  const date = new Date(inv.date).toLocaleDateString();
                  const label = inv.number ?? date;

                  return (
                    <div key={inv.id} className="flex items-center justify-between gap-3 py-1.5 border-b border-zinc-100 dark:border-zinc-800/50 last:border-0">
                      <div className="flex flex-col gap-0.5 min-w-0">
                        <span className="text-[12px] text-zinc-300 truncate">{label}</span>
                        <span className="text-[11px] text-zinc-500">{date} · {amount}</span>
                      </div>
                      <div className="flex items-center gap-2 shrink-0">
                        {inv.pdfUrl && (
                          <button
                            onClick={() => void openUrl(inv.pdfUrl!)}
                            className="text-[11px] text-zinc-400 hover:text-zinc-200 underline underline-offset-2 transition-colors"
                          >
                            {t("settings.subscription.invoices.download")}
                          </button>
                        )}
                        {inv.hostedUrl && (
                          <button
                            onClick={() => void openUrl(inv.hostedUrl!)}
                            className="text-[11px] text-zinc-400 hover:text-zinc-200 underline underline-offset-2 transition-colors"
                          >
                            {t("settings.subscription.invoices.view")}
                          </button>
                        )}
                      </div>
                    </div>
                  );
                })}

                {invoicesHasMore && (
                  <button
                    onClick={() => fetchInvoices(invoicesCursor)}
                    disabled={invoicesLoading}
                    className="mt-1 text-[11px] text-zinc-400 hover:text-zinc-200 transition-colors disabled:opacity-50 text-left"
                  >
                    {invoicesLoading ? t("settings.subscription.invoices.loading") : t("settings.subscription.invoices.load_more")}
                  </button>
                )}
              </div>
            )}
          </div>
        )}
      </SettingsSection>
    </div>
  );
}
