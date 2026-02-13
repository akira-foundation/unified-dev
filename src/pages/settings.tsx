import { useState } from "react";
import {
  AlertTriangle,
  CheckCircle,
  CreditCard,
  Crown,
  Database,
  Globe,
  Info,
  Mail,
  Smartphone,
  Trash2,
  User,
} from "lucide-react";

import AppearanceTabs from "@/components/appearance-tabs";
import { Card } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import UpgradeModal from "@/components/upgrade-modal";
import { useI18n } from "@/i18n/i18n";

export function SettingsPage() {
  const { t, locale, setLocale } = useI18n();
  const dailyUsage = 0;
  const dailyLimit = 20;

  const [showResetConfirm, setShowResetConfirm] = useState(false);
  const [showUpgradeModal, setShowUpgradeModal] = useState(false);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const showToast = (message: string) => {
    setToastMessage(message);
    setTimeout(() => setToastMessage(null), 3000);
  };

  const handleClearHistory = () => {
    localStorage.removeItem("noxdireit_recent_searches");
    showToast("Histórico de pesquisa limpo.");
  };

  const handleClearSaved = () => {
    if (window.confirm("Tem a certeza? Isto apagará todos os itens guardados.")) {
      localStorage.removeItem("noxdireit_saved_laws");
      localStorage.removeItem("noxdireit_saved_drafts");
      localStorage.removeItem("noxdireit_saved_meetings");
      localStorage.removeItem("noxdireit_saved_checklists");
      showToast("Todos os itens guardados foram removidos.");
    }
  };

  const handleFactoryReset = () => {
    localStorage.clear();
    showToast("Aplicação reiniciada. A atualizar...");
    setTimeout(() => window.location.reload(), 1500);
  };

  const onShowUpgrade = () => {
    setShowUpgradeModal(true);
  };

  const onManageBilling = () => {
    window.location.assign("/settings/billing");
  };

  const SettingsSection = ({ title, icon: Icon, colorClass, children }: any) => (
    <Card className="mb-6 overflow-hidden gap-0">
      <div className="flex items-center gap-3 border-b border-zinc-100 px-6 py-3 dark:border-zinc-800/50">
        <Icon size={18} className={cn("text-zinc-500 dark:text-zinc-400", colorClass)} />
        <h3 className="text-xs font-bold uppercase tracking-wider text-zinc-900 dark:text-white">{title}</h3>
      </div>
      <div className="divide-y divide-zinc-100 dark:divide-zinc-800/50">{children}</div>
    </Card>
  );

  const SettingsItem = ({ label, description, action, destructive = false, className }: any) => (
    <div
      className={cn(
        "flex items-center justify-between px-6 py-4 transition-colors hover:bg-zinc-50 dark:hover:bg-zinc-900/40",
        className,
      )}
    >
      <div>
        <p className="text-sm font-medium text-zinc-900 dark:text-white">{label}</p>
        {description && <p className="mt-0.5 text-xs text-zinc-500 dark:text-zinc-400">{description}</p>}
      </div>
      <div className={destructive ? "text-red-600" : "text-zinc-700 dark:text-zinc-200"}>{action}</div>
    </div>
  );

  const usagePercent = Math.min((dailyUsage / dailyLimit) * 100, 100);

  return (
    <div className="mx-auto w-full max-w-2xl flex-1 flex-col">
      <div className="my-8">
        <h1 className="text-3xl font-bold tracking-tight text-zinc-900 dark:text-white mb-2">Definições</h1>
        <p className="text-zinc-500 dark:text-zinc-400">Personalize a sua experiência e gira os seus dados.</p>
      </div>

      {toastMessage && (
        <div className="animate-fade-in-up fixed bottom-6 right-6 z-[100] flex items-center gap-3 rounded-xl border border-zinc-100 bg-white px-6 py-4 font-medium text-black shadow-2xl">
          <CheckCircle size={20} className="text-emerald-500" />
          {toastMessage}
        </div>
      )}

      <Card className="mb-8">
        <div className="relative z-10 mb-6 flex items-start justify-between">
          <div>
            <span className="mb-2 inline-flex items-center rounded-full border border-zinc-200 bg-zinc-100 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
              Plano Atual
            </span>
            <h2 className="text-xl font-bold text-zinc-900 dark:text-white">Plano Gratuito</h2>
            <p className="mt-1 text-sm text-zinc-500 dark:text-zinc-400">Funcionalidades básicas.</p>
          </div>
          <div className="rounded-2xl border border-zinc-100 bg-zinc-50 p-2.5 dark:border-zinc-800 dark:bg-zinc-900">
            <CreditCard size={20} className="text-purple-600 dark:text-purple-400" />
          </div>
        </div>

        <div className="relative z-10 mb-6">
          <div className="mb-2 flex items-end justify-between">
            <span className="text-[10px] font-bold uppercase tracking-wider text-zinc-500 dark:text-zinc-400">Uso Diário</span>
            <span className="font-mono text-xs font-semibold text-zinc-900 dark:text-white">
              {dailyUsage} / {dailyLimit}
            </span>
          </div>
          <div className="h-2 w-full overflow-hidden rounded-full bg-zinc-100 dark:bg-zinc-800">
            <div
              className={`h-full rounded-full transition-all duration-1000 ease-out ${usagePercent > 90 ? "bg-red-500" : "bg-purple-600 dark:bg-purple-500"}`}
              style={{ width: `${usagePercent}%` }}
            />
          </div>
        </div>

        <div className="relative z-10 flex items-center gap-3">
          <button
            onClick={onShowUpgrade}
            className="flex h-11 flex-1 items-center justify-center gap-2 rounded-xl bg-purple-600 px-4 text-sm font-bold text-white shadow-lg shadow-purple-600/20 transition-colors hover:bg-purple-700 dark:bg-white dark:text-purple-700 dark:shadow-none dark:hover:bg-zinc-100"
          >
            <Crown size={18} className="text-purple-200 dark:text-purple-600" /> Fazer Upgrade
          </button>
          <button
            onClick={onManageBilling}
            className="h-11 rounded-xl bg-zinc-100 px-6 text-sm font-medium text-zinc-900 transition-colors hover:bg-zinc-200 dark:bg-[#1f1f22] dark:text-zinc-300 dark:hover:bg-[#27272a] dark:hover:text-white"
          >
            Faturação
          </button>
        </div>
      </Card>

      <SettingsSection title="Conta" icon={User} colorClass="text-zinc-500">
        <SettingsItem
          label="Perfil & Segurança"
          description="Informação pessoal, email e palavra-passe."
          action={
            <button
              onClick={() => window.location.assign("/settings/profile")}
              className="flex h-8 items-center gap-2 rounded-lg border border-zinc-200 bg-white px-3 text-xs font-bold text-zinc-700 hover:bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900 dark:text-zinc-300 dark:hover:bg-zinc-800"
            >
              Gerir Conta
            </button>
          }
        />
      </SettingsSection>

      <SettingsSection title={t("settings.section.general")} icon={Smartphone} colorClass="text-purple-500">
        <SettingsItem
          label={t("settings.general.language")}
          description={t("settings.general.languageValue")}
          action={
            <Select value={locale} onValueChange={(value) => setLocale(value as any)}>
              <SelectTrigger className="h-8 rounded-full border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="en">{t("settings.general.languageEnglish")}</SelectItem>
                <SelectItem value="pt-PT">{t("settings.general.languagePortuguese")}</SelectItem>
              </SelectContent>
            </Select>
          }
        />
        <SettingsItem
          label={t("settings.general.appearance")}
          description={t("settings.general.appearanceDesc")}
          action={<AppearanceTabs />}
        />
      </SettingsSection>

      <SettingsSection title="Dados & Privacidade" icon={Database} colorClass="text-purple-500">
        <SettingsItem
          label="Limpar Histórico de Pesquisa"
          description="Remove todas as sugestões de pesquisa recente."
          action={
            <button
              onClick={handleClearHistory}
              className="text-sm font-bold text-purple-500 hover:text-purple-400 transition-colors"
            >
              Limpar
            </button>
          }
        />
        <SettingsItem
          label="Limpar Itens Guardados"
          description="Apaga itens guardados da memória local."
          action={
            <button
              onClick={handleClearSaved}
              className="text-sm font-bold text-rose-500 hover:text-rose-400 transition-colors"
            >
              Apagar Tudo
            </button>
          }
        />
        <SettingsItem
          label="Reiniciar Aplicação"
          description="Restaura as definições de fábrica e limpa todos os dados."
          destructive
          action={
            <button
              onClick={() => setShowResetConfirm(true)}
              className="flex h-8 w-8 items-center justify-center rounded-full bg-red-500/10 text-red-500 transition-colors hover:bg-red-500/20"
            >
              <Trash2 size={16} />
            </button>
          }
        />
      </SettingsSection>

      <SettingsSection title="Sobre" icon={Info} colorClass="text-purple-500">
        <SettingsItem
          label="Versão"
          action={<span className="font-mono text-xs text-zinc-500 dark:text-zinc-500">v1.3.0 (Beta)</span>}
        />
        <SettingsItem
          label="Contacto / Suporte"
          description="Reportar bugs ou sugerir funcionalidades."
          action={
            <a
              href="mailto:suporte@noxdireit.cv"
              className="flex items-center gap-2 text-sm font-bold text-blue-500 hover:text-blue-400 transition-colors"
            >
              <Mail size={16} /> Enviar Email
            </a>
          }
        />
        <SettingsItem
          label="Desenvolvido por"
          action={<span className="text-sm font-bold text-zinc-900 dark:text-white">Kidiatoliny Gonçalves</span>}
        />
        <div className="py-4 text-center border-t border-zinc-100 dark:border-zinc-800/50">
          <p className="text-[10px] uppercase tracking-widest text-zinc-500 dark:text-zinc-600">
            Feito com <span className="text-red-500">❤</span> em Cabo Verde
          </p>
        </div>
      </SettingsSection>

      {showResetConfirm && (
        <div className="animate-fade-in fixed inset-0 z-[150] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm">
          <div className="animate-scale-in w-full max-w-sm rounded-3xl border border-zinc-200 bg-white p-6 shadow-2xl dark:border-zinc-800 dark:bg-[#18181b]">
            <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-red-100 text-red-600 dark:bg-red-500/10 dark:text-red-500">
              <AlertTriangle size={24} />
            </div>
            <h3 className="mb-2 text-center text-xl font-bold text-zinc-900 dark:text-white">Apagar tudo?</h3>
            <p className="mb-6 text-center text-sm text-zinc-500 dark:text-zinc-400">
              Esta ação é irreversível. Todos os seus dados locais serão eliminados.
            </p>
            <div className="flex gap-3">
              <button
                onClick={() => setShowResetConfirm(false)}
                className="flex-1 rounded-xl bg-zinc-100 py-3 font-bold text-zinc-700 hover:bg-zinc-200 dark:bg-zinc-800 dark:text-zinc-300 dark:hover:bg-zinc-700"
              >
                Cancelar
              </button>
              <button
                onClick={handleFactoryReset}
                className="flex-1 rounded-xl bg-red-600 py-3 font-bold text-white shadow-lg shadow-red-600/20 hover:bg-red-700"
              >
                Sim, Apagar
              </button>
            </div>
          </div>
        </div>
      )}

      {showUpgradeModal && <UpgradeModal onClose={() => setShowUpgradeModal(false)} />}
    </div>
  );
}
