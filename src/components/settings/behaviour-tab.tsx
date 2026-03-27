import { SlidersHorizontal } from "lucide-react";
import { useI18n } from "@/i18n/i18n";
import { useSettingsStore } from "@/stores/settings-store";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { issueScopeLabelKey, prScopeLabelKey } from "@/lib/work-visibility";
import type { IssueScope, PullRequestScope } from "@/types/work-visibility";
import { invoke } from "@tauri-apps/api/core";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";

export function BehaviourTab() {
  const { t } = useI18n();
  const {
    defaultIssueScope,
    defaultPrScope,
    assignIssuesToSelfByDefault,
    setDefaultIssueScope,
    setDefaultPrScope,
    setAssignIssuesToSelfByDefault,
  } = useSettingsStore();

  const persistGlobalVisibilityPreferences = async (
    issueScope: IssueScope,
    prScope: PullRequestScope,
    assignToSelf: boolean,
  ) => {
    await invoke("upsert_visibility_preferences", {
      input: {
        scopeType: "global",
        scopeId: "global",
        issueScope,
        prScope,
        assignIssuesToSelf: assignToSelf,
      },
    });
  };

  return (
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
        <SettingsItem
          label={t("settings.behaviour.issueScope.label")}
          description={t("settings.behaviour.issueScope.description")}
          action={
            <Select value={defaultIssueScope} onValueChange={async (value) => {
              const next = value as IssueScope;
              setDefaultIssueScope(next);
              await persistGlobalVisibilityPreferences(next, defaultPrScope, assignIssuesToSelfByDefault);
            }}>
              <SelectTrigger className="w-44 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
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
          label={t("settings.behaviour.prScope.label")}
          description={t("settings.behaviour.prScope.description")}
          action={
            <Select value={defaultPrScope} onValueChange={async (value) => {
              const next = value as PullRequestScope;
              setDefaultPrScope(next);
              await persistGlobalVisibilityPreferences(defaultIssueScope, next, assignIssuesToSelfByDefault);
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
          action={
            <Switch
              checked={assignIssuesToSelfByDefault}
              onCheckedChange={async (checked) => {
                setAssignIssuesToSelfByDefault(checked);
                await persistGlobalVisibilityPreferences(defaultIssueScope, defaultPrScope, checked);
              }}
            />
          }
        />
      </SettingsSection>
    </div>
  );
}
