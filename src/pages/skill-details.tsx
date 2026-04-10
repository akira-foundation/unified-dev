import { useEffect } from "react";
import { Info, Download, Trash2, Loader2, Settings2 } from "lucide-react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { invoke } from "@tauri-apps/api/core";
import { PageLayout } from "@/components/layout/page-layout";
import { PageHeader, PageHeaderTitle } from "@/components/layout/page-header";
import { Switch } from "@/components/ui/switch";
import { useAgentsStore, type InstalledSkill } from "@/stores/useAgentsStore";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { convertFileSrc } from "@tauri-apps/api/core";
import { skillColor } from "@/lib/skill-color";
import { queryKeys } from "@/lib/query-keys";
import { SettingsSection } from "@/components/settings/settings-section";
import { SettingsItem } from "@/components/settings/settings-item";

export function SkillDetailsPage() {
  const { t } = useI18n();
  const { selectedSkill, setActiveTab, setSelectedSkill } = useAgentsStore();
  const queryClient = useQueryClient();

  const isRemote = !!selectedSkill?.repo_url && !selectedSkill?.source_path;
  const isInstalled = !!selectedSkill?.source_path;

  const installMutation = useMutation({
    mutationFn: ({ skillId, repoUrl }: { skillId: string; repoUrl: string }) =>
      invoke<InstalledSkill>("install_skill", { skillId, repoUrl }),
    onSuccess: (installed) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.skills() });
      queryClient.invalidateQueries({ queryKey: queryKeys.recommendedSkills() });
      setSelectedSkill(installed);
    },
  });

  const toggleMutation = useMutation({
    mutationFn: ({ id, enabled }: { id: string; enabled: boolean }) =>
      invoke("set_skill_enabled", { id, enabled }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.skills() });
    },
  });

  const uninstallMutation = useMutation({
    mutationFn: (id: string) => invoke("uninstall_skill", { id }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.skills() });
      setActiveTab("skills");
    },
  });

  useEffect(() => {
    if (!selectedSkill) {
      setActiveTab("skills");
    }
  }, [selectedSkill, setActiveTab]);

  if (!selectedSkill) {
    return null;
  }

  const displayName: string = selectedSkill.name ?? selectedSkill.title ?? selectedSkill.id;
  const displayDescription: string = selectedSkill.description ?? "";
  const sourcePath: string | null = selectedSkill.source_path ?? null;
  const iconPath: string | null = selectedSkill.icon_path ?? null;
  const colorKey: string = selectedSkill.uid ?? selectedSkill.id ?? displayName;
  const colorClass: string = skillColor(colorKey);

  return (
    <PageLayout scroll>
      <PageHeader className="mx-auto w-full max-w-3xl px-6">
        <div className="flex flex-col gap-4">
          <div className="flex items-center gap-4">
            <div className={cn(
              "relative flex h-12 w-12 shrink-0 items-center justify-center rounded-md dark:bg-white/5 bg-black/5 dark:border-white/5 border-border border font-bold shadow-sm overflow-hidden",
              colorClass,
            )}>
              {iconPath ? (
                <img src={convertFileSrc(iconPath)} alt="skill icon" className="h-full w-full object-cover" />
              ) : (
                <div className="h-4 w-4 rounded-full bg-current opacity-80" />
              )}
            </div>
            <div>
              <PageHeaderTitle className="text-3xl">{displayName}</PageHeaderTitle>
            </div>
          </div>
        </div>
      </PageHeader>

      <div className="mx-auto w-full max-w-3xl px-6 pb-24 flex flex-col">
        <SettingsSection
          title={t("pages.skillDetails.general.title")}
          description={t("pages.skillDetails.general.description")}
          icon={Info}
        >
          {displayDescription ? (
            <SettingsItem
              label={t("pages.skillDetails.description")}
              description={displayDescription}
            />
          ) : null}
          {sourcePath ? (
            <SettingsItem
              label={t("pages.skillDetails.location")}
              description={sourcePath}
            />
          ) : null}
        </SettingsSection>

        {isRemote && (
          <SettingsSection
            title="Install"
            description="Add this skill to your Unified Dev."
            icon={Download}
          >
            <SettingsItem
              label={t("common.install")}
              description="Download and install this skill from its source repository."
              action={
                <button
                  disabled={installMutation.isPending}
                  onClick={() => installMutation.mutate({ skillId: selectedSkill.id, repoUrl: selectedSkill.repo_url })}
                  className="flex items-center gap-1.5 px-3 h-8 rounded-md bg-purple-600 hover:bg-purple-500 disabled:opacity-50 disabled:cursor-not-allowed text-white text-xs font-semibold transition-colors"
                >
                  {installMutation.isPending ? (
                    <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  ) : (
                    <Download className="h-3.5 w-3.5" />
                  )}
                  {installMutation.isPending ? t("common.installing") : t("common.install")}
                </button>
              }
            />
          </SettingsSection>
        )}

        {isInstalled && (
          <SettingsSection
            title="Manage"
            description="Enable, disable or remove this skill."
            icon={Settings2}
          >
            <SettingsItem
              label="Enabled"
              description="When disabled, this skill will not be available to the agent."
              action={
                <Switch
                  checked={selectedSkill.enabled}
                  onCheckedChange={(checked) =>
                    toggleMutation.mutate({ id: selectedSkill.id, enabled: checked })
                  }
                  className="data-[state=checked]:bg-purple-500"
                />
              }
            />
            {selectedSkill.scope !== "project" && selectedSkill.scope !== "local" && (
              <SettingsItem
                label={t("common.uninstall")}
                description="Remove this skill from all skill directories."
                action={
                  <button
                    disabled={uninstallMutation.isPending}
                    onClick={() => uninstallMutation.mutate(selectedSkill.id)}
                    className="flex items-center gap-1.5 px-3 h-8 rounded-md text-red-400 hover:text-red-300 hover:bg-red-500/10 disabled:opacity-50 disabled:cursor-not-allowed transition-all text-xs font-semibold"
                  >
                    {uninstallMutation.isPending ? (
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    ) : (
                      <Trash2 className="h-3.5 w-3.5" />
                    )}
                    {t("common.uninstall")}
                  </button>
                }
              />
            )}
          </SettingsSection>
        )}
      </div>
    </PageLayout>
  );
}
