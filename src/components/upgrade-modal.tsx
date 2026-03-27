import { useState } from "react";
import { Check, Crown, Globe, Zap } from "lucide-react";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { useLicenseStore } from "@/stores/license-store";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";

interface UpgradeModalProps {
  onClose: () => void;
}

export default function UpgradeModal({ onClose }: UpgradeModalProps) {
  const { t } = useI18n();
  const [billingCycle, setBillingCycle] = useState<"monthly" | "yearly">("monthly");
  const { plan: getPlan } = useLicenseStore();
  const activePlan = getPlan();
  const yearly = billingCycle === "yearly";

  const plans = [
    {
      key: "free" as const,
      name: t("upgrade.plan.free"),
      price: "0",
      period: null,
      description: t("upgrade.desc.free"),
      icon: Zap,
      features: [
        t("upgrade.feature.free.1"),
        t("upgrade.feature.free.2"),
        t("upgrade.feature.free.3"),
      ],
      featured: false,
      cta: t("upgrade.cta.free"),
    },
    {
      key: "pro" as const,
      name: t("upgrade.plan.pro"),
      price: yearly ? "8" : "9",
      period: yearly ? t("upgrade.billing.billed_annually") : t("upgrade.billing.monthly"),
      description: t("upgrade.desc.pro"),
      icon: Crown,
      features: [
        t("upgrade.feature.pro.1"),
        t("upgrade.feature.pro.2"),
        t("upgrade.feature.pro.3"),
      ],
      featured: true,
      cta: t("upgrade.cta.pro"),
    },
    {
      key: "ultimate" as const,
      name: t("upgrade.plan.ultimate"),
      price: yearly ? "17" : "19",
      period: yearly ? t("upgrade.billing.billed_annually") : t("upgrade.billing.monthly"),
      description: t("upgrade.desc.ultimate"),
      icon: Globe,
      features: [
        t("upgrade.feature.ultimate.1"),
        t("upgrade.feature.ultimate.2"),
        t("upgrade.feature.ultimate.3"),
        t("upgrade.feature.ultimate.4"),
      ],
      featured: false,
      cta: t("upgrade.cta.ultimate"),
    },
  ];

  return (
    <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogContent
        showCloseButton
        className="p-0 gap-0 overflow-hidden sm:max-w-2xl border-4"
      >
        {/* Header */}
        <DialogHeader className="px-6 pt-6 pb-4 border-b border-border text-left gap-1">
          <DialogTitle className="text-base font-semibold">
            {t("upgrade.title")}
          </DialogTitle>
          <DialogDescription>
            {t("upgrade.description")}
          </DialogDescription>
        </DialogHeader>

        {/* Billing toggle */}
        <div className="flex items-center justify-end gap-3 px-6 py-2.5 border-b border-border bg-muted/40">
          <span className={cn("text-xs font-medium transition-colors", !yearly ? "text-foreground" : "text-muted-foreground")}>
            {t("upgrade.billing.monthly")}
          </span>
          <button
            onClick={() => setBillingCycle(yearly ? "monthly" : "yearly")}
            className={cn(
              "relative inline-flex h-5 w-9 shrink-0 items-center rounded-full border transition-colors",
              yearly ? "bg-primary border-primary" : "bg-input border-border"
            )}
          >
            <span className={cn(
              "inline-block h-3.5 w-3.5 rounded-full bg-white shadow-sm transition-transform duration-200",
              yearly ? "translate-x-[18px]" : "translate-x-0.5"
            )} />
          </button>
          <span className={cn("text-xs font-medium flex items-center gap-1.5 transition-colors", yearly ? "text-foreground" : "text-muted-foreground")}>
            {t("upgrade.billing.yearly")}
            <span className="text-[10px] font-bold text-emerald-500 bg-emerald-500/10 px-1.5 py-0.5 rounded-full">
              {t("upgrade.billing.discount")}
            </span>
          </span>
        </div>

        {/* Plans */}
        <div className="grid grid-cols-3 divide-x divide-border">
          {plans.map((plan) => {
            const Icon = plan.icon;
            const isCurrent = activePlan === plan.key;

            return (
              <div
                key={plan.key}
                className={cn(
                  "flex flex-col p-5",
                  plan.featured && "bg-primary/[0.03]"
                )}
              >
                {/* Icon + name */}
                <div className="flex items-center gap-2 mb-3">
                  <div className={cn(
                    "w-7 h-7 rounded-md flex items-center justify-center shrink-0",
                    plan.featured ? "bg-primary/10 text-primary" : "bg-muted text-muted-foreground"
                  )}>
                    <Icon size={14} />
                  </div>
                  <span className="text-sm font-semibold text-foreground leading-none">
                    {plan.name}
                  </span>
                  {plan.featured && (
                    <span className="text-[9px] font-black uppercase tracking-wider bg-primary text-primary-foreground px-1.5 py-0.5 rounded-full leading-none">
                      {t("upgrade.recommended")}
                    </span>
                  )}
                </div>

                {/* Price */}
                <div className="flex items-baseline gap-0.5 mb-1">
                  <span className="text-2xl font-black tracking-tight text-foreground">
                    {plan.price}
                  </span>
                  <span className={cn(
                    "text-sm font-bold",
                    plan.featured ? "text-primary" : "text-muted-foreground"
                  )}>
                    €
                  </span>
                  {plan.period && (
                    <span className="text-xs text-muted-foreground ml-0.5">
                      /{plan.period.toLowerCase()}
                    </span>
                  )}
                </div>

                <p className="text-xs text-muted-foreground mb-4 leading-relaxed">
                  {plan.description}
                </p>

                {/* Features */}
                <ul className="space-y-2 mb-5 flex-1">
                  {plan.features.map((f) => (
                    <li key={f} className="flex items-start gap-2">
                      <Check
                        size={12}
                        className={cn(
                          "shrink-0 mt-0.5",
                          plan.featured ? "text-primary" : "text-muted-foreground"
                        )}
                        strokeWidth={2.5}
                      />
                      <span className={cn(
                        "text-xs leading-snug",
                        plan.featured ? "text-foreground" : "text-muted-foreground"
                      )}>
                        {f}
                      </span>
                    </li>
                  ))}
                </ul>

                {/* CTA */}
                <button
                  disabled={isCurrent}
                  className={cn(
                    "w-full h-8 rounded-md text-xs font-semibold transition-all active:scale-95",
                    plan.featured
                      ? "bg-primary text-primary-foreground hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed"
                      : "border border-border bg-transparent text-muted-foreground hover:text-foreground hover:bg-accent disabled:opacity-40 disabled:cursor-not-allowed"
                  )}
                >
                  {isCurrent ? t("upgrade.cta.free") : plan.cta}
                </button>
              </div>
            );
          })}
        </div>
      </DialogContent>
    </Dialog>
  );
}
