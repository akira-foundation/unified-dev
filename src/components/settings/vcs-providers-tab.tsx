import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { Github, GitlabIcon, Blocks, Link2, Plus, RefreshCw } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { useI18n } from "@/i18n/i18n";
import { useProviders } from "@/hooks/useProviders";
import { useNavigation } from "@/hooks/useNavigation";
import type { ProviderKind, RateLimitDto } from "@/types/provider";
import { AddProviderDialog } from "@/components/providers/add-provider-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";
import { queryKeys } from "@/lib/query-keys";
import { cache } from "@/config/cache";

const VCS_PROVIDERS = [
  { kind: "github" as ProviderKind, title: "GitHub", descKey: "settings.vcsProviders.github.description", icon: Github },
  { kind: "gitlab" as ProviderKind, title: "GitLab", descKey: "settings.vcsProviders.gitlab.description", icon: GitlabIcon },
  { kind: "bitbucket" as ProviderKind, title: "Bitbucket", descKey: "settings.vcsProviders.bitbucket.description", icon: Blocks },
] as const;

function resetTime(unix: number): string {
  return new Date(unix * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function RateLimitRow({
  data,
  loading,
  onRefresh,
}: {
  data: RateLimitDto | undefined;
  loading: boolean;
  onRefresh: () => void;
}) {
  if (loading) {
    return (
      <div className="flex items-center gap-3 px-4 py-3 border-t border-zinc-100 dark:border-zinc-800/50">
        <Skeleton className="h-4 w-24 rounded" />
        <Skeleton className="h-4 w-32 rounded" />
        <Skeleton className="h-4 w-20 rounded" />
      </div>
    );
  }

  if (!data) return null;

  const resources = [
    { label: "Core", r: data.core },
    { label: "Search", r: data.search },
    { label: "GraphQL", r: data.graphql },
  ];

  return (
    <div className="flex items-center gap-4 px-4 py-3 border-t border-zinc-100 dark:border-zinc-800/50 flex-wrap">
      <span className="text-xs font-medium text-zinc-400 dark:text-zinc-500 uppercase tracking-wide shrink-0">
        Rate limit
      </span>
      {resources.map(({ label, r }) => {
        const pct = r.limit > 0 ? Math.round((r.remaining / r.limit) * 100) : 0;
        const color =
          pct > 50
            ? "text-emerald-600 dark:text-emerald-400 border-emerald-500/20 bg-emerald-500/10"
            : pct > 15
              ? "text-amber-600 dark:text-amber-400 border-amber-500/20 bg-amber-500/10"
              : "text-red-600 dark:text-red-400 border-red-500/20 bg-red-500/10";

        return (
          <div key={label} className="flex items-center gap-1.5">
            <span className="text-xs text-zinc-500 dark:text-zinc-400">{label}</span>
            <Badge variant="secondary" className={`text-xs tabular-nums ${color}`}>
              {r.remaining.toLocaleString()}/{r.limit.toLocaleString()}
            </Badge>
          </div>
        );
      })}
      <span className="text-xs text-zinc-400 dark:text-zinc-500 shrink-0">
        resets {resetTime(data.core.reset)}
      </span>
      <button
        onClick={onRefresh}
        className="ml-auto text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 transition-colors"
        title="Refresh rate limit"
      >
        <RefreshCw className="h-3.5 w-3.5" />
      </button>
    </div>
  );
}

export function VcsProvidersTab() {
  const { t } = useI18n();
  const { providers, createProvider, connectGithub } = useProviders();
  const { navigateTo, setActiveProviderId } = useNavigation("settings");
  const [isDialogOpen, setIsDialogOpen] = useState(false);

  const connectedKinds = new Set(providers.map((p) => p.kind));

  const { data: rateLimits, isFetching: rateLimitsLoading, refetch: refetchRateLimits } = useQuery({
    queryKey: queryKeys.rateLimits(),
    queryFn: () => invoke<RateLimitDto[]>("get_rate_limit"),
    enabled: false,
    staleTime: cache.staleTime.short,
    gcTime: cache.gcTime.default,
  });

  return (
    <div className="animate-in fade-in duration-300">
      <div className="flex justify-end mb-4">
        <Button onClick={() => setIsDialogOpen(true)}>
          <Plus size={18} /> {t("settings.vcsProviders.addManual")}
        </Button>
      </div>

      {VCS_PROVIDERS.map(({ kind, title, descKey, icon }) => {
        const connectedProvider = providers.find((p) => p.kind === kind);
        const rateLimitData = rateLimits?.find((r) => r.provider_id === connectedProvider?.id);

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
            {kind === "github" && connectedProvider && (
              <RateLimitRow
                data={rateLimitData}
                loading={rateLimitsLoading}
                onRefresh={refetchRateLimits}
              />
            )}
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
