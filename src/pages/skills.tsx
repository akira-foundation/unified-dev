import { useState } from "react";
import { Search, Trash2, FolderOpen, Globe, ChevronRight } from "lucide-react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { PageLayout } from "@/components/layout/page-layout";
import { PageHeader, PageHeaderMeta, PageHeaderTitle, PageHeaderActions } from "@/components/layout/page-header";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { useAgentsStore, type InstalledSkill } from "@/stores/useAgentsStore";
import { useI18n } from "@/i18n/i18n";
import { invoke } from "@tauri-apps/api/core";
import { convertFileSrc } from "@tauri-apps/api/core";
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import { queryKeys } from "@/lib/query-keys";
import { skillColor } from "@/lib/skill-color";
export interface RemoteSkill {
  uid: string;
  id: string;
  name: string;
  description: string;
  repo_url: string;
  installs: number;
}

export interface SkillSource {
  id: string;
  name: string;
  description: string;
  type: "remote";
  repoUrl?: string;
  branch?: string;
}

export const SKILL_SOURCES: SkillSource[] = [
  {
    id: "skills-sh",
    name: "skills.sh",
    description: "Community skill registry",
    type: "remote",
  },
  {
    id: "claude",
    name: "Claude",
    description: "alirezarezvani/claude-skills",
    type: "remote",
    repoUrl: "https://github.com/alirezarezvani/claude-skills",
    branch: "main",
  },
  {
    id: "codex",
    name: "Codex",
    description: "ComposioHQ/awesome-codex-skills",
    type: "remote",
    repoUrl: "https://github.com/ComposioHQ/awesome-codex-skills",
    branch: "master",
  },
];

interface SkillIconProps {
  className?: string;
  textIcon?: string;
  iconPath?: string | null;
  onClick?: () => void;
}

function SkillIcon({ className, textIcon, iconPath, onClick }: SkillIconProps) {
  return (
    <div
      className={cn(
        "relative flex h-10 w-10 shrink-0 items-center justify-center rounded-md dark:bg-white/5 bg-black/5 dark:border-white/5 border-border border font-bold shadow-sm transition-transform group-hover:scale-110 overflow-hidden",
        onClick && "cursor-pointer hover:ring-2 hover:ring-purple-500/50",
        className,
      )}
      onClick={onClick}
      title={onClick ? "Click to change icon" : undefined}
    >
      {iconPath ? (
        <img
          src={convertFileSrc(iconPath)}
          alt="skill icon"
          className="h-full w-full object-cover"
        />
      ) : textIcon ? (
        <span className="text-[10px] leading-none tracking-tight">{textIcon}</span>
      ) : (
        <div className="h-4 w-4 rounded-full bg-current opacity-80" />
      )}
    </div>
  );
}

