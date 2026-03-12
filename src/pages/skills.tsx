import { useState, useEffect } from "react";
import { RefreshCcw, Plus, Search, Settings } from "lucide-react";
import { PageLayout } from "@/components/layout/page-layout";
import { PageHeader, PageHeaderMeta, PageHeaderTitle, PageHeaderActions } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { invoke } from "@tauri-apps/api/core";

interface InstalledSkill {
  id: string;
  name: string;
  description: string;
}

const recommendedSkills = [
  {
    id: "fortify",
    title: "Developing with Fortify",
    description: "Laravel Fortify headless authentication backend",
    icon: "bg-indigo-500/10 text-indigo-500",
  },
  {
    id: "skill-creator",
    title: "Skill Creator",
    description: "Create or update a skill",
    icon: "bg-yellow-500/10 text-yellow-500",
  },
  {
    id: "skill-installer",
    title: "Skill Installer",
    description: "Install curated skills from a GitHub repo",
    icon: "bg-orange-500/10 text-orange-500",
  },
  {
    id: "slides",
    title: "Slides",
    description: "Create and edit slide decks with artifacts",
    icon: "bg-blue-500/10 text-blue-500",
  },
  {
    id: "spreadsheets",
    title: "Spreadsheets",
    description: "Create and edit spreadsheets with artifacts",
    icon: "bg-green-500/10 text-green-500",
  },
  {
    id: "aspnet",
    title: "Aspnet Core",
    description: "[Windows only] Build and review ASP.NET Core web apps",
    icon: "bg-purple-600 border-purple-500 text-white",
    textIcon: ".NET",
  },
  {
    id: "chatgpt",
    title: "Chatgpt Apps",
    description: "Build and scaffold ChatGPT apps",
    icon: "bg-orange-500/10 text-orange-500",
  },
  {
    id: "cloudflare",
    title: "Cloudflare Deploy",
    description: "Deploy Workers, Pages, and platform services",
    icon: "bg-orange-500/10 text-orange-500",
  },
  {
    id: "webgame",
    title: "Develop Web Game",
    description: "Web game dev + Playwright test loop",
    icon: "bg-neutral-200 text-neutral-800",
  },
];

const SKILL_COLORS = [
  "bg-red-500/15 text-red-400",
  "bg-rose-500/15 text-rose-400",
  "bg-pink-500/15 text-pink-400",
  "bg-fuchsia-500/15 text-fuchsia-400",
  "bg-purple-500/15 text-purple-400",
  "bg-violet-500/15 text-violet-400",
  "bg-indigo-500/15 text-indigo-400",
  "bg-blue-500/15 text-blue-400",
  "bg-sky-500/15 text-sky-400",
  "bg-cyan-500/15 text-cyan-400",
  "bg-teal-500/15 text-teal-400",
  "bg-emerald-500/15 text-emerald-400",
  "bg-green-500/15 text-green-400",
  "bg-lime-500/15 text-lime-400",
  "bg-yellow-500/15 text-yellow-400",
  "bg-amber-500/15 text-amber-400",
  "bg-orange-500/15 text-orange-400",
];

function skillColor(id: string): string {
  let hash = 0;
  for (let i = 0; i < id.length; i++) {
    hash = (hash * 31 + id.charCodeAt(i)) >>> 0;
  }
  return SKILL_COLORS[hash % SKILL_COLORS.length];
}

function SkillIcon({ className, textIcon }: { className?: string; textIcon?: string }) {
  return (
    <div className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-white/5 border border-white/5 font-bold shadow-sm transition-transform group-hover:scale-110", className)}>
      {textIcon ? (
        <span className="text-[10px] leading-none tracking-tight">{textIcon}</span>
      ) : (
        <div className="h-4 w-4 rounded-full bg-current opacity-80" />
      )}
    </div>
  );
}

