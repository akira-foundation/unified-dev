import { useState } from "react";
import { RefreshCcw, Plus, Folder, Search } from "lucide-react";
import { PageLayout } from "@/components/layout/page-layout";
import { PageHeader, PageHeaderMeta, PageHeaderTitle, PageHeaderActions } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";

const installedSkills = [
  {
    id: "fortify",
    title: "Developing with Fortify",
    description: "Laravel Fortify headless authentication backe...",
    badge: "audit",
    active: true,
    icon: "bg-indigo-500/10 text-indigo-500",
  },
  {
    id: "figma",
    title: "Figma",
    description: "Use Figma MCP for design-to-code work",
    active: true,
    icon: "bg-pink-500/10 text-pink-500",
  },
  {
    id: "auditor",
    title: "Default Branch Issue Auditor",
    description: "Audit default branch and open prioritized issues",
    active: true,
    icon: "bg-zinc-500/10 text-zinc-500",
  },
  {
    id: "gh-resolver",
    title: "GH Issue Resolver PR",
    description: "Triar issues por urgência, corrigir e abrir PRs...",
    active: true,
    icon: "bg-zinc-500/10 text-zinc-500",
  },
  {
    id: "gh-creator",
    title: "GitHub Issue Creator",
    description: "Create concise, labeled GitHub issues",
    active: true,
    icon: "bg-zinc-500/10 text-zinc-500",
  },
  {
    id: "inertia",
    title: "Inertia React Development",
    description: "Develops Inertia.js v2 React client-side...",
    badge: "audit",
    active: true,
    icon: "bg-purple-500/10 text-purple-500",
  },
  {
    id: "laravel-refiner",
    title: "Laravel Code Refiner",
    description: "Refine Laravel code without behavior changes",
    active: true,
    icon: "bg-red-500/10 text-red-500",
  },
  {
    id: "linear",
    title: "Linear",
    description: "Manage Linear issues in Codex",
    active: true,
    icon: "bg-zinc-800 text-white",
  },
  {
    id: "linear-creator",
    title: "Linear Issue Creator",
    description: "Create Linear issues from user requests",
    active: true,
    icon: "bg-zinc-800 text-white",
  },
  {
    id: "pest",
    title: "Pest Testing",
    description: "Tests applications using the Pest 4 PHP...",
    badge: "audit",
    active: true,
    icon: "bg-rose-500/10 text-rose-500",
  },
  {
    id: "skill-creator",
    title: "Skill Creator",
    description: "Create or update a skill",
    active: true,
    icon: "bg-yellow-500/10 text-yellow-500",
  },
  {
    id: "skill-installer",
    title: "Skill Installer",
    description: "Install curated skills from openai/skills or othe...",
    active: true,
    icon: "bg-orange-500/10 text-orange-500",
  },
  {
    id: "slides",
    title: "Slides",
    description: "Create and edit slide decks with the artifacts...",
    active: true,
    icon: "bg-blue-500/10 text-blue-500",
  },
  {
    id: "spreadsheets",
    title: "Spreadsheets",
    description: "Create and edit spreadsheets with the artifact...",
    active: true,
    icon: "bg-green-500/10 text-green-500",
  },
  {
    id: "tailwindcss",
    title: "Tailwindcss Development",
    description: "Styles applications using Tailwind CSS v4...",
    badge: "audit",
    active: true,
    icon: "bg-cyan-500/10 text-cyan-500",
  },
  {
    id: "wayfinder",
    title: "Wayfinder Development",
    description: "Activates whenever referencing backend rout...",
    badge: "audit",
    active: true,
    icon: "bg-teal-500/10 text-teal-500",
  },
];

const recommendedSkills = [
  {
    id: "aspnet",
    title: "Aspnet Core",
    description: "[Windows only] Build and review ASP.NET Core web...",
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
    description: "Deploy Workers, Pages, and platform services on...",
    icon: "bg-orange-500/10 text-orange-500",
  },
  {
    id: "webgame",
    title: "Develop Web Game",
    description: "Web game dev + Playwright test loop",
    icon: "bg-neutral-200 text-neutral-800",
  },
];

function SkillIcon({ className, textIcon }: { className?: string, textIcon?: string }) {
  return (
    <div className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-xl font-bold shadow-sm", className)}>
      {textIcon ? (
        <span className="text-[10px] leading-none tracking-tight">{textIcon}</span>
      ) : (
        <div className="h-4 w-4 rounded-full bg-current opacity-80" />
      )}
    </div>
  );
}

export function SkillsPage() {
  const [activeSkills, setActiveSkills] = useState<Record<string, boolean>>(
    Object.fromEntries(installedSkills.map(skill => [skill.id, skill.active]))
  );

  const toggleSkill = (id: string, checked: boolean) => {
    setActiveSkills(prev => ({ ...prev, [id]: checked }));
  };

  return (
    <PageLayout scroll>
      <div className="mx-auto w-full max-w-6xl pb-12">
        <PageHeader className="px-8">
          <div>
            <PageHeaderTitle className="text-3xl">Skills</PageHeaderTitle>
            <PageHeaderMeta>
              <span>Give Unified Dev superpowers.</span>
            </PageHeaderMeta>
          </div>
          <PageHeaderActions className="gap-3">
            <Button variant="ghost" className="text-zinc-400 hover:text-white hover:bg-white/5 font-medium text-xs">
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
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {installedSkills.map((skill) => (
                <Card key={skill.id} className="group overflow-hidden">
                  <CardContent className="p-4 flex items-center justify-between">
                    <div className="flex items-center gap-4 min-w-0 pr-4">
                      <SkillIcon className={skill.icon} />
                      <div className="flex flex-col gap-0.5 min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="text-[14px] font-bold text-zinc-100 truncate">{skill.title}</span>
                          {skill.badge === "audit" && (
                            <div className="flex items-center gap-1.5 px-2 py-0.5 rounded-md bg-white/5 border border-white/5 text-[9px] font-black uppercase tracking-wider text-zinc-500 shrink-0">
                              <Folder className="h-3 w-3" />
                              <span>audit</span>
                            </div>
                          )}
                        </div>
                        <span className="text-[13px] text-zinc-500 truncate font-medium">{skill.description}</span>
                      </div>
                    </div>
                    <div className="shrink-0 pl-2">
                      <Switch
                        checked={activeSkills[skill.id]}
                        onCheckedChange={(checked) => toggleSkill(skill.id, checked)}
                        className="data-[state=checked]:bg-purple-500"
                      />
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          </div>

          {/* Recommended Section */}
          <div className="pb-12">
            <h2 className="text-[13px] font-black uppercase tracking-[0.15em] text-zinc-500 mb-6">Recommended</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
              {recommendedSkills.map((skill) => (
                <Card key={skill.id} className="group overflow-hidden">
                  <CardContent className="p-4 flex items-center justify-between">
                    <div className="flex items-center gap-4 min-w-0 pr-4">
                      <SkillIcon className={skill.icon} textIcon={skill.textIcon} />
                      <div className="flex flex-col gap-0.5 min-w-0">
                        <span className="text-[14px] font-bold text-zinc-100 truncate">{skill.title}</span>
                        <span className="text-[13px] text-zinc-500 truncate font-medium">{skill.description}</span>
                      </div>
                    </div>
                    <div className="shrink-0 pl-2">
                      <button className="flex items-center justify-center w-8 h-8 rounded-full text-zinc-500 hover:text-white hover:bg-white/10 transition-colors">
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
