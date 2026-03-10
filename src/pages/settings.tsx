import { useState } from "react";
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
} from "lucide-react";

import { Card, CardContent, CardDescription, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { cn } from "@/lib/utils";
import UpgradeModal from "@/components/upgrade-modal";
import { useI18n } from "@/i18n/i18n";
import { useDateLabel } from "@/hooks/use-date-label";
import {
  PageHeader,
  PageHeaderMeta,
  PageHeaderTitle,
} from "@/components/layout/page-header";
import { PageLayout } from "@/components/layout/page-layout";
import { Button } from "@/components/ui/button";

const SETTINGS_GROUPS = [
  {
    group: "Application",
    items: [
      { id: "general", label: "General", icon: <Settings2 className="h-4 w-4" /> },
      { id: "appearance", label: "Appearance", icon: <Palette className="h-4 w-4" /> },
      { id: "behaviour", label: "Behaviour", icon: <SlidersHorizontal className="h-4 w-4" /> },
      { id: "notifications", label: "Notifications", icon: <Bell className="h-4 w-4" /> },
    ]
  },
  {
    group: "Features",
    items: [
      { id: "integrations", label: "Integrations", icon: <Blocks className="h-4 w-4" /> },
      { id: "agents", label: "Coding Agents", icon: <Bot className="h-4 w-4" /> },
      { id: "shortcuts", label: "Shortcuts", icon: <Keyboard className="h-4 w-4" /> },
      { id: "dictation", label: "Dictation", icon: <Mic className="h-4 w-4" /> },
    ]
  },
  {
    group: "Development",
    items: [
      { id: "advanced", label: "Advanced", icon: <Wrench className="h-4 w-4" /> },
      { id: "github", label: "GitHub", icon: <Github className="h-4 w-4" /> },
      { id: "workspaces", label: "Workspaces", icon: <FolderGit2 className="h-4 w-4" /> },
      { id: "prompts", label: "Prompts", icon: <FileText className="h-4 w-4" /> },
    ]
  }
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

  const mergePrompt = `Merge the changes from this worktree into the base branch locally.

Steps:
1. Check for uncommitted changes with \`git status --porcelain\`
2. If there are uncommitted changes, stage them all with \`git add -A\` and commit with a meaningful, short message that describes the changes.`;

  const mergePushPrompt = `Merge the changes from this worktree into the base branch and push to the remote.

Steps:
1. Check for uncommitted changes with \`git status --porcelain\`
2. If there are uncommitted changes, stage them all with \`git add -A\` and commit with a meaningful, short message that describes the changes.`;

  const prPrompt = `Create a pull request for the changes on this branch.

Steps:
1. Check for uncommitted changes with \`git status --porcelain\`
2. If there are uncommitted changes, stage them all with \`git add -A\` and commit with a meaningful, short message that describes the changes.`;

  const draftPrPrompt = `Create a draft pull request for the changes on this branch.

Steps:
1. Check for uncommitted changes with \`git status --porcelain\`
2. If there are uncommitted changes, stage them all with \`git add -A\` and commit with a meaningful, short message that describes the changes.`;

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
            <div key={group.group} className="flex flex-col gap-1">
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
                title="Account"
                description="Manage your account profile and access limits."
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
                          <span className="text-[10px] bg-amber-500/10 text-amber-500 px-1.5 py-0.5 rounded font-medium">Trial</span>
                        </div>
                        <span className="text-[13px] text-zinc-500">kidiatoliny@akira-io.com</span>
                      </div>
                    </div>
                    <button className="flex items-center gap-2 text-[13px] text-zinc-400 hover:text-zinc-900 dark:hover:text-white transition-colors">
                      <LogOut className="h-4 w-4" />
                      Sign out
                    </button>
                  </div>

                  <div className="p-5 rounded-md border border-zinc-100 bg-zinc-50 dark:border-white/5 dark:bg-white/[0.02]">
                    <h3 className="text-[14px] text-zinc-900 dark:text-zinc-400 mb-3 font-medium dark:font-normal">Upgrade for mobile and web access.</h3>
                    <ul className="space-y-2 mb-4">
                      <li className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-400">
                        <span className="text-blue-500">✓</span> Access from mobile, tablet, or any browser
                      </li>
                      <li className="flex items-center gap-2 text-[13px] text-zinc-600 dark:text-zinc-400">
                        <span className="text-blue-500">✓</span> Start and monitor workspaces on the go
                      </li>
                    </ul>
                    <Button className="w-full" variant="default">
                      Upgrade
                    </Button>
                  </div>
                </div>

                <SettingsItem
                  label="Launch at login"
                  description="Automatically start Polyscope when you log in. It will run in the menubar so the server is always available."
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
                title="Appearance"
                description={t("settings.general.appearanceDesc")}
                icon={Palette}
              >
                <SettingsItem
                  label="Sync with system"
                  description="Automatically switch between dark and light themes based on your system appearance."
                  action={<Switch />}
                />
                <SettingsItem
                  label="Theme"
                  description="Choose a color theme for the interface."
                  action={
                    <Select defaultValue="dark">
                      <SelectTrigger className="w-40 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="dark">Default Dark</SelectItem>
                        <SelectItem value="light">Light</SelectItem>
                      </SelectContent>
                    </Select>
                  }
                />
                <SettingsItem
                  label="Zoom"
                  description="Adjust the interface zoom level. ⌘+/⌘-"
                  action={
                    <div className="flex items-center gap-3">
                      <button className="text-zinc-500 hover:text-zinc-900 dark:hover:text-white transition-colors h-6 w-6 flex items-center justify-center rounded hover:bg-zinc-100 dark:hover:bg-white/10"><Minus className="h-3 w-3" /></button>
                      <span className="text-[13px] text-zinc-900 dark:text-white w-10 text-center font-medium">100%</span>
                      <button className="text-zinc-500 hover:text-zinc-900 dark:hover:text-white transition-colors h-6 w-6 flex items-center justify-center rounded hover:bg-zinc-100 dark:hover:bg-white/10"><Plus className="h-3 w-3" /></button>
                    </div>
                  }
                />
                <SettingsItem
                  label="Terminal font"
                  description="Custom font family for the built-in terminal. Useful for nerd fonts with icon support. Leave empty to use the default font."
                  action={
                    <input
                      type="text"
                      placeholder="e.g. MesloLGS NF"
                      className="w-48 h-8 px-3 rounded-md bg-zinc-50 dark:bg-white/5 border border-zinc-200 dark:border-white/10 text-[13px] text-zinc-900 dark:text-white placeholder:text-zinc-400 dark:placeholder:text-zinc-600 focus:outline-none focus:border-purple-500 transition-colors"
                    />
                  }
                />
              </SettingsSection>
            </div>
          )}

          {activeTab === "behaviour" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection title="Behaviour" description="Configure application behavior and workflow settings." icon={SlidersHorizontal}>
                <SettingsItem
                  label="Hide inactive repositories"
                  description="Only show repositories that have active workspaces in the sidebar."
                  action={<Switch />}
                />
                <SettingsItem
                  label="Sidebar sort order"
                  description="Choose how workspaces are organized in the sidebar."
                  action={
                    <Select defaultValue="repository">
                      <SelectTrigger className="w-40 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="repository">Repository</SelectItem>
                        <SelectItem value="recent">Recent</SelectItem>
                      </SelectContent>
                    </Select>
                  }
                />
                <SettingsItem
                  label="Send review comments immediately"
                  description="Send diff comments directly to the agent when you submit them. When off, comments are pasted into the prompt input when you close the diff."
                  action={<Switch defaultChecked />}
                />
                <SettingsItem
                  label="Show inline diff comment responses"
                  description="Display the assistant response directly under sent diff comments. Responses stay collapsed by default."
                  action={<Switch />}
                />
                <SettingsItem
                  label="Default Merge Action"
                  description='The primary action shown on the merge button. "Merge locally" merges into the base branch only. "Merge and push" also pushes to the remote.'
                  action={
                    <Select defaultValue="draft_pr">
                      <SelectTrigger className="w-44 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="draft_pr">Draft pull request</SelectItem>
                        <SelectItem value="merge_locally">Merge locally</SelectItem>
                        <SelectItem value="merge_push">Merge and push</SelectItem>
                      </SelectContent>
                    </Select>
                  }
                />
                <SettingsItem
                  label="Fetch latest from origin"
                  description="When enabled, new workspaces start from the latest remote state. When disabled, they start from the current local base branch."
                  action={<Switch defaultChecked />}
                />
                <SettingsItem
                  label="Auto-archive workspaces"
                  description="Automatically remove workspaces after merging or creating a PR, once CI passes."
                  action={<Switch />}
                />
              </SettingsSection>
            </div>
          )}

          {activeTab === "notifications" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection title="Notifications" description="Choose how and when alerts are presented." icon={Bell}>
                <SettingsItem
                  label="Notify when agent finishes"
                  description="Show a native notification when an agent completes its work and the app is not focused."
                  action={<Switch defaultChecked />}
                />
                <SettingsItem
                  label="Dock badge"
                  description="Show the number of workspaces needing attention as a badge on the dock icon."
                  action={<Switch defaultChecked />}
                />
                <SettingsItem
                  label="Completion sound"
                  description="Play a sound when an agent completes its work."
                  action={
                    <Select defaultValue="unfocused">
                      <SelectTrigger className="w-48 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="unfocused">When not focused</SelectItem>
                        <SelectItem value="always">Always</SelectItem>
                        <SelectItem value="never">Never</SelectItem>
                      </SelectContent>
                    </Select>
                  }
                />
                <SettingsItem
                  label="Sound"
                  description="Choose which notification sound to play."
                  action={
                    <Select defaultValue="sparkle">
                      <SelectTrigger className="w-48 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="sparkle">Sparkle Ding</SelectItem>
                        <SelectItem value="chime">Chime</SelectItem>
                        <SelectItem value="pop">Pop</SelectItem>
                      </SelectContent>
                    </Select>
                  }
                />
              </SettingsSection>
            </div>
          )}

          {activeTab === "integrations" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection title="Integrations" description="Manage connections to internal and external tools." icon={Blocks}>
                <SettingsItem
                  label="Nightwatch"
                  description="Laravel error tracking"
                  action={
                    <Button variant="outline" className="h-8 gap-2 bg-transparent hover:bg-zinc-100 dark:hover:bg-white/5 border-zinc-200 dark:border-white/10 dark:text-zinc-300">
                      <Unplug className="h-4 w-4" /> Disconnect
                    </Button>
                  }
                />
                <SettingsItem
                  label="Sentry"
                  description="Error tracking and performance monitoring"
                  action={
                    <Button variant="outline" className="h-8 gap-2 bg-transparent hover:bg-zinc-100 dark:hover:bg-white/5 border-zinc-200 dark:border-white/10 dark:text-zinc-300">
                      <Link2 className="h-4 w-4" /> Connect
                    </Button>
                  }
                />
                <SettingsItem
                  label="Default IDE"
                  description="Used by the Command Palette action for opening the current workspace."
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
                  label="Default Terminal"
                  description="Used when opening a workspace in a terminal."
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
              <SettingsSection title="Coding Agents" description="Configure parameters for AI execution." icon={Bot}>
                <SettingsTextarea
                  label="Environment Variables"
                  description="Configure environment variables that will be passed to Claude Code. One per line, format: VAR_NAME=value or export VAR_NAME=value"
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
              <SettingsSection title="Shortcuts" description="Keyboard shortcuts to boost your productivity." icon={Keyboard}>
                {[
                  { label: "Toggle Terminal", keys: "⌘`" },
                  { label: "Toggle Sidebar", keys: "⌘B" },
                  { label: "Toggle Changes Panel", keys: "⌘D" },
                  { label: "Toggle Diff View", keys: "⌘⇧D" },
                  { label: "Toggle Preview", keys: "⌘P" },
                  { label: "Merge / Pull Request", keys: "⌘⇧M" },
                  { label: "Add Attachment", keys: "⌘⇧A" },
                  { label: "Toggle Plan Mode", keys: "⌘⇧P" },
                  { label: "Toggle Opinions", keys: "⌘⇧O" },
                  { label: "Toggle Dictation", keys: "⌘⇧V" },
                  { label: "Focus Prompt Input", keys: "⌘L" },
                ].map((shortcut) => (
                  <SettingsItem
                    key={shortcut.label}
                    label={shortcut.label}
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
              <SettingsSection title="Dictation" description="Choose the speech recognition method for prompt dictation." icon={Mic}>
                <SettingsItem
                  label="Speech Recognition Method"
                  description="Uses the built-in speech recognition capabilities of your operating system. Lower accuracy and limited language support. No data will be sent to any servers."
                  action={
                    <Select defaultValue="web_speech">
                      <SelectTrigger className="w-40 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="web_speech">Web Speech</SelectItem>
                        <SelectItem value="custom">Custom Engine</SelectItem>
                      </SelectContent>
                    </Select>
                  }
                />
              </SettingsSection>
            </div>
          )}

          {activeTab === "advanced" && (
            <div className="animate-in fade-in duration-300">
              <SettingsSection title="Advanced" description="Developer options." icon={Wrench}>
                <SettingsItem
                  label="Show all agent events (debug)"
                  description="Shows raw agent and ask-user events in the activity feed."
                  action={<Switch />}
                />
              </SettingsSection>
              <SettingsSection
                title={t("settings.section.privacy")}
                description="Manage your privacy and data settings here."
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
            <div className="animate-scale-in w-full max-w-sm rounded-md border border-zinc-200 bg-white p-6 shadow-2xl dark:border-zinc-800 dark:bg-[#18181b]">
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
                  className="flex-1 rounded-md bg-zinc-100 py-3 font-bold text-zinc-700 hover:bg-zinc-200 dark:bg-zinc-800 dark:text-zinc-300 dark:hover:bg-zinc-700"
                >
                  Cancelar
                </button>
                <button
                  onClick={handleFactoryReset}
                  className="flex-1 rounded-md bg-red-600 py-3 font-bold text-white shadow-lg shadow-red-600/20 hover:bg-red-700"
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
