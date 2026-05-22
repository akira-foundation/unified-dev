import { useEffect } from "react";
import { Info, Download, Trash2, Loader2, Settings2 } from "lucide-react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { invoke } from "@tauri-apps/api/core";
import { PageLayout } from "@/components/layout/page-layout";
import { Switch } from "@/components/ui/switch";
import { useAgentsStore, type InstalledSkill } from "@/stores/useAgentsStore";
import { useI18n } from "@/i18n/i18n";
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

  const displayDescription: string = selectedSkill.description ?? "";
  const sourcePath: string | null = selectedSkill.source_path ?? null;

  return (
    <PageLayout scroll>
      <div className="mx-auto flex w-full max-w-3xl flex-col px-6 pb-24 pt-2">
        <SettingsSection
          title={t("pages.skillDetails.general.title")}
          description={t("pages.skillDetails.general.description")}
          icon={Info}
        >
          <SettingsItem
            label={t("pages.skillDetails.description")}
            description={displayDescription || t("pages.skillDetails.noDescription")}
          />
          {sourcePath && (
            <SettingsItem label={t("pages.skillDetails.location")} description={sourcePath} />
          )}
        </SettingsSection>

        {isRemote && (
          <SettingsSection title="Install" description="Add this skill to your Unified Dev." icon={Download}>
            <SettingsItem
              label={t("common.install")}
              description="Download and install this skill from its source repository."
              action={
                <button
                  disabled={installMutation.isPending}
                  onClick={() => installMutation.mutate({ skillId: selectedSkill.id, repoUrl: selectedSkill.repo_url })}
                  className="flex h-8 items-center gap-1.5 rounded-md bg-purple-600 px-3 text-xs font-semibold text-white transition-colors hover:bg-purple-500 disabled:cursor-not-allowed disabled:opacity-50"
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
          <SettingsSection title="Manage" description="Enable, disable or remove this skill." icon={Settings2}>
            <SettingsItem
              label="Enabled"
              description="When disabled, this skill will not be available to the agent."
              action={
                <Switch
                  checked={selectedSkill.enabled}
                  onCheckedChange={(checked) => toggleMutation.mutate({ id: selectedSkill.id, enabled: checked })}
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
                    className="flex h-8 items-center gap-1.5 rounded-md px-3 text-xs font-semibold text-red-400 transition-all hover:bg-red-500/10 hover:text-red-300 disabled:cursor-not-allowed disabled:opacity-50"
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
