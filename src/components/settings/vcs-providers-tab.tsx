import { useState } from "react";
import { Github, GitlabIcon, Blocks, Link2, Plus } from "lucide-react";
import { useI18n } from "@/i18n/i18n";
import { useProviders } from "@/hooks/useProviders";
import { useNavigation } from "@/hooks/useNavigation";
import type { ProviderKind } from "@/types/provider";
import { AddProviderDialog } from "@/components/providers/add-provider-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";

const VCS_PROVIDERS = [
  { kind: "github" as ProviderKind, title: "GitHub", descKey: "settings.vcsProviders.github.description", icon: Github },
  { kind: "gitlab" as ProviderKind, title: "GitLab", descKey: "settings.vcsProviders.gitlab.description", icon: GitlabIcon },
  { kind: "bitbucket" as ProviderKind, title: "Bitbucket", descKey: "settings.vcsProviders.bitbucket.description", icon: Blocks },
] as const;

export function VcsProvidersTab() {
  const { t } = useI18n();
  const { providers, createProvider, connectGithub } = useProviders();
  const { navigateTo, setActiveProviderId } = useNavigation("settings");
  const [isDialogOpen, setIsDialogOpen] = useState(false);

  const connectedKinds = new Set(providers.map((p) => p.kind));

  return (
    <div className="animate-in fade-in duration-300">
      <div className="flex justify-end mb-4">
        <Button onClick={() => setIsDialogOpen(true)}>
          <Plus size={18} /> {t("settings.vcsProviders.addManual")}
        </Button>
      </div>

      {VCS_PROVIDERS.map(({ kind, title, descKey, icon }) => {
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
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => {
                        if (connectedProvider) {
                          setActiveProviderId(connectedProvider.id);
                          navigateTo("provider-detail");
                        }
                      }}
                    >
                      {t("common.manage")}
                    </Button>
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
        open={isDialogOpen}
        onOpenChange={setIsDialogOpen}
        onSubmit={createProvider}
      />
    </div>
  );
}
