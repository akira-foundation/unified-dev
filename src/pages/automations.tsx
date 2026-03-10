import { RefreshCcw, Plus, Search, Settings } from "lucide-react";
import { PageLayout } from "@/components/layout/page-layout";
import { PageHeader, PageHeaderTitle, PageHeaderMeta, PageHeaderActions } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent } from "@/components/ui/card";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { useAgentsStore } from "@/stores/useAgentsStore";

const templates = [
  {
    id: "scan-commits",
    icon: "🐞",
    text: "Scan recent commits (since the last run, or last 24h) for likely bugs and propose minimal fixes."
  },
  {
    id: "release-notes",
    icon: "📖",
    text: "Draft weekly release notes from merged PRs (include links when available)."
  },
  {
    id: "standup-summary",
    icon: "💬",
    text: "Summarize yesterday's git activity for standup."
  },
  {
    id: "ci-failures",
    icon: "🎯",
    text: "Summarize CI failures and flaky tests from the last CI window; suggest top fixes."
  },
  {
    id: "mini-game",
    icon: "⭐",
    text: "Create a small classic game with minimal scope."
  },
  {
    id: "skill-deepen",
    icon: "🗂️",
    text: "From recent PRs and reviews, suggest next skills to deepen."
  },
  {
    id: "weekly-update",
    icon: "📄",
    text: "Synthesize this week's PRs, rollouts, incidents, and reviews into a weekly update."
  },
  {
    id: "benchmarks",
    icon: "👍",
    text: "Compare recent changes to benchmarks or traces and flag regressions early."
  },
  {
    id: "sdk-drift",
    icon: "✅",
    text: "Detect dependency and SDK drift and propose a minimal alignment plan."
  },
  {
    id: "untested-paths",
    icon: "🧩",
    text: "Identify untested paths from recent changes; add focused tests and use $yeet for draft PRs."
  },
  {
    id: "pre-tagging",
    icon: "✅",
    text: "Before tagging, verify changelog, migrations, feature flags, and tests."
  },
  {
    id: "update-agents-md",
    icon: "📝",
    text: "Update AGENTS.md with newly discovered workflows and commands."
  },
  {
    id: "team-summary",
    icon: "📰",
    text: "Summarize last week's PRs by teammate and theme; underline risks."
  },
  {
    id: "triage-issues",
    icon: "❗",
    text: "Triage new issues; suggest owner, priority, and labels."
  },
  {
    id: "ci-fixgroup",
    icon: "⌨️",
    text: "Check CI failures; group by likely root cause and suggest minimal fixes."
  },
  {
    id: "outdated-deps",
    icon: "📦",
    text: "Scan outdated dependencies; propose safe upgrades with minimal changes."
  }
];

export function AutomationsPage() {
  const { setActiveTab, setSelectedAutomation } = useAgentsStore();

  return (
    <PageLayout scroll>
      <div className="mx-auto w-full max-w-6xl pb-12">
        <PageHeader className="px-8">
          <div className="flex-1">
            <div className="flex items-center gap-3">
              <PageHeaderTitle className="text-3xl">Automations</PageHeaderTitle>
              <span className="flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-white/5 border border-white/5 text-[9px] text-zinc-400 shrink-0 font-black uppercase tracking-wider h-fit">
                Beta
              </span>
            </div>
            <PageHeaderMeta>
              <span>Automate work by setting up scheduled threads.</span>
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
                placeholder="Search automations"
                className="w-64 pl-9 bg-zinc-900/50 border-white/5 text-sm text-zinc-300 placeholder:text-zinc-600 focus-visible:ring-1 focus-visible:ring-purple-500/50 transition-colors"
              />
            </div>
            <Button
              onClick={() => setActiveTab("create-automation")}
              className="gap-1.5"
            >
              <Plus className="h-4 w-4" strokeWidth={3} />
              New automation
            </Button>
          </PageHeaderActions>
        </PageHeader>

        <div className="px-8 mt-4">
          <h2 className="text-[13px] font-black uppercase tracking-[0.15em] text-zinc-500 mb-6">Start with a template</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {templates.map((template, idx) => (
              <button
                key={idx}
                onClick={() => setSelectedAutomation(template)}
                className="w-full text-left group transition-all active:scale-[0.98]"
              >
                <Card className="group overflow-hidden">
                  <CardContent className="p-4 flex items-center justify-between">
                    <div className="flex items-center gap-4 min-w-0 pr-4">
                      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-white/5 border border-white/5 font-bold shadow-sm transition-transform group-hover:scale-110">
                        <span className="text-xl leading-none">{template.icon}</span>
                      </div>
                      <div className="flex flex-col gap-0.5 min-w-0">
                        <span className="text-[13px] text-zinc-400 font-medium leading-snug group-hover:text-zinc-200 transition-colors line-clamp-2">
                          {template.text}
                        </span>
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
                                setSelectedAutomation(template);
                              }}
                            >
                              <Settings className="h-4 w-4" />
                            </button>
                          </TooltipTrigger>
                          <TooltipContent className="bg-purple-500 text-white border-none font-bold">
                            <span className="text-xs">Configure automation</span>
                          </TooltipContent>
                        </Tooltip>
                      </TooltipProvider>

                      <div className="flex items-center justify-center w-8 h-8 rounded-md text-zinc-500 group-hover:text-white group-hover:bg-white/10 transition-colors">
                        <Plus className="h-4 w-4" />
                      </div>
                    </div>
                  </CardContent>
                </Card>
              </button>
            ))}
          </div>
        </div>
      </div>
    </PageLayout>
  );
}
