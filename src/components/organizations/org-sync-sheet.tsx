import { useEffect, useState } from "react";
import { ChevronDown, RefreshCw } from "lucide-react";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import { Card, CardContent, CardTitle } from "@/components/ui/card";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { useI18n } from "@/i18n/i18n";
import { useSyncSettingsStore, GLOBAL_SYNC_ID, INTERVAL_OPTIONS } from "@/stores/sync-settings-store";
import type { SyncSettingsDto } from "@/stores/sync-settings-store";
import type { OrganizationSummary } from "@/types/organization";

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
    resetSettings(orgId).then((defaults) => setDraft(defaults));
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
                    <ChevronDown className="h-3.5 w-3.5 text-zinc-400 transition-transform duration-200 [[data-state=open]_&]:rotate-180" />
                  </div>
                </CollapsibleTrigger>
                <CollapsibleContent>
                  <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
                    {ROWS.map(({ label, description, enabledKey, intervalKey, intervalKind }) => {
                      const enabled = current[enabledKey];
                      const intervalSecs = current[intervalKey];
                      const globalEnabled = globalFallback[enabledKey];
                      const globalInterval = globalFallback[intervalKey];
                      const isDefault =
                        enabled === globalEnabled && intervalSecs === globalInterval;

                      return (
                        <div key={enabledKey} className="flex items-center justify-between px-4 py-3 gap-4">
                          <div className="flex flex-col gap-0.5 min-w-0 flex-1">
                            <div className="flex items-center gap-2">
                              <span className="text-xs font-semibold text-zinc-900 dark:text-white">
                                {label}
                              </span>
                              {!isDefault && (
                                <span className="shrink-0 text-[9px] font-bold uppercase tracking-wider px-1.5 py-0.5 rounded bg-purple-500/10 text-purple-400 border border-purple-500/20">
                                  {t("settings.sync.overrides.activeBadge")}
                                </span>
                              )}
                            </div>
                            <p className="text-[11px] text-zinc-500 dark:text-zinc-400 leading-relaxed">
                              {description}
                            </p>
                          </div>
                          <div className="flex items-center gap-3 shrink-0">
                            {enabled && (
                              <Select
                                value={String(intervalSecs)}
                                onValueChange={(v) => patch(intervalKey, Number(v))}
                              >
                                <SelectTrigger className="w-28 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
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
                              onCheckedChange={(v) => patch(enabledKey, v)}
                            />
                          </div>
                        </div>
                      );
                    })}
                  </CardContent>
                </CollapsibleContent>
              </Card>
            </Collapsible>
          </div>
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
