import { useState, useEffect } from "react";
import {
  Settings2,
  Palette,
  SlidersHorizontal,
  Bell,
  Blocks,
  Bot,
  Keyboard,
  Mic,
  Wrench,
  LogOut,
  Minus,
  Plus,
  Unplug,
  Link2,
  Github,
  FolderGit2,
  FileText,
  AlertTriangle,
  CheckCircle,
  Trash2,
  User,
  Shield,
  GitlabIcon,
  RefreshCw,
} from "lucide-react";
import { useProviders } from "@/hooks/useProviders";
import { useNavigation } from "@/hooks/useNavigation";
import type { ProviderKind } from "@/types/provider";
import { AddProviderDialog } from "@/components/providers/add-provider-dialog";
import { Badge } from "@/components/ui/badge";

import { Card, CardContent, CardDescription, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { cn } from "@/lib/utils";
import UpgradeModal from "@/components/upgrade-modal";
import { useI18n } from "@/i18n/i18n";
import { useSettingsStore } from "@/stores/settings-store";
import { useSyncSettingsStore, GLOBAL_SYNC_ID } from "@/stores/sync-settings-store";
import { SyncSettingsTab } from "@/components/settings/sync-settings-tab";
import { useAppearance } from "@/hooks/use-appearance";
import { useDateLabel } from "@/hooks/use-date-label";
import {
  PageHeader,
  PageHeaderMeta,
  PageHeaderTitle,
} from "@/components/layout/page-header";
import { PageLayout } from "@/components/layout/page-layout";
import { Button } from "@/components/ui/button";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import {
  vscDarkPlus,
  atomDark,
  dracula,
  nord,
  oneDark,
  coldarkDark,
  oneLight,
  ghcolors,
  nightOwl,
  materialDark,
  materialOceanic,
  synthwave84,
  shadesOfPurple,
  duotoneDark,
  gruvboxDark
} from "react-syntax-highlighter/dist/esm/styles/prism";

const CODE_THEMES: Record<string, any> = {
  vscDarkPlus,
  atomDark,
  dracula,
  nord,
  oneDark,
  coldarkDark,
  oneLight,
  ghcolors,
  nightOwl,
  materialDark,
  materialOceanic,
  synthwave84,
  shadesOfPurple,
  duotoneDark,
  gruvboxDark,
};

const SAMPLE_CODE = `<?php

namespace App\\Actions;

final readonly class CreateUserAction
{
    public function handle(array $data): User
    {
        return User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => bcrypt($data['password']),
        ]);
    }
}`;


export function SettingsPage() {
  const { t, locale, setLocale } = useI18n();
  const { editorTheme, setEditorTheme, promptOverrides, loadPrompts, savePrompt, resetPrompt } = useSettingsStore();
  const { appearance, updateAppearance } = useAppearance();
  const dateLabel = useDateLabel(locale);
  const { loadSettings } = useSyncSettingsStore();
  const SETTINGS_GROUPS = [
    {
      id: "application",
      group: t("settings.groups.application"),
      items: [
        { id: "general", label: t("settings.tabs.general"), icon: <Settings2 className="h-4 w-4" /> },
        { id: "appearance", label: t("settings.tabs.appearance"), icon: <Palette className="h-4 w-4" /> },
        { id: "behaviour", label: t("settings.tabs.behaviour"), icon: <SlidersHorizontal className="h-4 w-4" /> },
        { id: "notifications", label: t("settings.tabs.notifications"), icon: <Bell className="h-4 w-4" /> },
      ]
    },
    {
      id: "features",
      group: t("settings.groups.features"),
      items: [
        { id: "integrations", label: t("settings.tabs.integrations"), icon: <Blocks className="h-4 w-4" /> },
        { id: "agents", label: t("settings.tabs.agents"), icon: <Bot className="h-4 w-4" /> },
        { id: "sync", label: t("settings.tabs.sync"), icon: <RefreshCw className="h-4 w-4" /> },
        { id: "shortcuts", label: t("settings.tabs.shortcuts"), icon: <Keyboard className="h-4 w-4" /> },
        { id: "dictation", label: t("settings.tabs.dictation"), icon: <Mic className="h-4 w-4" /> },
      ]
    },
    {
      id: "development",
      group: t("settings.groups.development"),
      items: [
        { id: "advanced", label: t("settings.tabs.advanced"), icon: <Wrench className="h-4 w-4" /> },
        { id: "vcs-providers", label: t("settings.tabs.vcsProviders"), icon: <Unplug className="h-4 w-4" /> },
        { id: "workspaces", label: t("settings.tabs.workspaces"), icon: <FolderGit2 className="h-4 w-4" /> },
        { id: "prompts", label: t("settings.tabs.prompts"), icon: <FileText className="h-4 w-4" /> },
      ]
    }
  ];

  const [activeTab, setActiveTab] = useState("general");
  const [showThemePreview, setShowThemePreview] = useState(false);
  const [isProviderDialogOpen, setIsProviderDialogOpen] = useState(false);
  const { providers, createProvider, connectGithub } = useProviders();
  const { navigateTo, setActiveProviderId } = useNavigation("settings");

  const [showResetConfirm, setShowResetConfirm] = useState(false);
  const [showUpgradeModal, setShowUpgradeModal] = useState(false);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  // Local draft edits for the Prompts tab — keyed by action.
  // A draft of "" means the user cleared the field (reverting to default behaviour).
  const [promptDrafts, setPromptDrafts] = useState<Record<string, string>>({});
  const [savingPrompt, setSavingPrompt] = useState<string | null>(null);

  // Friendly placeholder shown when no custom prompt is set for an action.
  const PROMPT_PLACEHOLDERS: Record<string, string> = {
    merge_local: "Commits any uncommitted changes and merges the branch into the base branch locally.",
    merge_push:  "Commits any uncommitted changes, merges the branch locally, and pushes to the remote.",
    draft_pr:    "Commits any uncommitted changes, pushes the branch, and opens a draft pull request on GitHub.",
    create_pr:   "Commits any uncommitted changes, pushes the branch, and opens a pull request on GitHub.",
  };

  useEffect(() => {
    if (activeTab === "prompts") {
      loadPrompts();
    }
    if (activeTab === "sync") {
      loadSettings(GLOBAL_SYNC_ID);
    }
  }, [activeTab]);

  const showToast = (message: string) => {
    setToastMessage(message);
    setTimeout(() => setToastMessage(null), 3000);
  };

  const handleClearHistory = () => {
    localStorage.removeItem("noxdireit_recent_searches");
    showToast(t("toast.historyCleared"));
  };

  const handleClearSaved = () => {
    if (window.confirm(t("modal.reset.desc"))) {
      localStorage.removeItem("noxdireit_saved_laws");
      localStorage.removeItem("noxdireit_saved_drafts");
      localStorage.removeItem("noxdireit_saved_meetings");
      localStorage.removeItem("noxdireit_saved_checklists");
      showToast(t("toast.savedCleared"));
    }
  };

  const handleFactoryReset = () => {
    localStorage.clear();
    showToast(t("toast.appReset"));
    setTimeout(() => window.location.reload(), 1500);
  };

  const SettingsSection = ({ title, description, children, icon: Icon }: any) => (
    <Card className="mb-6 overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
      <div className="flex flex-row items-center gap-4 px-6 py-6 pb-6">
        {Icon && (
          <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
            <Icon size={22} strokeWidth={2} />
          </div>
        )}
        <div className="flex flex-col gap-1">
          <CardTitle className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">{title}</CardTitle>
          {description && <CardDescription className="text-[13px] font-medium text-zinc-500/80 leading-none">{description}</CardDescription>}
        </div>
      </div>
      <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
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

  // SettingsTextarea is superseded by the inline prompt rows in the Prompts tab.
  // Kept for non-prompt tabs if ever needed.
  const SettingsTextarea = ({ label, description, defaultValue }: any) => (
    <div className="flex flex-col gap-3 px-4 py-6 transition-colors hover:bg-zinc-50 dark:hover:bg-zinc-900/40 border-b border-zinc-100 dark:border-zinc-800/50 last:border-0">
      <div className="flex flex-col gap-1">
        <p className="text-sm font-medium text-zinc-900 dark:text-white">{label}</p>
      </div>
      <textarea
        className="w-full h-48 bg-zinc-50 dark:bg-black/20 border border-zinc-200 dark:border-white/5 rounded-md text-zinc-600 dark:text-zinc-400 font-mono text-[13px] p-4 focus:outline-none focus:border-purple-500 transition-colors custom-scrollbar"
        defaultValue={defaultValue}
      />
      {description && <p className="text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed">{description}</p>}
     </div>
  );

  return (
    <PageLayout scroll>
      <PageHeader className="mx-auto w-full max-w-6xl">
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
        <div className="w-64 shrink-0 flex flex-col gap-6">
          {SETTINGS_GROUPS.map((group) => (
            <div key={group.id} className="flex flex-col gap-1">
              <h3 className="px-3 text-[11px] font-bold uppercase tracking-[0.1em] text-zinc-400/60 mb-2">
                {group.group}
              </h3>
              <div className="flex flex-col gap-0.5">
                {group.items.map((tab) => (
                  <button
                    key={tab.id}
                    onClick={() => setActiveTab(tab.id)}
                    className={cn(
                      "flex items-center gap-3 px-3 py-2 rounded-md text-[13px] transition-all duration-200",
                      activeTab === tab.id
                        ? "bg-zinc-100 dark:bg-zinc-800 text-zinc-900 dark:text-white font-semibold shadow-sm"
                        : "text-zinc-500 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-zinc-200 hover:bg-zinc-50 dark:hover:bg-zinc-800/30"
                    )}
                  >
                    <div className={cn(
                      "transition-colors duration-200",
                      activeTab === tab.id ? "text-purple-500" : "text-zinc-400 dark:text-zinc-500"
                    )}>
                      {tab.icon}
                    </div>
                    {tab.label}
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>

        {/* Content */}
        <div className="flex-1 min-w-0">
          {toastMessage && (
            <div className="animate-fade-in-up fixed bottom-6 right-6 z-[100] flex items-center gap-3 rounded-md border border-zinc-100 bg-white px-6 py-4 font-medium text-black shadow-2xl">
              <CheckCircle size={20} className="text-emerald-500" />
              {toastMessage}
            </div>
          )}

          {activeTab === "general" && (
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
                          <span className="text-[10px] bg-amber-500/10 text-amber-500 px-1.5 py-0.5 rounded font-medium">{t("settings.general.account.trialBadge")}</span>
                        </div>
                        <span className="text-[13px] text-zinc-500">kidiatoliny@akira-io.com</span>
                      </div>
                    </div>
                    <button className="flex items-center gap-2 text-[13px] text-zinc-400 hover:text-zinc-900 dark:hover:text-white transition-colors">
                      <LogOut className="h-4 w-4" />
                      {t("common.signOut")}
                    </button>
                  </div>

                  <div className="p-5 rounded-md border border-zinc-100 bg-zinc-50 dark:border-white/5 dark:bg-white/[0.02]">
                    <h3 className="text-[14px] text-zinc-900 dark:text-zinc-400 mb-3 font-medium dark:font-normal">{t("settings.general.account.upgradeBanner.title")}</h3>
                    <ul className="space-y-2 mb-4">
                      <li className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-400">
                        <span className="text-blue-500">✓</span> {t("settings.general.account.upgradeBanner.feature1")}
                      </li>
                      <li className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-400">
                        <span className="text-blue-500">✓</span> {t("settings.general.account.upgradeBanner.feature2")}
                      </li>
                    </ul>
                    <Button className="w-full" variant="default">
                      {t("common.upgrade")}
                    </Button>
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
          )}

          {activeTab === "appearance" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection
                title={t("settings.appearance.section.title")}
                description={t("settings.general.appearanceDesc")}
                icon={Palette}
              >
                <SettingsItem
                  label={t("settings.appearance.syncWithSystem")}
                  description={t("settings.appearance.syncWithSystem.desc")}
                  action={
                    <Switch
                      checked={appearance === "system"}
                      onCheckedChange={(checked) => updateAppearance(checked ? "system" : "dark")}
                    />
                  }
                />
                <SettingsItem
                  label={t("settings.appearance.theme")}
                  description={t("settings.appearance.theme.desc")}
                  action={
                    <Select
                      value={appearance === "system" ? "dark" : appearance}
                      onValueChange={(value) => updateAppearance(value as "light" | "dark")}
                      disabled={appearance === "system"}
                    >
                      <SelectTrigger className="w-40 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300 disabled:opacity-50 disabled:cursor-not-allowed">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="dark">{t("settings.appearance.themeDark")}</SelectItem>
                        <SelectItem value="light">{t("settings.appearance.themeLight")}</SelectItem>
                      </SelectContent>
                    </Select>
                  }
                />
                <SettingsItem
                  label={t("settings.appearance.codeTheme")}
                  description={t("settings.appearance.codeTheme.desc")}
                  action={
                    <div className="flex items-center gap-2">
                      <Button
                        variant="outline"
                        size="sm"
                        className="h-8 text-[11px] font-bold uppercase tracking-wider"
                        onClick={() => setShowThemePreview(!showThemePreview)}
                      >
                        {showThemePreview ? t("settings.appearance.preview.hide") : t("settings.appearance.preview.show")}
                      </Button>
                      <Select value={editorTheme} onValueChange={setEditorTheme}>
                        <SelectTrigger className="w-40 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="oneDark">One Dark</SelectItem>
                          <SelectItem value="vscDarkPlus">VS Code Dark</SelectItem>
                          <SelectItem value="nightOwl">Night Owl</SelectItem>
                          <SelectItem value="materialDark">Material Dark</SelectItem>
                          <SelectItem value="materialOceanic">Material Oceanic</SelectItem>
                          <SelectItem value="synthwave84">Synthwave '84</SelectItem>
                          <SelectItem value="shadesOfPurple">Shades of Purple</SelectItem>
                          <SelectItem value="dracula">Dracula</SelectItem>
                          <SelectItem value="nord">Nord</SelectItem>
                          <SelectItem value="atomDark">Atom Dark</SelectItem>
                          <SelectItem value="coldarkDark">Coldark</SelectItem>
                          <SelectItem value="gruvboxDark">Gruvbox Dark</SelectItem>
                          <SelectItem value="duotoneDark">Duotone Dark</SelectItem>
                          <SelectItem value="oneLight">One Light</SelectItem>
                          <SelectItem value="ghcolors">GitHub</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                  }
                />

                {showThemePreview && (
                  <div className="px-6 py-4 animate-in fade-in slide-in-from-top-2 duration-300">
                    <div className="rounded-xl border border-zinc-200 dark:border-white/5 overflow-hidden bg-[#0A0A0A] shadow-2xl">
                      <div className="bg-[#0D0D0D] px-4 py-2.5 border-b border-white/5 flex justify-between items-center bg-gradient-to-r from-[#0D0D0D] to-[#111111]">
                        <div className="flex items-center gap-2">
                          <div className="flex gap-1.5">
                            <div className="w-2.5 h-2.5 rounded-full bg-red-500/20 border border-red-500/40" />
                            <div className="w-2.5 h-2.5 rounded-full bg-amber-500/20 border border-amber-500/40" />
                            <div className="w-2.5 h-2.5 rounded-full bg-emerald-500/20 border border-emerald-500/40" />
                          </div>
                          <span className="text-[10px] uppercase tracking-widest font-bold text-zinc-500 ml-2">Preview: CreateUserAction.php</span>
                        </div>
                        <div className="flex items-center gap-2">
                          <span className="text-[9px] font-mono text-zinc-600 bg-white/5 px-1.5 py-0.5 rounded">PHP 8.4</span>
                        </div>
                      </div>
                      <div className="p-0 max-h-[350px] overflow-auto custom-scrollbar bg-transparent">
                        <SyntaxHighlighter
                          language="php"
                          style={CODE_THEMES[editorTheme] || oneDark}
                          showLineNumbers={true}
                          lineNumberStyle={{
                            minWidth: '3.5em',
                            paddingRight: '1.5em',
                            color: '#3f3f3f',
                            textAlign: 'right',
                            fontSize: '11px',
                            userSelect: 'none',
                            opacity: 0.5
                          }}
                          codeTagProps={{
                            style: {
                              background: 'none',
                            }
                          }}
                          customStyle={{
                            margin: 0,
                            padding: '1.5rem 0',
                            background: 'transparent',
                            fontSize: '13px',
                            fontFamily: 'JetBrains Mono, Menlo, Monaco, Consolas, monospace',
                            lineHeight: '1.7',
                          }}
                        >
                          {SAMPLE_CODE}
                        </SyntaxHighlighter>
                      </div>
                    </div>
                  </div>
                )}
                <SettingsItem
                  label={t("settings.appearance.zoom.label")}
                  description={t("settings.appearance.zoom.description")}
                  action={
                    <div className="flex items-center gap-3">
                      <button className="text-zinc-500 hover:text-zinc-900 dark:hover:text-white transition-colors h-6 w-6 flex items-center justify-center rounded hover:bg-zinc-100 dark:hover:bg-white/10"><Minus className="h-3 w-3" /></button>
                      <span className="text-[13px] text-zinc-900 dark:text-white w-10 text-center font-medium">100%</span>
                      <button className="text-zinc-500 hover:text-zinc-900 dark:hover:text-white transition-colors h-6 w-6 flex items-center justify-center rounded hover:bg-zinc-100 dark:hover:bg-white/10"><Plus className="h-3 w-3" /></button>
                    </div>
                  }
                />
                <SettingsItem
                  label={t("settings.appearance.terminalFont.label")}
                  description={t("settings.appearance.terminalFont.description")}
                  action={
                    <input
                      type="text"
                      placeholder={t("settings.appearance.terminalFont.placeholder")}
                      className="w-48 h-8 px-3 rounded-md bg-zinc-50 dark:bg-white/5 border border-zinc-200 dark:border-white/10 text-[13px] text-zinc-900 dark:text-white placeholder:text-zinc-400 dark:placeholder:text-zinc-600 focus:outline-none focus:border-purple-500 transition-colors"
                    />
                  }
                />
              </SettingsSection>
            </div>
          )}

          {activeTab === "behaviour" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection title={t("settings.behaviour.title")} description={t("settings.behaviour.description")} icon={SlidersHorizontal}>
                <SettingsItem
                  label={t("settings.behaviour.hideInactiveRepos.label")}
                  description={t("settings.behaviour.hideInactiveRepos.description")}
                  action={<Switch />}
                />
                <SettingsItem
                  label={t("settings.behaviour.sidebarSortOrder.label")}
                  description={t("settings.behaviour.sidebarSortOrder.description")}
                  action={
                    <Select defaultValue="repository">
                      <SelectTrigger className="w-40 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="repository">{t("settings.behaviour.sidebarSortOrder.repository")}</SelectItem>
                        <SelectItem value="recent">{t("settings.behaviour.sidebarSortOrder.recent")}</SelectItem>
                      </SelectContent>
                    </Select>
                  }
                />
                <SettingsItem
                  label={t("settings.behaviour.sendReviewComments.label")}
                  description={t("settings.behaviour.sendReviewComments.description")}
                  action={<Switch defaultChecked />}
                />
                <SettingsItem
                  label={t("settings.behaviour.inlineDiffResponses.label")}
                  description={t("settings.behaviour.inlineDiffResponses.description")}
                  action={<Switch />}
                />
                <SettingsItem
                  label={t("settings.behaviour.defaultMergeAction.label")}
                  description={t("settings.behaviour.defaultMergeAction.description")}
                  action={
                    <Select defaultValue="draft_pr">
                      <SelectTrigger className="w-44 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="draft_pr">{t("settings.behaviour.defaultMergeAction.draftPr")}</SelectItem>
                        <SelectItem value="merge_locally">{t("settings.behaviour.defaultMergeAction.mergeLocally")}</SelectItem>
                        <SelectItem value="merge_push">{t("settings.behaviour.defaultMergeAction.mergePush")}</SelectItem>
                      </SelectContent>
                    </Select>
                  }
                />
                <SettingsItem
                  label={t("settings.behaviour.fetchLatest.label")}
                  description={t("settings.behaviour.fetchLatest.description")}
                  action={<Switch defaultChecked />}
                />
                <SettingsItem
                  label={t("settings.behaviour.autoArchive.label")}
                  description={t("settings.behaviour.autoArchive.description")}
                  action={<Switch />}
                />
              </SettingsSection>
            </div>
          )}

          {activeTab === "notifications" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection title={t("settings.notifications.title")} description={t("settings.notifications.description")} icon={Bell}>
                <SettingsItem
                  label={t("settings.notifications.agentFinish.label")}
                  description={t("settings.notifications.agentFinish.description")}
                  action={<Switch defaultChecked />}
                />
                <SettingsItem
                  label={t("settings.notifications.dockBadge.label")}
                  description={t("settings.notifications.dockBadge.description")}
                  action={<Switch defaultChecked />}
                />
                <SettingsItem
                  label={t("settings.notifications.completionSound.label")}
                  description={t("settings.notifications.completionSound.description")}
                  action={
                    <Select defaultValue="unfocused">
                      <SelectTrigger className="w-48 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="unfocused">{t("settings.notifications.completionSound.unfocused")}</SelectItem>
                        <SelectItem value="always">{t("settings.notifications.completionSound.always")}</SelectItem>
                        <SelectItem value="never">{t("settings.notifications.completionSound.never")}</SelectItem>
                      </SelectContent>
                    </Select>
                  }
                />
                <SettingsItem
                  label={t("settings.notifications.sound.label")}
                  description={t("settings.notifications.sound.description")}
                  action={
                    <Select defaultValue="sparkle">
                      <SelectTrigger className="w-48 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="sparkle">{t("settings.notifications.sound.sparkleDing")}</SelectItem>
                        <SelectItem value="chime">{t("settings.notifications.sound.chime")}</SelectItem>
                        <SelectItem value="pop">{t("settings.notifications.sound.pop")}</SelectItem>
                      </SelectContent>
                    </Select>
                  }
                />
              </SettingsSection>
            </div>
          )}

          {activeTab === "integrations" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection title={t("settings.integrations.title")} description={t("settings.integrations.description")} icon={Blocks}>
                <SettingsItem
                  label={t("settings.integrations.nightwatch.label")}
                  description={t("settings.integrations.nightwatch.description")}
                  action={
                    <Button variant="outline" className="h-8 gap-2 bg-transparent hover:bg-zinc-100 dark:hover:bg-white/5 border-zinc-200 dark:border-white/10 dark:text-zinc-300">
                      <Unplug className="h-4 w-4" /> {t("common.disconnect")}
                    </Button>
                  }
                />
                <SettingsItem
                  label={t("settings.integrations.sentry.label")}
                  description={t("settings.integrations.sentry.description")}
                  action={
                    <Button variant="outline" className="h-8 gap-2 bg-transparent hover:bg-zinc-100 dark:hover:bg-white/5 border-zinc-200 dark:border-white/10 dark:text-zinc-300">
                      <Link2 className="h-4 w-4" /> {t("common.connect")}
                    </Button>
                  }
                />
                <SettingsItem
                  label={t("settings.integrations.defaultIde.label")}
                  description={t("settings.integrations.defaultIde.description")}
                  action={
                    <Select defaultValue="phpstorm">
                      <SelectTrigger className="w-32 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="vscode">VS Code</SelectItem>
                        <SelectItem value="cursor">Cursor</SelectItem>
                        <SelectItem value="phpstorm">PhpStorm</SelectItem>
                        <SelectItem value="webstorm">WebStorm</SelectItem>
                        <SelectItem value="intellij">IntelliJ IDEA</SelectItem>
                        <SelectItem value="zed">Zed</SelectItem>
                        <SelectItem value="sublime">Sublime Text</SelectItem>
                        <SelectItem value="rustrover">RustRover</SelectItem>
                      </SelectContent>
                    </Select>
                  }
                />
                <SettingsItem
                  label={t("settings.integrations.defaultTerminal.label")}
                  description={t("settings.integrations.defaultTerminal.description")}
                  action={
                    <Select defaultValue="ghostty">
                      <SelectTrigger className="w-32 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="terminal">Terminal</SelectItem>
                        <SelectItem value="iterm2">iTerm2</SelectItem>
                        <SelectItem value="warp">Warp</SelectItem>
                        <SelectItem value="ghostty">Ghostty</SelectItem>
                        <SelectItem value="kitty">Kitty</SelectItem>
                        <SelectItem value="alacritty">Alacritty</SelectItem>
                      </SelectContent>
                    </Select>
                  }
                />
              </SettingsSection>
            </div>
          )}

          {activeTab === "agents" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection title={t("settings.agents.title")} description={t("settings.agents.description")} icon={Bot}>
                <SettingsTextarea
                  label={t("settings.agents.envVars.label")}
                  description={t("settings.agents.envVars.description")}
                  defaultValue={`ANTHROPIC_API_KEY=sk-ant-...
CLAUDE_CODE_USE_BEDROCK=1
AWS_REGION=us-east-1
AWS_PROFILE=default`}
                />
              </SettingsSection>
            </div>
          )}

          {activeTab === "shortcuts" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection title={t("settings.shortcuts.title")} description={t("settings.shortcuts.description")} icon={Keyboard}>
                {[
                  { labelKey: "settings.shortcuts.toggleTerminal", keys: "⌘`" },
                  { labelKey: "settings.shortcuts.toggleSidebar", keys: "⌘B" },
                  { labelKey: "settings.shortcuts.toggleChanges", keys: "⌘D" },
                  { labelKey: "settings.shortcuts.toggleDiff", keys: "⌘⇧D" },
                  { labelKey: "settings.shortcuts.togglePreview", keys: "⌘P" },
                  { labelKey: "settings.shortcuts.mergePr", keys: "⌘⇧M" },
                  { labelKey: "settings.shortcuts.addAttachment", keys: "⌘⇧A" },
                  { labelKey: "settings.shortcuts.togglePlan", keys: "⌘⇧P" },
                  { labelKey: "settings.shortcuts.toggleOpinions", keys: "⌘⇧O" },
                  { labelKey: "settings.shortcuts.toggleDictation", keys: "⌘⇧V" },
                  { labelKey: "settings.shortcuts.focusPrompt", keys: "⌘L" },
                ].map((shortcut) => (
                  <SettingsItem
                    key={shortcut.labelKey}
                    label={t(shortcut.labelKey)}
                    action={
                      <div className="w-48 flex justify-end">
                        <div className="bg-zinc-100 dark:bg-white/5 border border-zinc-200 dark:border-white/10 rounded h-8 px-4 flex items-center justify-center font-mono text-[12px] text-zinc-600 dark:text-zinc-300 tracking-widest">
                          {shortcut.keys}
                        </div>
                      </div>
                    }
                  />
                ))}
              </SettingsSection>
            </div>
          )}

          {activeTab === "dictation" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection title={t("settings.dictation.title")} description={t("settings.dictation.description")} icon={Mic}>
                <SettingsItem
                  label={t("settings.dictation.method.label")}
                  description={t("settings.dictation.method.description")}
                  action={
                    <Select defaultValue="web_speech">
                      <SelectTrigger className="w-40 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="web_speech">{t("settings.dictation.method.webSpeech")}</SelectItem>
                        <SelectItem value="custom">{t("settings.dictation.method.custom")}</SelectItem>
                      </SelectContent>
                    </Select>
                  }
                />
              </SettingsSection>
            </div>
          )}

          {activeTab === "sync" && <SyncSettingsTab />}

          {activeTab === "advanced" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection title={t("settings.advanced.title")} description={t("settings.advanced.description")} icon={Wrench}>
                <SettingsItem
                  label={t("settings.advanced.debug.label")}
                  description={t("settings.advanced.debug.description")}
                  action={<Switch />}
                />
              </SettingsSection>
              <SettingsSection
                title={t("settings.section.privacy")}
                description={t("settings.advanced.privacy.description")}
                icon={Shield}
              >
                <SettingsItem
                  label={t("settings.privacy.clearHistory")}
                  description={t("settings.privacy.clearHistoryDesc")}
                  action={
                    <button
                      onClick={handleClearHistory}
                      className="text-sm font-bold text-purple-500 hover:text-purple-400 transition-colors"
                    >
                      {t("settings.privacy.clear")}
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
                      {t("settings.privacy.clearAll")}
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

          {activeTab === "vcs-providers" && (() => {
            const connectedKinds = new Set(providers.map((p) => p.kind));
            return (
              <div className="animate-in fade-in duration-300">
                <div className="flex justify-end mb-4">
                  <Button onClick={() => setIsProviderDialogOpen(true)}>
                    <Plus size={18} /> {t("settings.vcsProviders.addManual")}
                  </Button>
                </div>

                {([
                  { kind: "github" as ProviderKind, title: "GitHub", descKey: "settings.vcsProviders.github.description", icon: Github },
                  { kind: "gitlab" as ProviderKind, title: "GitLab", descKey: "settings.vcsProviders.gitlab.description", icon: GitlabIcon },
                  { kind: "bitbucket" as ProviderKind, title: "Bitbucket", descKey: "settings.vcsProviders.bitbucket.description", icon: Blocks },
                ]).map(({ kind, title, descKey, icon }) => {
                  const connectedProvider = providers.find((p) => p.kind === kind);
                  return (
                    <SettingsSection key={kind} title={title} description={t("settings.vcsProviders.connectAccount").replace("{title}", title)} icon={icon}>
                      <SettingsItem
                        label={title}
                        description={t(descKey)}
                        action={
                          connectedKinds.has(kind) ? (
                            <div className="flex items-center gap-2">
                              {connectedProvider?.account_login && (
                                <span className="text-sm text-zinc-500">{t("settings.vcsProviders.connectedAs").replace("{login}", connectedProvider.account_login)}</span>
                              )}
                              <Badge variant="secondary" className="text-emerald-500 border-emerald-500/20 bg-emerald-500/10">{t("common.connected")}</Badge>
                              <Button variant="outline" size="sm" onClick={() => { if (connectedProvider) { setActiveProviderId(connectedProvider.id); navigateTo("provider-detail"); } }}>{t("common.manage")}</Button>
                            </div>
                          ) : kind === "github" ? (
                            <Button onClick={() => connectGithub()}>
                              <Link2 size={18} /> {t("common.connect")}
                            </Button>
                          ) : (
                            <div className="flex items-center gap-2">
                              <Badge variant="secondary" className="text-zinc-500 border-zinc-200 dark:border-zinc-700 dark:text-zinc-400">
                                {t("common.comingSoon")}
                              </Badge>
                              <Button disabled>
                                <Link2 size={18} /> {t("common.connect")}
                              </Button>
                            </div>
                          )
                        }
                      />
                    </SettingsSection>
                  );
                })}

                <AddProviderDialog
                  open={isProviderDialogOpen}
                  onOpenChange={setIsProviderDialogOpen}
                  onSubmit={createProvider}
                />
              </div>
            );
          })()}

          {activeTab === "workspaces" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection
                title={t("settings.workspaces.title")}
                description={t("settings.workspaces.description")}
                icon={FolderGit2}
              >
                <SettingsItem
                  label={t("settings.workspaces.defaultDir.label")}
                  description={t("settings.workspaces.defaultDir.description")}
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
                title={t("settings.prompts.title")}
                description={t("settings.prompts.description")}
                icon={FileText}
              >
                {([
                  { action: "merge_local", labelKey: "settings.prompts.mergeLocal.label", descKey: "settings.prompts.mergeLocal.description" },
                  { action: "merge_push",  labelKey: "settings.prompts.mergePush.label",  descKey: "settings.prompts.mergePush.description" },
                  { action: "draft_pr",    labelKey: "settings.prompts.draftPr.label",    descKey: "settings.prompts.draftPr.description" },
                  { action: "create_pr",   labelKey: "settings.prompts.createPr.label",   descKey: "settings.prompts.createPr.description" },
                ] as const).map(({ action, labelKey, descKey }) => {
                  const label = t(labelKey);
                  const description = t(descKey);
                  const isCustomized = action in promptOverrides;
                  // Value shown in the textarea: draft > saved override > empty (default is hidden).
                  const storedValue  = isCustomized ? promptOverrides[action] : "";
                  const draftValue   = promptDrafts[action];
                  const currentValue = draftValue ?? storedValue;
                  const isDirty      = draftValue !== undefined && draftValue !== storedValue;

                  const handleSave = async () => {
                    setSavingPrompt(action);
                    try {
                      if (currentValue.trim() === "") {
                        // Treat clearing as a reset
                        await resetPrompt(action);
                      } else {
                        await savePrompt(action, currentValue);
                      }
                      setPromptDrafts((prev) => { const next = { ...prev }; delete next[action]; return next; });
                    } finally {
                      setSavingPrompt(null);
                    }
                  };

                  const handleReset = async () => {
                    setSavingPrompt(action);
                    try {
                      await resetPrompt(action);
                      setPromptDrafts((prev) => { const next = { ...prev }; delete next[action]; return next; });
                    } finally {
                      setSavingPrompt(null);
                    }
                  };

                  return (
                    <div key={action} className="flex flex-col gap-3 px-4 py-6 border-b border-zinc-100 dark:border-zinc-800/50 last:border-0">
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-2">
                          <p className="text-sm font-medium text-zinc-900 dark:text-white">{label}</p>
                          <span className={cn(
                            "text-[9px] font-bold uppercase tracking-wider px-1.5 py-0.5 rounded",
                            isCustomized
                              ? "bg-purple-500/10 text-purple-400 border border-purple-500/20"
                              : "bg-zinc-100 dark:bg-zinc-800 text-zinc-400 border border-zinc-200 dark:border-zinc-700"
                          )}>
                            {isCustomized ? t("settings.prompts.badge.custom") : t("settings.prompts.badge.default")}
                          </span>
                        </div>
                        <div className="flex items-center gap-2">
                          {isCustomized && !isDirty && (
                            <Button
                              variant="ghost"
                              size="sm"
                              disabled={savingPrompt === action}
                              onClick={handleReset}
                              className="h-7 px-2.5 text-[11px] text-zinc-400 hover:text-white"
                            >
                              {t("settings.prompts.resetToDefault")}
                            </Button>
                          )}
                          {isDirty && (
                            <Button
                              size="sm"
                              disabled={savingPrompt === action}
                              onClick={handleSave}
                              className="h-7 px-3 text-[11px] bg-purple-600 hover:bg-purple-700 text-white"
                            >
                              {savingPrompt === action ? t("common.saving") : t("common.save")}
                            </Button>
                          )}
                        </div>
                      </div>
                      <textarea
                        className="w-full h-36 bg-zinc-50 dark:bg-black/20 border border-zinc-200 dark:border-white/5 rounded-md text-zinc-600 dark:text-zinc-400 font-mono text-[13px] p-4 focus:outline-none focus:border-purple-500 transition-colors custom-scrollbar resize-none placeholder:text-zinc-400 dark:placeholder:text-zinc-600 placeholder:font-sans placeholder:not-italic"
                        placeholder={PROMPT_PLACEHOLDERS[action]}
                        value={currentValue}
                        onChange={(e) => setPromptDrafts((prev) => ({ ...prev, [action]: e.target.value }))}
                      />
                      <p className="text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed">{description}</p>
                    </div>
                  );
                })}
              </SettingsSection>
            </div>
          )}
        </div>

        {showResetConfirm && (
          <div className="animate-fade-in fixed inset-0 z-[150] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm">
            <div className="animate-scale-in w-full max-w-sm rounded-md border border-zinc-200 bg-white p-6 shadow-2xl dark:border-zinc-800 dark:bg-[#18181b]">
              <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-red-100 text-red-600 dark:bg-red-500/10 dark:text-red-500">
                <AlertTriangle size={24} />
              </div>
              <h3 className="mb-2 text-center text-xl font-bold text-zinc-900 dark:text-white">{t("modal.reset.title")}</h3>
              <p className="mb-6 text-center text-sm text-zinc-500 dark:text-zinc-400">
                {t("modal.reset.desc")}
              </p>
              <div className="flex gap-3">
                <button
                  onClick={() => setShowResetConfirm(false)}
                  className="flex-1 rounded-md bg-zinc-100 py-3 font-bold text-zinc-700 hover:bg-zinc-200 dark:bg-zinc-800 dark:text-zinc-300 dark:hover:bg-zinc-700"
                >
                  {t("modal.reset.cancel")}
                </button>
                <button
                  onClick={handleFactoryReset}
                  className="flex-1 rounded-md bg-red-600 py-3 font-bold text-white shadow-lg shadow-red-600/20 hover:bg-red-700"
                >
                  {t("modal.reset.confirm")}
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