export function SkillsPage() {
  const [installedSkills, setInstalledSkills] = useState<InstalledSkill[]>([]);
  const [activeSkills, setActiveSkills] = useState<Record<string, boolean>>({});
  const [loading, setLoading] = useState(true);
  const { setSelectedSkill } = useAgentsStore();

  const loadSkills = async () => {
    setLoading(true);
    try {
      const skills = await invoke<InstalledSkill[]>("list_installed_skills");
      setInstalledSkills(skills);
      setActiveSkills(prev => {
        const next: Record<string, boolean> = {};
        for (const s of skills) {
          next[s.id] = prev[s.id] ?? true;
        }
        return next;
      });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { loadSkills(); }, []);

  const toggleSkill = (id: string, checked: boolean) => {
    setActiveSkills(prev => ({ ...prev, [id]: checked }));
  };

  return (
    <PageLayout scroll>
      <div className="mx-auto w-full max-w-6xl pb-12">
        <PageHeader className="px-8">
          <div>
            <div className="flex items-center gap-3">
              <PageHeaderTitle className="text-3xl">Skills</PageHeaderTitle>
              <span className="flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-white/5 border border-white/5 text-[9px] text-zinc-400 shrink-0 font-black uppercase tracking-wider h-fit">
                Beta
              </span>
            </div>
            <PageHeaderMeta>
              <span>Give Unified Dev superpowers.</span>
            </PageHeaderMeta>
          </div>
          <PageHeaderActions className="gap-3">
            <Button
              variant="ghost"
              className="text-zinc-400 hover:text-white hover:bg-white/5 font-medium text-xs"
              onClick={loadSkills}
            >
              <RefreshCcw className="mr-2 h-3.5 w-3.5" />
              Refresh
            </Button>
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-500" />
              <Input
                placeholder="Search skills"
                className="w-64 pl-9 bg-zinc-900/50 border-white/5 text-sm text-zinc-300 placeholder:text-zinc-600 focus-visible:ring-1 focus-visible:ring-purple-500/50 transition-colors"
              />
            </div>
            <Button className="gap-1.5">
              <Plus className="h-4 w-4" strokeWidth={3} />
              New skill
            </Button>
          </PageHeaderActions>
        </PageHeader>

        <div className="px-8 flex flex-col gap-12 mt-4">
          {/* Installed Section */}
          <div>
            <h2 className="text-[13px] font-black uppercase tracking-[0.15em] text-zinc-500 mb-6">Installed</h2>
            {loading ? (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {Array.from({ length: 6 }).map((_, i) => (
                  <div key={i} className="h-[66px] rounded-xl bg-white/[0.03] animate-pulse" />
                ))}
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {installedSkills.map((skill) => (
                  <Card
                    key={skill.id}
                    className="group overflow-hidden cursor-pointer hover:border-white/10 transition-colors"
                    onClick={() => setSelectedSkill(skill)}
                  >
                    <CardContent className="p-4 flex items-center justify-between">
                      <div className="flex items-center gap-4 min-w-0 pr-4">
                        <SkillIcon className={skillColor(skill.id)} />
                        <div className="flex flex-col gap-0.5 min-w-0">
                          <span className="text-[14px] font-bold text-zinc-100 truncate">{skill.name}</span>
                          <span className="text-[13px] text-zinc-500 truncate font-medium">{skill.description}</span>
                        </div>
                      </div>
                      <div className="flex items-center gap-2 shrink-0 pl-2">
                        <div onClick={(e) => e.stopPropagation()}>
                          <Switch
                            checked={activeSkills[skill.id] ?? true}
                            onCheckedChange={(checked) => toggleSkill(skill.id, checked)}
                            className="data-[state=checked]:bg-purple-500"
                          />
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}
          </div>

          {/* Recommended Section */}
          <div className="pb-12">
            <h2 className="text-[13px] font-black uppercase tracking-[0.15em] text-zinc-500 mb-6">Recommended</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
              {recommendedSkills.map((skill) => (
                <Card
                  key={skill.id}
                  className="group overflow-hidden cursor-pointer hover:border-white/10 transition-colors"
                  onClick={() => setSelectedSkill({ ...skill, recommended: true })}
                >
                  <CardContent className="p-4 flex items-center justify-between">
                    <div className="flex items-center gap-4 min-w-0 pr-4">
                      <SkillIcon className={skillColor(skill.id)} textIcon={"textIcon" in skill ? skill.textIcon : undefined} />
                      <div className="flex flex-col gap-0.5 min-w-0">
                        <span className="text-[14px] font-bold text-zinc-100 truncate">{skill.title}</span>
                        <span className="text-[13px] text-zinc-500 truncate font-medium">{skill.description}</span>
                      </div>
                    </div>
                    <div className="flex items-center gap-2 shrink-0 pl-2">
                      <TooltipProvider>
                        <Tooltip>
                          <TooltipTrigger asChild>
                            <button
                              className="opacity-0 group-hover:opacity-100 flex items-center justify-center w-8 h-8 rounded-md text-zinc-500 hover:text-white hover:bg-white/10 transition-all font-medium"
                              onClick={(e) => {
                                e.stopPropagation();
                                setSelectedSkill({ ...skill, recommended: true });
                              }}
                            >
                              <Settings className="h-4 w-4" />
                            </button>
                          </TooltipTrigger>
                          <TooltipContent className="bg-purple-500 text-white border-none font-bold">
                            <span className="text-xs">Manage skill</span>
                          </TooltipContent>
                        </Tooltip>
                      </TooltipProvider>

                      <button
                        className="flex items-center justify-center w-8 h-8 rounded-md text-zinc-500 hover:text-white hover:bg-white/10 transition-colors"
                        onClick={(e) => {
                          e.stopPropagation();
                        }}
                      >
                        <Plus className="h-4 w-4" />
                      </button>
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