export function SkillsPage() {
  const { t } = useI18n();
  const { setSelectedSkill, setSelectedSkillSource, repositoryGroups, selectedIssueId } = useAgentsStore();
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");

  const activeThread = repositoryGroups
    .flatMap((g) => g.repositories.flatMap((r) => r.issues))
    .find((i) => i.id === selectedIssueId);
  const workspacePath = activeThread?.workspacePath ?? null;

  const { data: installedSkills = [], isLoading: loading } = useQuery({
    queryKey: queryKeys.skills(),
    queryFn: () => invoke<InstalledSkill[]>("sync_skills", { workspacePath }),
  });

  const toggleSkill = useMutation({
    mutationFn: ({ id, enabled }: { id: string; enabled: boolean }) =>
      invoke("set_skill_enabled", { id, enabled }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.skills() });
    },
  });

  const uninstallSkill = useMutation({
    mutationFn: (id: string) => invoke("uninstall_skill", { id }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.skills() });
    },
  });

  const changeIcon = async (id: string) => {
    const selected = await openDialog({
      multiple: false,
      filters: [{ name: "Image", extensions: ["png", "jpg", "jpeg", "webp", "svg"] }],
    });
    if (!selected || typeof selected !== "string") return;

    const ext = selected.split(".").pop() ?? "png";
    const bytes = await fetch(convertFileSrc(selected))
      .then((r) => r.arrayBuffer())
      .then((b) => Array.from(new Uint8Array(b)));

    await invoke<string>("set_skill_icon", { id, data: bytes, extension: ext });
    queryClient.invalidateQueries({ queryKey: queryKeys.skills() });
  };

  const query = search.toLowerCase();

  const filteredInstalled = installedSkills.filter(
    (s) =>
      !search ||
      s.name.toLowerCase().includes(query) ||
      s.description.toLowerCase().includes(query),
  );

  return (
    <PageLayout scroll>
      <div className="mx-auto w-full max-w-6xl pb-12">
        <PageHeader className="px-8">
          <div>
            <div className="flex items-center gap-3">
              <PageHeaderTitle className="text-3xl">{t("pages.skills.title")}</PageHeaderTitle>
              <span className="flex items-center gap-1.5 px-2.5 py-1 rounded-md dark:bg-white/5 bg-black/5 dark:border-white/5 border-border border text-[9px] text-zinc-500 shrink-0 font-black uppercase tracking-wider h-fit">
                {t("common.beta")}
              </span>
            </div>
            <PageHeaderMeta>
              <span>{t("pages.skills.subtitle")}</span>
            </PageHeaderMeta>
          </div>
          <PageHeaderActions className="gap-3">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-500" />
              <Input
                placeholder={t("pages.skills.searchPlaceholder")}
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="w-64 pl-9 focus-visible:ring-purple-500/50"
              />
            </div>
          </PageHeaderActions>
        </PageHeader>

        <div className="px-8 flex flex-col gap-12 mt-4">
          {/* Installed Section */}
          <div>
            <h2 className="text-[13px] font-black uppercase tracking-[0.15em] text-zinc-500 mb-6">
              {t("pages.skills.installed")}
            </h2>
            {loading ? (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {Array.from({ length: 6 }).map((_, i) => (
                  <div key={i} className="h-[66px] rounded-xl dark:bg-white/[0.03] bg-black/[0.03] animate-pulse" />
                ))}
              </div>
            ) : filteredInstalled.length === 0 ? (
              <p className="text-sm text-zinc-600">{t("pages.skills.empty")}</p>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {filteredInstalled.map((skill) => (
                  <Card
                    key={skill.id}
                    className="group overflow-hidden cursor-pointer dark:hover:border-white/10 hover:border-border transition-colors"
                    onClick={() => setSelectedSkill(skill)}
                  >
                    <CardContent className="p-4 flex items-center justify-between">
                      <div className="flex items-center gap-4 min-w-0 pr-4">
                        <SkillIcon
                          className={skillColor(skill.id)}
                          iconPath={skill.icon_path}
                          onClick={() => changeIcon(skill.id)}
                        />
                        <div className="flex flex-col gap-0.5 min-w-0">
                          <div className="flex items-center gap-2 min-w-0">
                            <span className="text-[14px] font-bold dark:text-zinc-100 text-foreground truncate">
                              {skill.name}
                            </span>
                            {skill.scope === "project" && (
                              <span className="flex items-center gap-1 shrink-0 px-1.5 py-0.5 rounded text-[9px] font-black uppercase tracking-wider bg-teal-500/10 text-teal-400 border border-teal-500/20">
                                <FolderOpen className="h-2.5 w-2.5" />
                                Project
                              </span>
                            )}
                            {(skill.scope as string) === "local" && (
                              <span className="flex items-center gap-1 shrink-0 px-1.5 py-0.5 rounded text-[9px] font-black uppercase tracking-wider bg-blue-500/10 text-blue-400 border border-blue-500/20">
                                <FolderOpen className="h-2.5 w-2.5" />
                                Local
                              </span>
                            )}
                          </div>
                          <span className="text-[13px] text-zinc-500 truncate font-medium">
                            {skill.description}
                          </span>
                        </div>
                      </div>

                      <div
                        className="flex items-center gap-1 shrink-0 pl-2"
                        onClick={(e) => e.stopPropagation()}
                      >
                        {skill.scope !== "project" && (skill.scope as string) !== "local" && (
                          <TooltipProvider>
                            <Tooltip>
                              <TooltipTrigger asChild>
                                <button
                                  className="opacity-0 group-hover:opacity-100 flex items-center gap-1.5 px-2 h-8 rounded-md text-red-400 hover:text-red-300 hover:bg-red-500/10 transition-all text-xs font-semibold"
                                  onClick={() => uninstallSkill.mutate(skill.id)}
                                >
                                  <Trash2 className="h-3.5 w-3.5" />
                                  {t("common.uninstall")}
                                </button>
                              </TooltipTrigger>
                              <TooltipContent className="bg-zinc-800 text-zinc-200 border-zinc-700 text-xs">
                                {t("pages.skills.removeTooltip")}
                              </TooltipContent>
                            </Tooltip>
                          </TooltipProvider>
                        )}

                        <Switch
                          checked={skill.enabled}
                          onCheckedChange={(checked) => toggleSkill.mutate({ id: skill.id, enabled: checked })}
                          className="data-[state=checked]:bg-purple-500 ml-1"
                        />
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}
          </div>

          {/* Discover Section */}
          <div className="pb-12">
            <h2 className="text-[13px] font-black uppercase tracking-[0.15em] text-zinc-500 mb-6">
              {t("pages.skills.recommended")}
            </h2>

            <div className="flex flex-col gap-3">
              {SKILL_SOURCES.map((source) => (
                <Card
                  key={source.id}
                  className="group overflow-hidden cursor-pointer dark:hover:border-white/10 hover:border-border transition-colors"
                  onClick={() => setSelectedSkillSource({ id: source.id, name: source.name, description: source.description })}
                >
                  <CardContent className="p-4 flex items-center justify-between">
                    <div className="flex items-center gap-4 min-w-0 pr-4">
                      <div className="relative flex h-10 w-10 shrink-0 items-center justify-center rounded-md dark:bg-white/5 bg-black/5 dark:border-white/5 border-border border shadow-sm">
                        <Globe className="h-4 w-4 text-zinc-500" />
                      </div>
                      <div className="flex flex-col gap-0.5 min-w-0">
                        <span className="text-[14px] font-bold dark:text-zinc-100 text-foreground truncate">
                          {source.name}
                        </span>
                        <span className="text-[13px] text-zinc-500 truncate font-medium">
                          {source.description}
                        </span>
                      </div>
                    </div>
                    <div className="flex items-center gap-1 shrink-0 pl-2">
                      <ChevronRight className="h-4 w-4 text-zinc-500 group-hover:text-foreground transition-colors" />
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          </div>
        </div>
      </div>
    </PageLayout>
  );
}
