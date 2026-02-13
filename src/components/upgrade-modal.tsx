import { useState } from "react";
import { Building2, Check, Crown, Shield, X, Zap } from "lucide-react";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";

interface UpgradeModalProps {
  onClose: () => void;
}

export default function UpgradeModal({ onClose }: UpgradeModalProps) {
  const { t } = useI18n();
  const [billingCycle, setBillingCycle] = useState<"monthly" | "yearly">("monthly");

  const plans = {
    developer: {
      name: t("upgrade.plan.developer"),
      price: billingCycle === "monthly" ? "9" : "90",
      period: t("upgrade.billing.monthly") === "Monthly" ? "/mo" : "/mês",
      description: t("upgrade.desc.developer"),
      features: [
        t("upgrade.feature.developer.1"),
        t("upgrade.feature.developer.2"),
        t("upgrade.feature.developer.3"),
        t("upgrade.feature.developer.4"),
      ],
    },
    team: {
      name: t("upgrade.plan.team"),
      price: billingCycle === "monthly" ? "19" : "190",
      period: t("upgrade.billing.monthly") === "Monthly" ? "/mo" : "/mês",
      description: t("upgrade.desc.team"),
      features: [
        t("upgrade.feature.team.1"),
        t("upgrade.feature.team.2"),
        t("upgrade.feature.team.3"),
        t("upgrade.feature.team.4"),
        t("upgrade.feature.team.5"),
      ],
    },
    enterprise: {
      name: t("upgrade.plan.enterprise"),
      price: t("upgrade.query"),
      period: "",
      description: t("upgrade.desc.enterprise"),
      features: [
        t("upgrade.feature.enterprise.1"),
        t("upgrade.feature.enterprise.2"),
        t("upgrade.feature.enterprise.3"),
        t("upgrade.feature.enterprise.4"),
        t("upgrade.feature.enterprise.5"),
      ],
    },
  };

  return (
    <div className="fixed inset-0 z-[150] flex items-center justify-center bg-black/90 backdrop-blur-md animate-fade-in p-4 overflow-y-auto">
      <div className="relative w-full max-w-6xl bg-[#0c0c0e] rounded-[32px] shadow-[0_0_100px_rgba(0,0,0,1)] border border-zinc-800/80 overflow-hidden flex flex-col md:flex-row animate-scale-in my-auto min-h-[680px]">

        {/* Sidebar */}
        <div className="w-full md:w-[320px] bg-black p-12 flex flex-col justify-between shrink-0 border-r border-zinc-800/80">
          <div>
            <div className="inline-flex px-3 py-1 rounded-full bg-purple-500/10 border border-purple-500/20 mb-10">
              <span className="text-[10px] font-bold uppercase tracking-wider text-purple-400">{t("upgrade.title")}</span>
            </div>

            <h2 className="text-4xl font-black leading-tight text-white mb-6 whitespace-pre-line">
              {t("upgrade.headline").split("\n").map((line, i) => (
                <span key={i} className={line.toLowerCase().includes("workflow") || line.toLowerCase().includes("pr") ? "text-purple-400" : ""}>
                  {line}
                  {i === 0 && <br />}
                </span>
              ))}
            </h2>

            <p className="text-sm text-zinc-400 leading-relaxed font-medium">
              {t("upgrade.description")}
            </p>
          </div>

          <div className="mt-12">
            <div
              className="bg-zinc-900/80 p-1 rounded-full flex items-center border border-zinc-800 w-fit cursor-pointer shadow-xl"
              onClick={() => setBillingCycle(billingCycle === "monthly" ? "yearly" : "monthly")}
            >
              <div className={cn(
                "px-6 py-2 rounded-full text-[12px] font-bold transition-all duration-300",
                billingCycle === "monthly" ? "bg-purple-600 text-white shadow-lg" : "text-zinc-500 hover:text-zinc-300"
              )}>
                {t("upgrade.billing.monthly")}
              </div>
              <div className={cn(
                "px-6 py-2 rounded-full text-[12px] font-bold transition-all duration-300 flex items-center gap-2",
                billingCycle === "yearly" ? "bg-purple-600 text-white shadow-lg" : "text-zinc-500 hover:text-zinc-300"
              )}>
                {t("upgrade.billing.yearly")} <span className={cn("font-black text-[10px]", billingCycle === "yearly" ? "text-emerald-200" : "text-emerald-400")}>{t("upgrade.billing.discount")}</span>
              </div>
            </div>
          </div>
        </div>

        {/* Plan Cards */}
        <div className="flex-1 p-8 lg:p-12 relative flex items-center bg-[#0c0c0e]">
          <button
            onClick={onClose}
            className="absolute top-8 right-8 p-2 rounded-full text-zinc-400 hover:text-white hover:bg-zinc-900 transition-colors z-20 border border-zinc-800"
          >
            <X size={20} />
          </button>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 w-full">

            {/* Developer Card */}
            <div className="group bg-zinc-900/40 rounded-3xl p-8 border border-zinc-800 flex flex-col hover:border-zinc-700 transition-all">
              <div className="mb-6 text-center md:text-left">
                <div className="w-12 h-12 rounded-2xl bg-zinc-800 flex items-center justify-center text-zinc-400 mb-6 border border-zinc-700 mx-auto md:mx-0 group-hover:scale-110 transition-transform">
                  <Zap size={24} fill="currentColor" strokeWidth={0} />
                </div>
                <h3 className="text-xl font-bold text-white mb-2">{plans.developer.name}</h3>
                <p className="text-[13px] text-zinc-400 leading-snug h-10 line-clamp-2">
                  {plans.developer.description}
                </p>
              </div>

              <div className="flex items-baseline gap-1 mb-8 justify-center md:justify-start">
                <span className="text-4xl font-black text-white tracking-tight">{plans.developer.price}</span>
                <span className="text-lg font-bold text-zinc-500">€</span>
                <span className="text-[13px] text-zinc-600 font-bold ml-1">{plans.developer.period}</span>
              </div>

              <div className="space-y-4 mb-10 flex-1">
                {plans.developer.features.map((f) => (
                  <div key={f} className="flex items-center gap-4 text-zinc-300">
                    <Check size={16} className="text-zinc-500" strokeWidth={3} />
                    <span className="text-[13px] font-medium">{f}</span>
                  </div>
                ))}
              </div>

              <button className="w-full py-4 rounded-xl bg-white text-black font-black text-[13px] hover:bg-zinc-200 transition-all active:scale-95">
                {t("upgrade.cta.developer")}
              </button>
            </div>

            {/* Team Card (Recommended Visual but no badge) */}
            <div className="relative group bg-black/40 rounded-3xl p-8 border border-purple-500/50 flex flex-col shadow-2xl shadow-purple-900/20 hover:border-purple-500 transition-all lg:scale-105 z-10">
              <div className="mb-6 text-center md:text-left">
                <div className="w-12 h-12 rounded-2xl bg-purple-500/20 flex items-center justify-center text-purple-400 mb-6 border border-purple-500/30 mx-auto md:mx-0 group-hover:rotate-12 transition-transform">
                  <Crown size={24} />
                </div>
                <h3 className="text-xl font-bold text-white mb-2">{plans.team.name}</h3>
                <p className="text-[13px] text-zinc-300 leading-snug h-10 line-clamp-2 font-medium">
                  {plans.team.description}
                </p>
              </div>

              <div className="flex items-baseline gap-1 mb-8 justify-center md:justify-start">
                <span className="text-4xl font-black text-white tracking-tight">{plans.team.price}</span>
                <span className="text-lg font-bold text-purple-400">€</span>
                <span className="text-[13px] text-zinc-600 font-bold ml-1">{plans.team.period}</span>
              </div>

              <div className="space-y-4 mb-10 flex-1">
                {plans.team.features.map((f) => (
                  <div key={f} className="flex items-center gap-4 text-white">
                    <Check size={16} className="text-purple-400" strokeWidth={3} />
                    <span className="text-[13px] font-bold">{f}</span>
                  </div>
                ))}
              </div>

              <button className="w-full py-4.5 rounded-xl bg-purple-600 text-white font-black text-[13px] hover:bg-purple-500 transition-all flex items-center justify-center gap-2 shadow-lg shadow-purple-900/40 active:scale-95">
                <Shield size={18} strokeWidth={2.5} /> {t("upgrade.cta.team")}
              </button>
            </div>

            {/* Enterprise Card */}
            <div className="group bg-zinc-900/40 rounded-3xl p-8 border border-zinc-800 flex flex-col hover:border-zinc-700 transition-all">
              <div className="mb-6 text-center md:text-left">
                <div className="w-12 h-12 rounded-2xl bg-zinc-800 flex items-center justify-center text-zinc-400 mb-6 border border-zinc-700 mx-auto md:mx-0 group-hover:-rotate-12 transition-transform">
                  <Building2 size={24} />
                </div>
                <h3 className="text-xl font-bold text-white mb-2">{plans.enterprise.name}</h3>
                <p className="text-[13px] text-zinc-400 leading-snug h-10 line-clamp-2">
                  {plans.enterprise.description}
                </p>
              </div>

              <div className="mb-8 h-[40px] flex items-center justify-center md:justify-start">
                <span className="text-2xl font-black text-white uppercase tracking-tight">{plans.enterprise.price}</span>
              </div>

              <div className="space-y-4 mb-10 flex-1">
                {plans.enterprise.features.map((f) => (
                  <div key={f} className="flex items-center gap-4 text-zinc-300">
                    <Check size={16} className="text-zinc-500" strokeWidth={3} />
                    <span className="text-[13px] font-medium">{f}</span>
                  </div>
                ))}
              </div>

              <button
                onClick={() => window.open("mailto:comercial@noxdireit.cv")}
                className="w-full py-4 rounded-xl border border-zinc-700 text-zinc-200 font-black text-[13px] hover:bg-zinc-800 transition-all active:scale-95"
              >
                {t("upgrade.cta.enterprise")}
              </button>
            </div>

          </div>
        </div>
      </div>
    </div>
  );
}
