import { useI18n } from "@/i18n/i18n";
import {
  formatPrice,
  PlanDto,
  RECOMMENDED_TIER,
  TIER_CHECK_COLOR,
  TIER_COLOR,
  TIER_ORDER,
} from "./subscription-types";

interface PlanCardProps {
  tier: string;
  plan: PlanDto;
  currentPlan: string;
  locale: string;
  loadingPlan: string | null;
  downgrading: "free" | "pro" | null;
  cancelAtPeriodEnd: boolean;
  onUpgrade: (tier: "pro" | "ultimate") => void;
  onDowngrade: (target: "free" | "pro") => void;
}

export function PlanCard({
  tier,
  plan,
  currentPlan,
  locale,
  loadingPlan,
  downgrading,
  cancelAtPeriodEnd,
  onUpgrade,
  onDowngrade,
}: PlanCardProps) {
  const { t } = useI18n();
  const isCurrentPlan = currentPlan === tier;
  const isUpgradeable = (TIER_ORDER[tier] ?? 99) > (TIER_ORDER[currentPlan] ?? 0);
  const price = formatPrice(plan.amount, plan.currency, locale);
  const isLoading = loadingPlan === tier;
  const isFree = tier === "free";

  return (
    <div
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
          onClick={() => void onUpgrade(tier as "pro" | "ultimate")}
          disabled={isLoading}
          className="text-[12px] font-semibold py-1.5 px-3 rounded-md bg-purple-500 hover:bg-purple-600 text-white transition-colors disabled:opacity-60"
        >
          {isLoading ? t("upgrade.cta.loading") : t(`upgrade.cta.${tier}`)}
        </button>
      ) : tier === "pro" && currentPlan === "ultimate" && !cancelAtPeriodEnd ? (
        <button
          onClick={() => void onDowngrade("pro")}
          disabled={downgrading !== null}
          className="text-[12px] font-medium py-1.5 px-3 rounded-md border border-zinc-600 text-zinc-400 hover:text-zinc-200 hover:border-zinc-500 transition-colors disabled:opacity-60"
        >
          {downgrading === "pro" ? t("settings.subscription.downgrade.downgrading") : t("settings.subscription.downgrade.to_pro")}
        </button>
      ) : tier === "free" && currentPlan !== "free" && !cancelAtPeriodEnd ? (
        <button
          onClick={() => void onDowngrade("free")}
          disabled={downgrading !== null}
          className="text-[12px] font-medium py-1.5 px-3 rounded-md border border-zinc-600 text-zinc-400 hover:text-zinc-200 hover:border-zinc-500 transition-colors disabled:opacity-60"
        >
          {downgrading === "free" ? t("settings.subscription.downgrade.downgrading") : t("settings.subscription.downgrade.confirm")}
        </button>
      ) : null}
    </div>
  );
}
