import { useState, useEffect, useTransition, Activity } from "react";
import {
  Settings2,
  Palette,
  SlidersHorizontal,
  Bell,
  // Blocks,
  // Bot,
  // Keyboard,
  // Mic,
  // Wrench,
  Unplug,
  // FolderGit2,
  FileText,
  // Smartphone,
  RefreshCw,
  CreditCard,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { useDateLabel } from "@/hooks/use-date-label";
import {
  PageHeader,
  PageHeaderMeta,
  PageHeaderTitle,
} from "@/components/layout/page-header";
import { PageLayout } from "@/components/layout/page-layout";
import { GeneralTab } from "@/components/settings/general-tab";
import { AppearanceTab } from "@/components/settings/appearance-tab";
import { BehaviourTab } from "@/components/settings/behaviour-tab";
import { NotificationsTab } from "@/components/settings/notifications-tab";
import { IntegrationsTab } from "@/components/settings/integrations-tab";
import { AgentsTab } from "@/components/settings/agents-tab";
import { RemoteTab } from "@/components/settings/remote-tab";
import { ShortcutsTab } from "@/components/settings/shortcuts-tab";
import { DictationTab } from "@/components/settings/dictation-tab";
import { SyncSettingsTab } from "@/components/settings/sync-settings-tab";
import { AdvancedTab } from "@/components/settings/advanced-tab";
import { VcsProvidersTab } from "@/components/settings/vcs-providers-tab";
import { WorkspacesTab } from "@/components/settings/workspaces-tab";
import { PromptsTab } from "@/components/settings/prompts-tab";
import { SubscriptionTab } from "@/components/settings/subscription-tab";

type TabId =
  | "general" | "appearance" | "behaviour" | "notifications"
  | "integrations" | "agents" | "remote" | "sync" | "shortcuts" | "dictation"
  | "advanced" | "vcs-providers" | "workspaces" | "prompts" | "subscription";

const COMING_SOON_TABS: TabId[] = ["integrations", "agents", "dictation", "workspaces", "remote", "shortcuts", "advanced"];

const SHOW_COMING_SOON = import.meta.env.DEV;

import { useNavigationStore } from "@/stores/navigation-store";

export function SettingsPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const settingsTab = useNavigationStore((s) => s.settingsTab);
  const setSettingsTab = useNavigationStore((s) => s.setSettingsTab);
  const [activeTab, setActiveTab] = useState<TabId>((settingsTab as TabId) ?? "general");
  const [isPending, startTransition] = useTransition();

  useEffect(() => {
    if (settingsTab && settingsTab !== activeTab) {
      startTransition(() => setActiveTab(settingsTab as TabId));
    }
  }, [settingsTab]);

  const handleTabChange = (id: TabId) => {
    startTransition(() => {
      setActiveTab(id);
      setSettingsTab(id);
    });
  };

  const SETTINGS_GROUPS = [
    {
      id: "application",
      group: t("settings.groups.application"),
      items: [
        { id: "general" as TabId,       label: t("settings.tabs.general"),       icon: <Settings2 className="h-4 w-4" /> },
        { id: "appearance" as TabId,    label: t("settings.tabs.appearance"),     icon: <Palette className="h-4 w-4" /> },
        { id: "behaviour" as TabId,     label: t("settings.tabs.behaviour"),      icon: <SlidersHorizontal className="h-4 w-4" /> },
        { id: "notifications" as TabId, label: t("settings.tabs.notifications"),  icon: <Bell className="h-4 w-4" /> },
        { id: "subscription" as TabId,  label: t("settings.tabs.subscription"),   icon: <CreditCard className="h-4 w-4" /> },
      ],
    },
    {
      id: "features",
      group: t("settings.groups.features"),
      items: [
        // { id: "integrations" as TabId, label: t("settings.tabs.integrations"), icon: <Blocks className="h-4 w-4" /> },
        // { id: "agents" as TabId,       label: t("settings.tabs.agents"),        icon: <Bot className="h-4 w-4" /> },
        // { id: "remote" as TabId,       label: t("settings.tabs.remote"),        icon: <Smartphone className="h-4 w-4" /> },
        { id: "sync" as TabId,         label: t("settings.tabs.sync"),          icon: <RefreshCw className="h-4 w-4" /> },
        // { id: "shortcuts" as TabId,    label: t("settings.tabs.shortcuts"),     icon: <Keyboard className="h-4 w-4" /> },
        // { id: "dictation" as TabId,    label: t("settings.tabs.dictation"),     icon: <Mic className="h-4 w-4" /> },
      ],
    },
    {
      id: "development",
      group: t("settings.groups.development"),
      items: [
        // { id: "advanced" as TabId,       label: t("settings.tabs.advanced"),      icon: <Wrench className="h-4 w-4" /> },
        { id: "vcs-providers" as TabId,  label: t("settings.tabs.vcsProviders"),  icon: <Unplug className="h-4 w-4" /> },
        // { id: "workspaces" as TabId,     label: t("settings.tabs.workspaces"),    icon: <FolderGit2 className="h-4 w-4" /> },
        { id: "prompts" as TabId,        label: t("settings.tabs.prompts"),       icon: <FileText className="h-4 w-4" /> },
      ],
    },
  ];

  const ALL_TABS: TabId[] = SETTINGS_GROUPS.flatMap((g) => g.items.map((i) => i.id));

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

      <div className="mx-auto w-full max-w-6xl pb-6 flex gap-6">
        <div className="w-64 shrink-0 flex flex-col gap-6">
          {SETTINGS_GROUPS.filter((group) =>
            group.items.some((tab) => SHOW_COMING_SOON || !COMING_SOON_TABS.includes(tab.id)),
          ).map((group) => (
            <div key={group.id} className="flex flex-col gap-1">
              <h3 className="px-3 text-[11px] font-bold uppercase tracking-[0.1em] text-zinc-400/60 mb-2">
                {group.group}
              </h3>
              <div className="flex flex-col gap-0.5">
                {group.items
                  .filter((tab) => SHOW_COMING_SOON || !COMING_SOON_TABS.includes(tab.id))
                  .map((tab) => {
                  const isComingSoon = COMING_SOON_TABS.includes(tab.id);
                  return (
                    <button
                      key={tab.id}
                      onClick={() => !isComingSoon && handleTabChange(tab.id)}
                      className={cn(
                        "flex items-center gap-3 px-3 py-2 rounded-md text-[13px] transition-all duration-200 w-full",
                        isComingSoon
                          ? "opacity-40 cursor-not-allowed"
                          : activeTab === tab.id
                          ? "bg-zinc-100 dark:bg-zinc-800 text-zinc-900 dark:text-white font-semibold shadow-sm"
                          : "text-zinc-500 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-zinc-200 hover:bg-zinc-50 dark:hover:bg-zinc-800/30",
                        isPending && activeTab !== tab.id && "opacity-70",
                      )}
                    >
                      <div className={cn(
                        "transition-colors duration-200",
                        isComingSoon ? "text-zinc-500" : activeTab === tab.id ? "text-purple-500" : "text-zinc-400 dark:text-zinc-500",
                      )}>
                        {tab.icon}
                      </div>
                      <span className="flex-1 text-left">{tab.label}</span>
                      {isComingSoon && (
                        <span className="text-[9px] font-bold uppercase tracking-widest text-zinc-500 border border-zinc-700/50 rounded px-1 py-px">
                          Soon
                        </span>
                      )}
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </div>

        <div className="flex-1 min-w-0">
          {ALL_TABS.map((id) => (
            <Activity key={id} mode={activeTab === id ? "visible" : "hidden"}>
              {id === "general"       && <GeneralTab />}
              {id === "appearance"    && <AppearanceTab />}
              {id === "behaviour"     && <BehaviourTab />}
              {id === "notifications" && <NotificationsTab />}
              {id === "integrations"  && <IntegrationsTab />}
              {id === "agents"        && <AgentsTab />}
              {id === "remote"        && <RemoteTab />}
              {id === "sync"          && <SyncSettingsTab />}
              {id === "shortcuts"     && <ShortcutsTab />}
              {id === "dictation"     && <DictationTab />}
              {id === "advanced"      && <AdvancedTab />}
              {id === "vcs-providers" && <VcsProvidersTab />}
              {id === "workspaces"    && <WorkspacesTab />}
              {id === "prompts"       && <PromptsTab />}
              {id === "subscription"  && <SubscriptionTab />}
            </Activity>
          ))}
        </div>
      </div>
    </PageLayout>
  );
}
