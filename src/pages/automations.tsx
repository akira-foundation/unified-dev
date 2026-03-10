import { RefreshCcw, Search, Plus } from "lucide-react";
import { PageLayout } from "@/components/layout/page-layout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

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
  return (
    <PageLayout scroll>
      <div className="mx-auto w-full max-w-5xl py-8 px-8">

        {/* Top Navigation Row */}
        <div className="flex items-center justify-end gap-3 mb-10">
          <Button variant="ghost" className="h-9 px-3 text-zinc-400 hover:text-white hover:bg-white/5 font-medium text-xs">
            <RefreshCcw className="mr-2 h-3.5 w-3.5" />
            Refresh
          </Button>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-zinc-500" />
            <Input
              placeholder="Search automations"
              className="h-9 w-64 pl-9 bg-[#1a1a1a] border-white/5 text-sm text-zinc-300 placeholder:text-zinc-600 rounded-lg focus-visible:ring-1 focus-visible:ring-purple-500/50"
            />
          </div>
          <Button className="h-9 px-4 bg-white text-black hover:bg-zinc-200 font-medium text-xs rounded-lg shadow-md transition-colors gap-1.5">
            <Plus className="h-3.5 w-3.5" />
            New automation
          </Button>
        </div>

        {/* Header Title */}
        <div className="mb-12">
          <div className="flex items-center gap-3 mb-2">
            <h1 className="text-3xl font-bold text-white">Automations</h1>
            <span className="flex items-center gap-1.5 px-2 py-0.5 rounded-md bg-white/5 border border-white/5 text-[10px] text-zinc-400 shrink-0 font-medium">
              Beta
            </span>
          </div>
          <p className="text-[15px] text-zinc-400">
            Automate work by setting up scheduled threads.
          </p>
        </div>

        {/* Templates Section */}
        <div className="pb-12">
          <h2 className="text-[13px] font-medium text-zinc-300 mb-4">Start with a template</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {templates.map((template, idx) => (
              <button
                key={idx}
                className="flex flex-col text-left gap-3 p-5 rounded-2xl bg-[#131313] border border-white/[0.03] hover:bg-[#1a1a1a] hover:border-white/5 transition-all w-full min-h-[110px]"
              >
                <div className="text-xl leading-none opacity-90">{template.icon}</div>
                <span className="text-[13px] font-semibold text-zinc-100 leading-snug">
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
