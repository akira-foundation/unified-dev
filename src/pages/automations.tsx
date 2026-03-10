import { RefreshCcw, Plus, Search } from "lucide-react";
import { PageLayout } from "@/components/layout/page-layout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useAgentsStore } from "@/stores/useAgentsStore";

const templates = [
  {
    icon: "🐞",
    text: "Scan recent commits (since the last run, or last 24h) for likely bugs and propose minimal fixes."
  },
  {
    icon: "📖",
    text: "Draft weekly release notes from merged PRs (include links when available)."
  },
  {
    icon: "💬",
    text: "Summarize yesterday's git activity for standup."
  },
  {
    icon: "🎯",
    text: "Summarize CI failures and flaky tests from the last CI window; suggest top fixes."
  },
  {
    icon: "⭐",
    text: "Create a small classic game with minimal scope."
  },
  {
    icon: "🗂️",
    text: "From recent PRs and reviews, suggest next skills to deepen."
  },
  {
    icon: "📄",
    text: "Synthesize this week's PRs, rollouts, incidents, and reviews into a weekly update."
  },
  {
    icon: "👍",
    text: "Compare recent changes to benchmarks or traces and flag regressions early."
  },
  {
    icon: "✅",
    text: "Detect dependency and SDK drift and propose a minimal alignment plan."
  },
  {
    icon: "🧩",
    text: "Identify untested paths from recent changes; add focused tests and use $yeet for draft PRs."
  },
  {
    icon: "✅",
    text: "Before tagging, verify changelog, migrations, feature flags, and tests."
  },
  {
    icon: "📝",
    text: "Update AGENTS.md with newly discovered workflows and commands."
  },
  {
    icon: "📰",
    text: "Summarize last week's PRs by teammate and theme; underline risks."
  },
  {
    icon: "❗",
    text: "Triage new issues; suggest owner, priority, and labels."
  },
  {
    icon: "⌨️",
    text: "Check CI failures; group by likely root cause and suggest minimal fixes."
  },
  {
    icon: "📦",
    text: "Scan outdated dependencies; propose safe upgrades with minimal changes."
  }
];

export function AutomationsPage() {
  const setActiveTab = useAgentsStore((state) => state.setActiveTab);

  return (
    <PageLayout scroll>
      <div className="mx-auto w-full max-w-5xl py-8 px-8">

        {/* Top Navigation Row */}
        <div className="flex items-center justify-end gap-3 mb-10">
          <Button variant="ghost" className="text-zinc-400 hover:text-white hover:bg-white/5 font-medium text-xs">
            <RefreshCcw className="mr-2 h-3.5 w-3.5" />
            Refresh
          </Button>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-500" />
            <Input
              placeholder="Search automations"
              className="w-64 pl-9 bg-[#161616] border-white/5 text-sm text-zinc-300 placeholder:text-zinc-600 focus-visible:ring-1 focus-visible:ring-purple-500/50 transition-colors"
            />
          </div>
          <Button
            onClick={() => setActiveTab("create-automation")}
            className="gap-1.5"
          >
            <Plus className="h-4 w-4" strokeWidth={3} />
            New automation
          </Button>
        </div>

        {/* Header Title */}
        <div className="mb-12">
          <div className="flex items-center gap-3 mb-2">
            <h1 className="text-3xl font-bold text-white tracking-tight">Automations</h1>
            <span className="flex items-center gap-1.5 px-2.5 py-1 rounded bg-white/5 border border-white/5 text-[9px] text-zinc-400 shrink-0 font-black uppercase tracking-wider">
              Beta
            </span>
          </div>
          <p className="text-[15px] text-zinc-400 font-medium">
            Automate work by setting up scheduled threads.
          </p>
        </div>

        {/* Templates Section */}
        <div className="pb-12">
          <h2 className="text-xs font-black uppercase tracking-[0.15em] text-zinc-500 mb-6">Start with a template</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {templates.map((template, idx) => (
              <button
                key={idx}
                onClick={() => setActiveTab("create-automation")}
                className="group flex flex-col text-left gap-4 p-6 rounded-2xl bg-[#0f0f0f] border border-white/[0.03] hover:bg-[#161616] hover:border-white/10 transition-all w-full min-h-[140px] shadow-sm hover:shadow-xl hover:shadow-black/50"
              >
                <div className="text-2xl leading-none opacity-90 group-hover:scale-110 transition-transform origin-left">{template.icon}</div>
                <span className="text-[13px] font-bold text-zinc-200 leading-snug group-hover:text-white transition-colors">
                  {template.text}
                </span>
              </button>
            ))}
          </div>
        </div>

      </div>
    </PageLayout>
  );
}
