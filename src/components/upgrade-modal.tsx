import { useState } from "react";
import { Building2, Check, Crown, Shield, X, Zap } from "lucide-react";

interface UpgradeModalProps {
  onClose: () => void;
}

export default function UpgradeModal({ onClose }: UpgradeModalProps) {
  const [billingCycle, setBillingCycle] = useState<"monthly" | "yearly">("monthly");

  const plans = {
    plus: {
      price: billingCycle === "monthly" ? "990" : "9.900",
      period: billingCycle === "monthly" ? "/mês" : "/ano",
      description: "Essencial para estudantes e pesquisa básica.",
    },
    pro: {
      price: billingCycle === "monthly" ? "1.990" : "19.900",
      period: billingCycle === "monthly" ? "/mês" : "/ano",
      description: "Para advogados e prática jurídica avançada.",
    },
    enterprise: {
      price: "Sob Consulta",
      period: "",
      description: "Para escritórios, departamentos e grandes equipas.",
    },
  };

  return (
    <div className="fixed inset-0 z-[150] overflow-y-auto bg-black/80 backdrop-blur-md animate-fade-in">
      <div className="flex min-h-full items-center justify-center p-4">
        <div className="relative w-full max-w-6xl bg-[#09090b] rounded-3xl shadow-2xl border border-gray-800 overflow-hidden animate-scale-in my-8 flex flex-col lg:flex-row">
          <button
            onClick={onClose}
            className="absolute top-4 right-4 z-10 p-2 text-gray-400 hover:text-white bg-gray-900/50 hover:bg-gray-800 rounded-full transition-colors"
          >
            <X size={20} />
          </button>

          <div className="w-full lg:w-1/4 p-8 lg:p-10 flex flex-col justify-center bg-gradient-to-br from-gray-900 via-[#09090b] to-black border-b lg:border-b-0 lg:border-r border-gray-800 text-center lg:text-left">
            <div className="mb-6">
              <span className="inline-block px-3 py-1 rounded-full bg-purple-500/10 text-purple-400 text-xs font-bold uppercase tracking-wider mb-4 border border-purple-500/20">
                Planos Premium
              </span>
              <h2 className="text-3xl font-bold text-white mb-4 leading-tight">
                Eleve a sua <br />
                <span className="text-transparent bg-clip-text bg-gradient-to-r from-purple-400 to-pink-400">
                  Prática Jurídica
                </span>
              </h2>
              <p className="text-gray-400 leading-relaxed text-sm">
                Desbloqueie ferramentas de IA avançadas, análise de impacto e auditoria jurídica para trabalhar com mais rapidez e segurança.
              </p>
            </div>

            <div
              className="bg-gray-800/60 p-1 rounded-lg flex relative border border-gray-700/50 w-max mx-auto lg:mx-0 cursor-pointer mb-6 lg:mb-0 shadow-inner"
              onClick={() => setBillingCycle(billingCycle === "monthly" ? "yearly" : "monthly")}
            >
              <div
                className={`absolute top-1 bottom-1 w-[calc(50%-0.25rem)] bg-gray-600 rounded-md transition-all duration-300 shadow-sm ${billingCycle === "monthly" ? "left-1" : "left-[50%]"}`}
              />
              <button
                onClick={(event) => {
                  event.stopPropagation();
                  setBillingCycle("monthly");
                }}
                className={`relative z-10 w-20 py-1 text-[11px] font-bold text-center transition-colors rounded-md flex items-center justify-center ${billingCycle === "monthly" ? "text-white" : "text-gray-400 hover:text-gray-200"}`}
              >
                Mensal
              </button>
              <button
                onClick={(event) => {
                  event.stopPropagation();
                  setBillingCycle("yearly");
                }}
                className={`relative z-10 w-24 py-1 text-[11px] font-bold text-center transition-colors rounded-md flex items-center justify-center gap-1 ${billingCycle === "yearly" ? "text-white" : "text-gray-400 hover:text-gray-200"}`}
              >
                Anual <span className="text-[9px] text-emerald-400 font-extrabold">-17%</span>
              </button>
            </div>
          </div>

          <div className="w-full lg:w-3/4 p-6 lg:p-10 bg-[#0c0c0e]">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4 h-full">
              <div className="flex flex-col p-5 rounded-2xl border border-gray-800 bg-gray-900/20 hover:border-gray-700 transition-all relative group">
                <div className="mb-4">
                  <div className="w-10 h-10 bg-gray-800 rounded-lg flex items-center justify-center text-gray-300 mb-4 group-hover:scale-110 transition-transform">
                    <Zap size={20} />
                  </div>
                  <h3 className="text-lg font-bold text-white">Plus</h3>
                  <p className="text-xs text-gray-500 mt-1 h-8 line-clamp-2">{plans.plus.description}</p>
                </div>

                <div className="mb-6">
                  <div className="flex items-baseline gap-1">
                    <span className="text-2xl font-bold text-white">{plans.plus.price}</span>
                    <span className="text-xs font-bold text-gray-500">CVE</span>
                    <span className="text-[10px] text-gray-500">{plans.plus.period}</span>
                  </div>
                </div>

                <ul className="space-y-3 mb-8 flex-1">
                  {["20 pesquisas/dia", "Notas Pessoais (Limitadas)", "Sugestões de Próxima Ação", "5 Leis offline"].map((item) => (
                    <li key={item} className="flex items-start gap-2 text-xs text-gray-400">
                      <Check size={14} className="text-gray-600 mt-0.5 flex-shrink-0" />
                      <span>{item}</span>
                    </li>
                  ))}
                </ul>

                <button
                  onClick={() => alert("Em breve!")}
                  className="w-full py-3 rounded-xl border border-gray-700 text-white font-semibold hover:bg-gray-800 transition-colors text-xs"
                >
                  Começar com Plus
                </button>
              </div>

              <div className="flex flex-col p-5 rounded-2xl border border-amber-500/30 bg-gradient-to-b from-amber-500/5 to-transparent relative group shadow-lg shadow-amber-900/10 scale-[1.02] z-10">
                <div className="absolute -top-3 left-1/2 transform -translate-x-1/2 bg-amber-500 text-black text-[9px] font-bold px-3 py-1 rounded-full uppercase tracking-wider shadow-lg">
                  Recomendado
                </div>

                <div className="mb-4">
                  <div className="w-10 h-10 bg-amber-500/10 rounded-lg flex items-center justify-center text-amber-500 mb-4 group-hover:scale-110 transition-transform border border-amber-500/20">
                    <Crown size={20} />
                  </div>
                  <h3 className="text-lg font-bold text-white">Profissional</h3>
                  <p className="text-xs text-amber-500/80 mt-1 h-8 line-clamp-2">{plans.pro.description}</p>
                </div>

                <div className="mb-6">
                  <div className="flex items-baseline gap-1">
                    <span className="text-2xl font-bold text-white">{plans.pro.price}</span>
                    <span className="text-xs font-bold text-amber-500">CVE</span>
                    <span className="text-[10px] text-gray-500">{plans.pro.period}</span>
                  </div>
                </div>

                <ul className="space-y-3 mb-8 flex-1">
                  {
                    [
                      { text: "50 pesquisas/dia", highlight: false },
                      { text: "Análise de Impacto Legal", highlight: true },
                      { text: "Gerador de Minutas", highlight: true },
                      { text: "Preparar Reunião", highlight: true },
                      { text: "Auditoria de Coerência", highlight: true },
                      { text: "Modo Checklist de Caso", highlight: false },
                      { text: "Notas Pessoais Ilimitadas", highlight: false },
                    ].map((item) => (
                      <li
                        key={item.text}
                        className={`flex items-start gap-2 text-xs ${item.highlight ? "text-white font-medium" : "text-gray-400"}`}
                      >
                        <Check
                          size={14}
                          className={`${item.highlight ? "text-amber-500" : "text-gray-600"} mt-0.5 flex-shrink-0`}
                        />
                        <span className="leading-snug">{item.text}</span>
                      </li>
                    ))
                  }
                </ul>

                <button
                  onClick={() => alert("Em breve!")}
                  className="w-full py-3 rounded-xl bg-gradient-to-r from-amber-500 to-orange-600 text-white font-bold hover:from-amber-600 hover:to-orange-700 transition-all shadow-lg shadow-amber-900/20 transform active:scale-[0.98] text-xs flex items-center justify-center gap-2"
                >
                  <Shield size={14} /> Desbloquear Pro
                </button>
              </div>

              <div className="flex flex-col p-5 rounded-2xl border border-blue-900/30 bg-gradient-to-b from-blue-900/5 to-transparent hover:border-blue-800 transition-all relative group">
                <div className="mb-4">
                  <div className="w-10 h-10 bg-blue-900/20 rounded-lg flex items-center justify-center text-blue-400 mb-4 group-hover:scale-110 transition-transform border border-blue-500/20">
                    <Building2 size={20} />
                  </div>
                  <h3 className="text-lg font-bold text-white">Escritórios</h3>
                  <p className="text-xs text-blue-400/80 mt-1 h-8 line-clamp-2">{plans.enterprise.description}</p>
                </div>

                <div className="mb-6">
                  <div className="flex items-baseline gap-1">
                    <span className="text-xl font-bold text-white uppercase">{plans.enterprise.price}</span>
                  </div>
                </div>

                <ul className="space-y-3 mb-8 flex-1">
                  {
                    [
                      "Multi-utilizador & Equipas",
                      "Base de Conhecimento Interna",
                      "Templates Partilhados",
                      "Logs de Auditoria & Compliance",
                      "Suporte Prioritário",
                      "Limites Personalizados",
                    ].map((item) => (
                      <li key={item} className="flex items-start gap-2 text-xs text-gray-400">
                        <Check size={14} className="text-blue-500 mt-0.5 flex-shrink-0" />
                        <span>{item}</span>
                      </li>
                    ))
                  }
                </ul>

                <button
                  onClick={() => window.open("mailto:comercial@noxdireit.cv")}
                  className="w-full py-3 rounded-xl border border-blue-800 text-blue-400 font-semibold hover:bg-blue-900/20 hover:text-blue-300 transition-colors text-xs"
                >
                  Pedir Proposta
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
