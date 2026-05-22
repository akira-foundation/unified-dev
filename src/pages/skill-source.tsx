import { useState } from "react";
import { Download, Loader2, Search } from "lucide-react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { PageLayout } from "@/components/layout/page-layout";
import { PageHeader, PageHeaderTitle, PageHeaderMeta, PageHeaderActions } from "@/components/layout/page-header";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
import { useAgentsStore, type InstalledSkill } from "@/stores/useAgentsStore";
import { useI18n } from "@/i18n/i18n";
import { queryKeys } from "@/lib/query-keys";
import { skillColor } from "@/lib/skill-color";
import { SKILL_SOURCES, type RemoteSkill } from "@/lib/skill-sources";

const FOUR_HOURS = 4 * 60 * 60 * 1000;

async function fetchRemoteSkills(source: { id: string; repoUrl?: string; branch?: string }): Promise<RemoteSkill[]> {
  const skills: RemoteSkill[] = [];

  return new Promise(async (resolve, reject) => {
    const unlistenSkill = await listen<RemoteSkill>("skills:discover:skill", (event) => {
      if (!skills.some((s) => s.uid === event.payload.uid)) {
        skills.push(event.payload);
      }
    });

    const unlistenDone = await listen("skills:discover:done", () => {
      unlistenSkill();
      unlistenDone();
      resolve(skills);
    });

    const cmd =
      source.id === "skills-sh"
        ? invoke("fetch_recommended_skills")
        : invoke("fetch_skills_from_repo", { repoUrl: source.repoUrl, branch: source.branch });

    cmd.catch((err) => {
      unlistenSkill();
      unlistenDone();
      reject(err);
    });
  });
}

function SkillIcon({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        "relative flex h-10 w-10 shrink-0 items-center justify-center rounded-md dark:bg-white/5 bg-black/5 dark:border-white/5 border-border border font-bold shadow-sm transition-transform group-hover:scale-110 overflow-hidden",
        className,
      )}
    >
      <div className="h-4 w-4 rounded-full bg-current opacity-80" />
    </div>
  );
}

export function SkillSourcePage() {
  const { t } = useI18n();
  const { selectedSkillSource, setSelectedSkill } = useAgentsStore();
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");

  const source = SKILL_SOURCES.find((s) => s.id === selectedSkillSource?.id);

  const { data: remoteSkills = [], isLoading } = useQuery({
    queryKey: ["remote-skills", selectedSkillSource?.id],
    queryFn: () => fetchRemoteSkills(source!),
    enabled: !!source,
    staleTime: FOUR_HOURS,
    gcTime: FOUR_HOURS,
  });

  const filtered = search.trim()
    ? remoteSkills.filter(
        (s) =>
          s.name.toLowerCase().includes(search.toLowerCase()) ||
          s.description.toLowerCase().includes(search.toLowerCase()),
      )
    : remoteSkills;

  const installSkill = useMutation({
    mutationFn: ({ skillId, repoUrl }: { skillId: string; repoUrl: string }) =>
      invoke<InstalledSkill>("install_skill", { skillId, repoUrl }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.skills() });
    },
  });

  return (
    <PageLayout scroll>
      <div className="mx-auto w-full max-w-6xl pb-12">
        <PageHeader className="px-8">
          <div className="flex flex-col gap-1">
            <div className="flex items-center gap-3">
              <PageHeaderTitle>{selectedSkillSource?.name}</PageHeaderTitle>
            </div>
            <PageHeaderMeta>
              <span>{selectedSkillSource?.description}</span>
            </PageHeaderMeta>
          </div>
          <PageHeaderActions>
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-500" />
              <Input
                placeholder={t("pages.skillSource.searchPlaceholder")}
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="w-64 pl-9 focus-visible:ring-purple-500/50"
              />
            </div>
          </PageHeaderActions>
        </PageHeader>

        <div className="px-8 mt-4">
          {isLoading && remoteSkills.length === 0 ? (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
              {Array.from({ length: 6 }).map((_, i) => (
                <div key={i} className="h-[66px] rounded-xl dark:bg-white/[0.03] bg-black/[0.03] animate-pulse" />
              ))}
            </div>
          ) : filtered.length === 0 ? (
            <p className="text-sm text-zinc-600">{t("pages.skills.empty")}</p>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
              {filtered.map((skill) => {
                const isInstalling = installSkill.isPending && installSkill.variables?.skillId === skill.id;
                return (
                  <Card
                    key={skill.uid}
                    className="group overflow-hidden dark:hover:border-white/10 hover:border-border transition-colors cursor-pointer"
                    onClick={() => {
                      setSelectedSkill(skill);
                    }}
                  >
                    <CardContent className="p-4 flex items-center justify-between">
                      <div className="flex items-center gap-4 min-w-0 pr-4">
                        <SkillIcon className={skillColor(skill.uid)} />
                        <div className="flex flex-col gap-0.5 min-w-0">
                          <span className="text-[14px] font-bold dark:text-zinc-100 text-foreground truncate">
                            {skill.name}
                          </span>
                          <span className="text-[13px] text-zinc-500 truncate font-medium">
                            {skill.description}
                          </span>
                        </div>
                      </div>
                      <div className="flex items-center gap-1 shrink-0 pl-2">
                        <TooltipProvider>
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <button
                                disabled={isInstalling}
                                className="flex items-center gap-1.5 px-2 h-8 rounded-md text-zinc-400 hover:text-foreground dark:hover:bg-white/10 hover:bg-black/10 disabled:opacity-50 disabled:cursor-not-allowed transition-all text-xs font-semibold"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  installSkill.mutate({ skillId: skill.id, repoUrl: skill.repo_url });
                                }}
                              >
                                {isInstalling ? (
                                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                                ) : (
                                  <Download className="h-3.5 w-3.5" />
                                )}
                                {isInstalling ? t("common.installing") : t("common.install")}
                              </button>
                            </TooltipTrigger>
                            <TooltipContent className="bg-zinc-800 text-zinc-200 border-zinc-700 text-xs">
                              {t("pages.skills.installTooltip")}
                            </TooltipContent>
                          </Tooltip>
                        </TooltipProvider>
                      </div>
                    </CardContent>
                  </Card>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </PageLayout>
  );
}
