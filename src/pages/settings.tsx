import { useState } from "react";
import {
  Settings2,
  Github,
  FolderGit2,
  FileText,
  Link2,
  AlertTriangle,
  CheckCircle,
  Mail,
  Trash2,
} from "lucide-react";

import AppearanceTabs from "@/components/appearance-tabs";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import UpgradeModal from "@/components/upgrade-modal";
import { useI18n } from "@/i18n/i18n";
import { useDateLabel } from "@/hooks/use-date-label";
import { appVersion } from "@/lib/app-meta";
import {
  PageHeader,
  PageHeaderMeta,
  PageHeaderTitle,
} from "@/components/layout/page-header";
import { PageLayout } from "@/components/layout/page-layout";
import { Button } from "@/components/ui/button";

const TABS = [
  { id: "general", label: "General", icon: <Settings2 className="h-4 w-4" /> },
  { id: "github", label: "GitHub", icon: <Github className="h-4 w-4" /> },
  { id: "workspaces", label: "Workspaces", icon: <FolderGit2 className="h-4 w-4" /> },
  { id: "prompts", label: "Prompts", icon: <FileText className="h-4 w-4" /> },
];

export function SettingsPage() {
  const { t, locale, setLocale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const [activeTab, setActiveTab] = useState("general");

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

  const SettingsSection = ({ title, description, children, icon: Icon }: any) => (
    <Card className="mb-6">
      <CardHeader className="flex flex-row items-center gap-3 space-y-0">
        {Icon && (
          <div className="h-10 w-10 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500">
            <Icon className="h-5 w-5" />
          </div>
        )}
        <div className="flex flex-col gap-1">
          <CardTitle className="text-xl">{title}</CardTitle>
          {description && <CardDescription>{description}</CardDescription>}
        </div>
      </CardHeader>
      <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 gap-0">
        {children}
      </CardContent>
    </Card>
  );

  const SettingsItem = ({ label, description, action, destructive = false, className }: any) => (
    <div
      className={cn(
        "flex items-center justify-between px-4 py-6 transition-colors hover:bg-zinc-50 dark:hover:bg-zinc-900/40",
        className,
      )}
    >
      <div className="flex flex-col gap-1 w-full max-w-[65%]">
        <p className="text-sm font-medium text-zinc-900 dark:text-white">{label}</p>
        {description && <p className="text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed">{description}</p>}
      </div>
      <div className={cn("shrink-0", destructive ? "text-red-600" : "text-zinc-700 dark:text-zinc-200")}>{action}</div>
    </div>
  );

  const SettingsTextarea = ({ label, description, defaultValue }: any) => (
    <div className="flex flex-col gap-3 px-4 py-6 transition-colors hover:bg-zinc-50 dark:hover:bg-zinc-900/40 border-b border-zinc-100 dark:border-zinc-800/50 last:border-0">
      <div className="flex flex-col gap-1">
        <p className="text-sm font-medium text-zinc-900 dark:text-white">{label}</p>
      </div>
      <textarea
        className="w-full h-48 bg-zinc-50 dark:bg-black/20 border border-zinc-200 dark:border-white/5 rounded-xl text-zinc-600 dark:text-zinc-400 font-mono text-[13px] p-4 focus:outline-none focus:border-purple-500 transition-colors custom-scrollbar"
        defaultValue={defaultValue}
      />
      {description && <p className="text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed">{description}</p>}
    </div>
  );

  const mergePrompt = \`Merge the changes from this worktree into the base branch locally.

Steps:
1. Check for uncommitted changes with \\\`git status --porcelain\\\`
2. If there are uncommitted changes, stage them all with \\\`git add -A\\\` and commit with a meaningful, short message that describes the changes.\`;

  const mergePushPrompt = \`Merge the changes from this worktree into the base branch and push to the remote.

Steps:
1. Check for uncommitted changes with \\\`git status --porcelain\\\`
2. If there are uncommitted changes, stage them all with \\\`git add -A\\\` and commit with a meaningful, short message that describes the changes.\`;

  const prPrompt = \`Create a pull request for the changes on this branch.

Steps:
1. Check for uncommitted changes with \\\`git status --porcelain\\\`
2. If there are uncommitted changes, stage them all with \\\`git add -A\\\` and commit with a meaningful, short message that describes the changes.\`;

  const draftPrPrompt = \`Create a draft pull request for the changes on this branch.

Steps:
1. Check for uncommitted changes with \\\`git status --porcelain\\\`
2. If there are uncommitted changes, stage them all with \\\`git add -A\\\` and commit with a meaningful, short message that describes the changes.\`;

  return (
    <PageLayout scroll>
      <PageHeader>
        <div>
          <PageHeaderTitle>{t("nav.settings")}</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
      </PageHeader>

      <div className="mx-auto w-full max-w-6xl pb-12 flex gap-8">
        
        {/* Sidebar */}
        <div className="w-64 shrink-0 flex flex-col gap-1">
          {TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={cn(
                "flex items-center gap-3 px-3 py-2.5 rounded-lg text-[13px] transition-colors",
                activeTab === tab.id
                  ? "bg-zinc-100 dark:bg-zinc-800 text-zinc-900 dark:text-white font-medium shadow-sm"
                  : "text-zinc-500 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-zinc-200 hover:bg-zinc-50 dark:hover:bg-zinc-800/50"
              )}
            >
              {tab.icon}
              {tab.label}
            </button>
          ))}
        </div>

        {/* Content */}
        <div className="flex-1 min-w-0">
          {toastMessage && (
            <div className="animate-fade-in-up fixed bottom-6 right-6 z-[100] flex items-center gap-3 rounded-xl border border-zinc-100 bg-white px-6 py-4 font-medium text-black shadow-2xl">
              <CheckCircle size={20} className="text-emerald-500" />
              {toastMessage}
            </div>
          )}

          {activeTab === "general" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection
                title={t("settings.section.general")}
                description={t("settings.general.appearanceDesc")}
                icon={Settings2}
              >
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
                <SettingsItem
                  label={t("settings.general.appearance")}
                  description={t("settings.general.appearanceDesc")}
                  action={<AppearanceTabs />}
                />
              </SettingsSection>

              <SettingsSection
                title={t("settings.section.privacy")}
                description={t("settings.privacy.clearHistoryDesc")}
              >
                <SettingsItem
                  label={t("settings.privacy.clearHistory")}
                  description={t("settings.privacy.clearHistoryDesc")}
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
                  label={t("settings.privacy.clearSaved")}
                  description={t("settings.privacy.clearSavedDesc")}
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
                  label={t("settings.privacy.reset")}
                  description={t("settings.privacy.resetDesc")}
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
            </div>
          )}

          {activeTab === "github" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection
                title="GitHub Account"
                description="Connect your GitHub account to enable pull requests and remote actions directly from the Agent workspace."
                icon={Github}
              >
                <SettingsItem
                  label="GitHub Authentication"
                  description="Authorize this app to access your GitHub repositories."
                  action={
                    <Button variant="outline" className="h-8 gap-2 bg-transparent hover:bg-zinc-100 dark:hover:bg-white/5 border-zinc-200 dark:border-white/10 dark:text-zinc-300">
                      <Link2 className="h-4 w-4" /> Connect
                    </Button>
                  }
                />
              </SettingsSection>
            </div>
          )}

          {activeTab === "workspaces" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection
                title="Workspaces"
                description="Configure how local Agent workspaces and repositories are handled."
                icon={FolderGit2}
              >
                <SettingsItem
                  label="Default Workspace Directory"
                  description="The default local path where new clone operations will be stored."
                  action={
                    <input
                      type="text"
                      defaultValue="~/Developer/Akira"
                      className="w-64 h-8 px-3 rounded-md bg-zinc-50 dark:bg-white/5 border border-zinc-200 dark:border-white/10 text-[13px] text-zinc-900 dark:text-white focus:outline-none focus:border-purple-500 transition-colors"
                    />
                  }
                />
              </SettingsSection>
            </div>
          )}

          {activeTab === "prompts" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection
                title="Prompts"
                description="Customize the instructions that the coding agent uses when executing specialized Git and GitHub actions."
                icon={FileText}
              >
                <SettingsTextarea 
                  label="Merge Prompt" 
                  defaultValue={mergePrompt} 
                  description="Showing the default local merge prompt. This merges locally only — it does not push to the remote. Edit to customize." 
                />
                <SettingsTextarea 
                  label="Merge and Push Prompt" 
                  defaultValue={mergePushPrompt} 
                  description="Showing the default merge-and-push prompt. This merges locally and pushes to the remote. Edit to customize." 
                />
                <SettingsTextarea 
                  label="Pull Request Prompt" 
                  defaultValue={prPrompt} 
                  description="Showing the default PR prompt. The branch name and issue details are filled in per workspace at runtime. Edit to customize." 
                />
                <SettingsTextarea 
                  label="Draft Pull Request Prompt" 
                  defaultValue={draftPrPrompt} 
                  description="Showing the default draft PR prompt. The branch name and issue details are filled in per workspace at runtime. Edit to customize." 
                />
              </SettingsSection>
            </div>
          )}
        </div>

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
    </PageLayout>
  );
}
