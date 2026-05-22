import { useEffect, useState } from "react";
import { Eye, RefreshCw } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { useI18n } from "@/i18n/i18n";
import { issueScopeLabelKey, prScopeLabelKey } from "@/lib/work-visibility";
import { useSettingsStore } from "@/stores/settings-store";
import { useSyncSettingsStore, GLOBAL_SYNC_ID, INTERVAL_OPTIONS } from "@/stores/sync-settings-store";
import type { SyncSettingsDto } from "@/stores/sync-settings-store";
import type { OrganizationSummary } from "@/types/organization";
import type { IssueScope, PullRequestScope } from "@/types/work-visibility";

interface OrgSyncSheetProps {
  organization: OrganizationSummary | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

function effective(settings: SyncSettingsDto | null, id: string): SyncSettingsDto {
  return settings ?? {
    id,
    scope: "organization",
    syncIssuesEnabled: true,
    syncIssuesIntervalSecs: 900,
    syncPrsEnabled: true,
    syncPrsIntervalSecs: 300,
    syncReposEnabled: true,
    syncReposIntervalSecs: 1800,
    syncOrgsEnabled: true,
    syncOrgsIntervalSecs: 7200,
  };
}

export function OrgSyncSheet({ organization, open, onOpenChange }: OrgSyncSheetProps) {
  const { t } = useI18n();
  const { loadSettings, saveSettings, resetSettings, globalSettings, orgSettings } =
    useSyncSettingsStore();
  const { organizationIssueScopes, organizationPrScopes, setOrganizationIssueScope, setOrganizationPrScope } = useSettingsStore();

  const [draft, setDraft] = useState<SyncSettingsDto | null>(null);

  useEffect(() => {
    if (!open || !organization) return;
    loadSettings(organization.id).then((s) => setDraft(s));
  }, [open, organization?.id]);

  if (!organization) return null;

  const orgId = organization.id;
  const hasOverride = !!orgSettings[orgId];
  const current = draft ?? effective(orgSettings[orgId] ?? null, orgId);

  const patch = (key: keyof SyncSettingsDto, value: boolean | number) => {
    setDraft((prev) => ({ ...effective(prev, orgId), [key]: value }));
    saveSettings({
      id: orgId,
      syncIssuesEnabled: current.syncIssuesEnabled,
      syncIssuesIntervalSecs: current.syncIssuesIntervalSecs,
      syncPrsEnabled: current.syncPrsEnabled,
      syncPrsIntervalSecs: current.syncPrsIntervalSecs,
      syncReposEnabled: current.syncReposEnabled,
      syncReposIntervalSecs: current.syncReposIntervalSecs,
      syncOrgsEnabled: current.syncOrgsEnabled,
      syncOrgsIntervalSecs: current.syncOrgsIntervalSecs,
      [key]: value,
    });
  };

  const handleReset = () => {
    resetSettings(orgId).then(async (defaults) => {
      setDraft(defaults);
      setOrganizationIssueScope(orgId, null);
      setOrganizationPrScope(orgId, null);
      await invoke("reset_visibility_preferences", {
        scopeType: "organization",
        scopeId: orgId,
      });
    });
  };

  const ROWS = [
    {
      label: t("settings.sync.issues.label"),
      description: t("settings.sync.org.issues.description"),
      enabledKey: "syncIssuesEnabled" as const,
      intervalKey: "syncIssuesIntervalSecs" as const,
      intervalKind: "issues" as const,
    },
    {
      label: t("settings.sync.prs.label"),
      description: t("settings.sync.org.prs.description"),
      enabledKey: "syncPrsEnabled" as const,
      intervalKey: "syncPrsIntervalSecs" as const,
      intervalKind: "prs" as const,
    },
    {
      label: t("settings.sync.repos.label"),
      description: t("settings.sync.org.repos.description"),
      enabledKey: "syncReposEnabled" as const,
      intervalKey: "syncReposIntervalSecs" as const,
      intervalKind: "repos" as const,
    },
    {
      label: t("settings.sync.orgs.label"),
      description: t("settings.sync.org.orgs.description"),
      enabledKey: "syncOrgsEnabled" as const,
      intervalKey: "syncOrgsIntervalSecs" as const,
      intervalKind: "orgs" as const,
    },
  ] as const;

  const globalFallback = effective(globalSettings, GLOBAL_SYNC_ID);

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side="right"
        className="flex flex-col p-0 overflow-hidden transition-all duration-200 w-full sm:max-w-lg"
      >
        {/* Header */}
        <SheetHeader className="px-5 pt-5 pb-4 border-b border-zinc-100 dark:border-zinc-800 shrink-0">
          <div className="flex items-start gap-3 pr-6">
            <div className="mt-1 shrink-0">
              <div className="h-2.5 w-2.5 rounded-full bg-purple-500" />
            </div>
            <div className="min-w-0 flex-1">
              <SheetTitle className="text-base leading-snug text-left">
                {organization.name}
              </SheetTitle>
              <SheetDescription className="text-xs mt-0.5">
                {t("settings.sync.title")}
              </SheetDescription>
            </div>
          </div>
        </SheetHeader>

        {/* Scrollable body */}
        <div className="flex-1 overflow-y-auto">
          <section className="border-b border-zinc-100 px-4 py-4 dark:border-zinc-800/60">
            <div className="mb-1.5 flex items-center gap-2">
              <RefreshCw className="h-3.5 w-3.5 text-purple-500" />
              <span className="text-[12px] font-semibold uppercase tracking-wider text-zinc-500">{t("settings.sync.title")}</span>
            </div>
            <div className="flex flex-col">
              {ROWS.map(({ label, description, enabledKey, intervalKey, intervalKind }) => {
                const enabled = current[enabledKey];
                const intervalSecs = current[intervalKey];
                const isDefault = enabled === globalFallback[enabledKey] && intervalSecs === globalFallback[intervalKey];
                return (
                  <div key={enabledKey} className="flex items-center justify-between gap-4 py-2">
                    <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                      <div className="flex items-center gap-2">
                        <span className="text-[13px] font-medium text-zinc-800 dark:text-zinc-100">{label}</span>
                        {!isDefault && (
                          <span className="shrink-0 rounded bg-purple-500/10 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-purple-500">
                            {t("settings.sync.overrides.activeBadge")}
                          </span>
                        )}
                      </div>
                      <p className="text-[11px] text-zinc-500 dark:text-zinc-400">{description}</p>
                    </div>
                    <div className="flex shrink-0 items-center gap-2.5">
                      {enabled && (
                        <Select value={String(intervalSecs)} onValueChange={(v) => patch(intervalKey, Number(v))}>
                          <SelectTrigger className="h-8 w-28 text-xs">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            {INTERVAL_OPTIONS[intervalKind].map((opt) => (
                              <SelectItem key={opt.value} value={String(opt.value)}>{opt.label}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      )}
                      <Switch checked={enabled} onCheckedChange={(v) => patch(enabledKey, v)} />
                    </div>
                  </div>
                );
              })}
            </div>
          </section>

          <section className="px-4 py-4">
            <div className="mb-1.5 flex items-center gap-2">
              <Eye className="h-3.5 w-3.5 text-purple-500" />
              <span className="text-[12px] font-semibold uppercase tracking-wider text-zinc-500">{t("pages.organization.visibility.title")}</span>
            </div>
            <div className="flex flex-col">
              <div className="flex items-center justify-between gap-4 py-2">
                <span className="text-[13px] font-medium text-zinc-800 dark:text-zinc-100">{t("pages.organization.visibility.issues")}</span>
                <Select
                  value={organizationIssueScopes[orgId] ?? "default"}
                  onValueChange={async (value) => {
                    const next = value === "default" ? null : value as IssueScope;
                    setOrganizationIssueScope(orgId, next);
                    await invoke("upsert_visibility_preferences", {
                      input: {
                        scopeType: "organization",
                        scopeId: orgId,
                        issueScope: next ?? "my_queue",
                        prScope: organizationPrScopes[orgId] ?? "mine_or_review_requested",
                        assignIssuesToSelf: true,
                      },
                    });
                  }}
                >
                  <SelectTrigger className="h-8 w-40 text-xs">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="default">{t("visibility.useGlobalDefault")}</SelectItem>
                    <SelectItem value="my_queue">{t(issueScopeLabelKey("my_queue"))}</SelectItem>
                    <SelectItem value="all_open">{t(issueScopeLabelKey("all_open"))}</SelectItem>
                    <SelectItem value="all">{t(issueScopeLabelKey("all"))}</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="flex items-center justify-between gap-4 py-2">
                <span className="text-[13px] font-medium text-zinc-800 dark:text-zinc-100">{t("pages.organization.visibility.prs")}</span>
                <Select
                  value={organizationPrScopes[orgId] ?? "default"}
                  onValueChange={async (value) => {
                    const next = value === "default" ? null : value as PullRequestScope;
                    setOrganizationPrScope(orgId, next);
                    await invoke("upsert_visibility_preferences", {
                      input: {
                        scopeType: "organization",
                        scopeId: orgId,
                        issueScope: organizationIssueScopes[orgId] ?? "my_queue",
                        prScope: next ?? "mine_or_review_requested",
                        assignIssuesToSelf: true,
                      },
                    });
                  }}
                >
                  <SelectTrigger className="h-8 w-44 text-xs">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="default">{t("visibility.useGlobalDefault")}</SelectItem>
                    <SelectItem value="mine_or_review_requested">{t(prScopeLabelKey("mine_or_review_requested"))}</SelectItem>
                    <SelectItem value="all_open">{t(prScopeLabelKey("all_open"))}</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
          </section>
        </div>

        {/* Footer */}
        <div className="px-5 py-3 border-t border-zinc-100 dark:border-zinc-800 shrink-0 flex flex-col gap-2">
          <p className="text-[11px] text-zinc-400 dark:text-zinc-500">
            {t("settings.sync.org.sheetFootnote")}
          </p>
          {hasOverride && (
            <Button
              variant="outline"
              className="w-full cursor-pointer"
              onClick={handleReset}
            >
              <RefreshCw className="h-4 w-4 mr-1.5" />
              {t("settings.sync.overrides.reset")}
            </Button>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}
