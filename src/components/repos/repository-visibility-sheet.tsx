import { useEffect, useState } from "react";
import { Eye, RefreshCw } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";

import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Card, CardContent, CardTitle } from "@/components/ui/card";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { useI18n } from "@/i18n/i18n";
import { issueScopeLabelKey, prScopeLabelKey } from "@/lib/work-visibility";
import { useSettingsStore } from "@/stores/settings-store";
import { INTERVAL_OPTIONS, type SyncSettingsDto } from "@/stores/sync-settings-store";
import type { OrganizationRepoWithOrg } from "@/types/organization";
import type { IssueScope, PullRequestScope } from "@/types/work-visibility";

interface RepositoryVisibilitySheetProps {
  repo: OrganizationRepoWithOrg | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function RepositoryVisibilitySheet({ repo, open, onOpenChange }: RepositoryVisibilitySheetProps) {
  const { t } = useI18n();
  const {
    resolveIssueScope,
    resolvePrScope,
    assignIssuesToSelfByDefault,
    setRepositoryIssueScope,
    setRepositoryPrScope,
  } = useSettingsStore();
  const [syncSettings, setSyncSettings] = useState<SyncSettingsDto | null>(null);

  const repoOrgId = repo?.organization_id ?? "";
  const repoName = repo?.repo_name ?? "";
  const issueScope = repo ? resolveIssueScope(repoOrgId, repoName) : "my_queue";
  const prScope = repo ? resolvePrScope(repoOrgId, repoName) : "mine_or_review_requested";
  const repoSyncId = repo ? `${repoOrgId}:${repoName}` : "";

  useEffect(() => {
    if (!open || !repo) return;
    void invoke<SyncSettingsDto>("get_sync_settings", { id: repoSyncId }).then(setSyncSettings);
  }, [open, repo, repoSyncId]);

  if (!repo) return null;

  const currentSyncSettings = syncSettings ?? {
    id: repoSyncId,
    scope: "repository",
    syncIssuesEnabled: true,
    syncIssuesIntervalSecs: 900,
    syncPrsEnabled: true,
    syncPrsIntervalSecs: 300,
    syncReposEnabled: true,
    syncReposIntervalSecs: 1800,
    syncOrgsEnabled: false,
    syncOrgsIntervalSecs: 7200,
  };

  const patchSync = async (patch: Partial<SyncSettingsDto>) => {
    const next = { ...currentSyncSettings, ...patch };
    const saved = await invoke<SyncSettingsDto>("upsert_sync_settings", {
      input: {
        id: repoSyncId,
        syncIssuesEnabled: next.syncIssuesEnabled,
        syncIssuesIntervalSecs: next.syncIssuesIntervalSecs,
        syncPrsEnabled: next.syncPrsEnabled,
        syncPrsIntervalSecs: next.syncPrsIntervalSecs,
        syncReposEnabled: next.syncReposEnabled,
        syncReposIntervalSecs: next.syncReposIntervalSecs,
        syncOrgsEnabled: false,
        syncOrgsIntervalSecs: next.syncOrgsIntervalSecs,
      },
    });
    setSyncSettings(saved);
  };

  const resetSync = async () => {
    const reset = await invoke<SyncSettingsDto>("reset_sync_settings", { id: repoSyncId });
    setSyncSettings(reset);
    setRepositoryIssueScope(repoOrgId, repoName, null);
    setRepositoryPrScope(repoOrgId, repoName, null);
    await invoke("reset_visibility_preferences", {
      scopeType: "repository",
      scopeId: repoSyncId,
    });
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side="right"
        className="flex flex-col p-0 overflow-hidden transition-all duration-200 w-full sm:max-w-lg"
      >
        <SheetHeader className="px-5 pt-5 pb-4 border-b border-zinc-100 dark:border-zinc-800 shrink-0">
          <div className="flex items-start gap-3 pr-6">
            <div className="mt-1 shrink-0">
              <div className="h-2.5 w-2.5 rounded-full bg-purple-500" />
            </div>
            <div className="min-w-0 flex-1">
              <SheetTitle className="text-base leading-snug text-left">{repoName}</SheetTitle>
              <SheetDescription className="text-xs mt-0.5">{t("settings.sync.title")}</SheetDescription>
            </div>
          </div>
        </SheetHeader>

        <div className="flex-1 overflow-y-auto">
          <div className="flex flex-col gap-3 p-2">
            <Collapsible defaultOpen>
              <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
                <CollapsibleTrigger className="w-full cursor-pointer">
                  <div className="flex flex-row items-center gap-3 px-4 py-3">
                    <div className="h-7 w-7 flex items-center justify-center rounded-lg bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
                      <RefreshCw size={14} strokeWidth={2} />
                    </div>
                    <CardTitle className="text-sm font-semibold text-zinc-900 dark:text-white/95 leading-none flex-1 text-left">
                      {t("settings.sync.title")}
                    </CardTitle>
                  </div>
                </CollapsibleTrigger>
                <CollapsibleContent>
                  <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
                  {[
                    ["issues", t("settings.sync.issues.label"), t("settings.sync.repo.issues.description"), currentSyncSettings.syncIssuesEnabled, currentSyncSettings.syncIssuesIntervalSecs],
                    ["prs", t("settings.sync.prs.label"), t("settings.sync.repo.prs.description"), currentSyncSettings.syncPrsEnabled, currentSyncSettings.syncPrsIntervalSecs],
                    ["repos", t("settings.sync.branches.label"), t("settings.sync.repo.branches.description"), currentSyncSettings.syncReposEnabled, currentSyncSettings.syncReposIntervalSecs],
                  ].map(([kind, label, description, enabled, intervalSecs]) => (
                    <div key={String(kind)} className="flex items-center justify-between px-4 py-3 gap-4">
                      <div className="flex flex-col gap-0.5 min-w-0 flex-1">
                        <span className="text-xs font-semibold text-zinc-900 dark:text-white">{label}</span>
                        <p className="text-[11px] text-zinc-500 dark:text-zinc-400 leading-relaxed">{description}</p>
                      </div>
                      <div className="flex items-center gap-3 shrink-0">
                        {enabled ? (
                          <Select
                            value={String(intervalSecs)}
                            onValueChange={(value) => {
                              const patch = kind === "issues"
                                ? { syncIssuesIntervalSecs: Number(value) }
                                : kind === "prs"
                                  ? { syncPrsIntervalSecs: Number(value) }
                                  : { syncReposIntervalSecs: Number(value) };
                              void patchSync(patch);
                            }}
                          >
                            <SelectTrigger className="w-28 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {INTERVAL_OPTIONS[kind as keyof typeof INTERVAL_OPTIONS].map((opt) => (
                                <SelectItem key={opt.value} value={String(opt.value)}>
                                  {opt.label}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        ) : null}
                        <Switch
                          checked={Boolean(enabled)}
                          onCheckedChange={(checked) => {
                            const patch = kind === "issues"
                              ? { syncIssuesEnabled: checked }
                              : kind === "prs"
                                ? { syncPrsEnabled: checked }
                                : { syncReposEnabled: checked };
                            void patchSync(patch);
                          }}
                        />
                      </div>
                    </div>
                  ))}
                  </CardContent>
                </CollapsibleContent>
              </Card>
            </Collapsible>

            <Collapsible defaultOpen>
              <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
                <CollapsibleTrigger className="w-full cursor-pointer">
                  <div className="flex flex-row items-center gap-3 px-4 py-3">
                    <div className="h-7 w-7 flex items-center justify-center rounded-lg bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
                      <Eye size={14} strokeWidth={2} />
                    </div>
                    <CardTitle className="text-sm font-semibold text-zinc-900 dark:text-white/95 leading-none flex-1 text-left">
                      {t("pages.organization.visibility.title")}
                    </CardTitle>
                  </div>
                </CollapsibleTrigger>
                <CollapsibleContent>
                  <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
                  <div className="flex items-center justify-between px-4 py-3 gap-4">
                    <div className="flex flex-col gap-0.5 min-w-0 flex-1">
                      <span className="text-xs font-semibold text-zinc-900 dark:text-white">{t("pages.organization.visibility.issues")}</span>
                    </div>
                    <Select value={issueScope} onValueChange={async (value) => {
                      const next = value as IssueScope;
                      setRepositoryIssueScope(repoOrgId, repoName, next);
                      await invoke("upsert_visibility_preferences", {
                        input: {
                          scopeType: "repository",
                          scopeId: `${repoOrgId}:${repoName}`,
                          issueScope: next,
                          prScope,
                          assignIssuesToSelf: assignIssuesToSelfByDefault,
                        },
                      });
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
                  </div>
                  <div className="flex items-center justify-between px-4 py-3 gap-4">
                    <div className="flex flex-col gap-0.5 min-w-0 flex-1">
                      <span className="text-xs font-semibold text-zinc-900 dark:text-white">{t("pages.organization.visibility.prs")}</span>
                    </div>
                    <Select value={prScope} onValueChange={async (value) => {
                      const next = value as PullRequestScope;
                      setRepositoryPrScope(repoOrgId, repoName, next);
                      await invoke("upsert_visibility_preferences", {
                        input: {
                          scopeType: "repository",
                          scopeId: `${repoOrgId}:${repoName}`,
                          issueScope,
                          prScope: next,
                          assignIssuesToSelf: assignIssuesToSelfByDefault,
                        },
                      });
                    }}>
                      <SelectTrigger className="w-44 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="mine_or_review_requested">{t(prScopeLabelKey("mine_or_review_requested"))}</SelectItem>
                        <SelectItem value="all_open">{t(prScopeLabelKey("all_open"))}</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  </CardContent>
                </CollapsibleContent>
              </Card>
            </Collapsible>
          </div>
        </div>

        <div className="px-5 py-3 border-t border-zinc-100 dark:border-zinc-800 shrink-0 flex flex-col gap-2">
          <p className="text-[11px] text-zinc-400 dark:text-zinc-500">
            {t("settings.sync.repo.sheetFootnote")}
          </p>
          <Button variant="outline" className="w-full cursor-pointer" onClick={resetSync}>
            <RefreshCw className="h-4 w-4 mr-1.5" />
            {t("settings.sync.overrides.reset")}
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}
