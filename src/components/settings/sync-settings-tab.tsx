import { RefreshCw } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { Card, CardContent, CardDescription, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { useI18n } from "@/i18n/i18n";
import { issueScopeLabelKey, prScopeLabelKey } from "@/lib/work-visibility";
import { useSettingsStore } from "@/stores/settings-store";
import { useSyncSettingsStore, GLOBAL_SYNC_ID, INTERVAL_OPTIONS } from "@/stores/sync-settings-store";
import type { SyncSettingsDto, UpsertSyncSettingsInput } from "@/stores/sync-settings-store";
import type { IssueScope, PullRequestScope } from "@/types/work-visibility";

const DEFAULT_SETTINGS: Omit<SyncSettingsDto, "id" | "scope"> = {
  syncIssuesEnabled: true,
  syncIssuesIntervalSecs: 900,
  syncPrsEnabled: true,
  syncPrsIntervalSecs: 300,
  syncReposEnabled: true,
  syncReposIntervalSecs: 1800,
  syncOrgsEnabled: true,
  syncOrgsIntervalSecs: 7200,
};

function effective(settings: SyncSettingsDto | null): SyncSettingsDto {
  return settings ?? { id: GLOBAL_SYNC_ID, scope: "global", ...DEFAULT_SETTINGS };
}

function SettingsSection({
  title,
  description,
  children,
  icon: Icon,
}: {
  title: string;
  description?: string;
  children: React.ReactNode;
  icon?: React.ComponentType<{ size?: number; strokeWidth?: number }>;
}) {
  return (
    <Card className="mb-6 overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
      <div className="flex flex-row items-center gap-4 px-6 py-6 pb-6">
        {Icon && (
          <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
            <Icon size={22} strokeWidth={2} />
          </div>
        )}
        <div className="flex flex-col gap-1">
          <CardTitle className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">
            {title}
          </CardTitle>
          {description && (
            <CardDescription className="text-[13px] font-medium text-zinc-500/80 leading-none">
              {description}
            </CardDescription>
          )}
        </div>
      </div>
      <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
        {children}
      </CardContent>
    </Card>
  );
}

function SettingsItem({
  label,
  description,
  action,
}: {
  label: string;
  description?: string;
  action: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between px-4 py-6 transition-colors hover:bg-zinc-50 dark:hover:bg-zinc-900/40">
      <div className="flex flex-col gap-1 w-full max-w-[65%]">
        <p className="text-sm font-medium text-zinc-900 dark:text-white">{label}</p>
        {description && (
          <p className="text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed">{description}</p>
        )}
      </div>
      <div className="shrink-0 text-zinc-700 dark:text-zinc-200">{action}</div>
    </div>
  );
}

export function SyncSettingsTab() {
  const { t } = useI18n();
  const { saveSettings, globalSettings } = useSyncSettingsStore();
  const {
    defaultIssueScope,
    defaultPrScope,
    assignIssuesToSelfByDefault,
    setDefaultIssueScope,
    setDefaultPrScope,
    setAssignIssuesToSelfByDefault,
  } = useSettingsStore();

  const global = effective(globalSettings);

  const handleSave = async (patch: Partial<SyncSettingsDto>) => {
    const input: UpsertSyncSettingsInput = {
      id: GLOBAL_SYNC_ID,
      syncIssuesEnabled: patch.syncIssuesEnabled ?? global.syncIssuesEnabled,
      syncIssuesIntervalSecs: patch.syncIssuesIntervalSecs ?? global.syncIssuesIntervalSecs,
      syncPrsEnabled: patch.syncPrsEnabled ?? global.syncPrsEnabled,
      syncPrsIntervalSecs: patch.syncPrsIntervalSecs ?? global.syncPrsIntervalSecs,
      syncReposEnabled: patch.syncReposEnabled ?? global.syncReposEnabled,
      syncReposIntervalSecs: patch.syncReposIntervalSecs ?? global.syncReposIntervalSecs,
      syncOrgsEnabled: patch.syncOrgsEnabled ?? global.syncOrgsEnabled,
      syncOrgsIntervalSecs: patch.syncOrgsIntervalSecs ?? global.syncOrgsIntervalSecs,
    };
    await saveSettings(input);
  };

  const persistVisibility = async (
    issueScope: IssueScope,
    prScope: PullRequestScope,
    assignToSelf: boolean,
  ) => {
    await invoke("upsert_visibility_preferences", {
      input: {
        scopeType: "global",
        scopeId: GLOBAL_SYNC_ID,
        issueScope,
        prScope,
        assignIssuesToSelf: assignToSelf,
      },
    });
  };

  function SyncRow({
    label,
    description,
    enabled,
    intervalSecs,
    intervalKind,
  }: {
    label: string;
    description: string;
    enabled: boolean;
    intervalSecs: number;
    intervalKind: keyof typeof INTERVAL_OPTIONS;
  }) {
    return (
      <SettingsItem
        label={label}
        description={description}
        action={
          <div className="flex items-center gap-3">
            {enabled && (
              <Select
                value={String(intervalSecs)}
                onValueChange={(v) => {
                  const key = `sync${intervalKind.charAt(0).toUpperCase() + intervalKind.slice(1)}IntervalSecs` as keyof SyncSettingsDto;
                  handleSave({ [key]: Number(v) } as Partial<SyncSettingsDto>);
                }}
              >
                <SelectTrigger className="w-32 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {INTERVAL_OPTIONS[intervalKind].map((opt) => (
                    <SelectItem key={opt.value} value={String(opt.value)}>
                      {opt.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            )}
            <Switch
              checked={enabled}
              onCheckedChange={(v) => {
                const key = `sync${intervalKind.charAt(0).toUpperCase() + intervalKind.slice(1)}Enabled` as keyof SyncSettingsDto;
                handleSave({ [key]: v } as Partial<SyncSettingsDto>);
              }}
            />
          </div>
        }
      />
    );
  }

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection
        title={t("settings.sync.title")}
        description={t("settings.sync.description")}
        icon={RefreshCw}
      >
        <SyncRow
          label={t("settings.sync.issues.label")}
          description={t("settings.sync.issues.description")}
          enabled={global.syncIssuesEnabled}
          intervalSecs={global.syncIssuesIntervalSecs}
          intervalKind="issues"
        />
        <SyncRow
          label={t("settings.sync.prs.label")}
          description={t("settings.sync.prs.description")}
          enabled={global.syncPrsEnabled}
          intervalSecs={global.syncPrsIntervalSecs}
          intervalKind="prs"
        />
        <SyncRow
          label={t("settings.sync.repos.label")}
          description={t("settings.sync.repos.description")}
          enabled={global.syncReposEnabled}
          intervalSecs={global.syncReposIntervalSecs}
          intervalKind="repos"
        />
        <SyncRow
          label={t("settings.sync.orgs.label")}
          description={t("settings.sync.orgs.description")}
          enabled={global.syncOrgsEnabled}
          intervalSecs={global.syncOrgsIntervalSecs}
          intervalKind="orgs"
        />
      </SettingsSection>

      <SettingsSection
        title={t("pages.organization.visibility.title")}
        description={t("settings.sync.visibility.description")}
        icon={RefreshCw}
      >
        <SettingsItem
          label={t("pages.organization.visibility.issues")}
          action={
            <Select value={defaultIssueScope} onValueChange={async (value) => {
              const next = value as IssueScope;
              setDefaultIssueScope(next);
              await persistVisibility(next, defaultPrScope, assignIssuesToSelfByDefault);
            }}>
              <SelectTrigger className="w-40 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="my_queue">{t(issueScopeLabelKey("my_queue"))}</SelectItem>
                <SelectItem value="all_open">{t(issueScopeLabelKey("all_open"))}</SelectItem>
                <SelectItem value="all">{t(issueScopeLabelKey("all"))}</SelectItem>
              </SelectContent>
            </Select>
          }
        />
        <SettingsItem
          label={t("pages.organization.visibility.prs")}
          action={
            <Select value={defaultPrScope} onValueChange={async (value) => {
              const next = value as PullRequestScope;
              setDefaultPrScope(next);
              await persistVisibility(defaultIssueScope, next, assignIssuesToSelfByDefault);
            }}>
              <SelectTrigger className="w-48 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="mine_or_review_requested">{t(prScopeLabelKey("mine_or_review_requested"))}</SelectItem>
                <SelectItem value="all_open">{t(prScopeLabelKey("all_open"))}</SelectItem>
              </SelectContent>
            </Select>
          }
        />
        <SettingsItem
          label={t("settings.behaviour.assignIssueToSelf.label")}
          description={t("settings.behaviour.assignIssueToSelf.description")}
          action={<Switch checked={assignIssuesToSelfByDefault} onCheckedChange={async (checked) => {
            setAssignIssuesToSelfByDefault(checked);
            await persistVisibility(defaultIssueScope, defaultPrScope, checked);
          }} />}
        />
      </SettingsSection>
    </div>
  );
}
