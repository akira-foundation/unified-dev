import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import {
  ArrowRight,
  Bot,
  CheckCircle2,
  CircleDot,
  FolderGit2,
  GitPullRequest,
  Layers,
  Loader2,
  RefreshCcw,
  Rocket,
  Sparkles,
  TriangleAlert,
  XCircle,
  Zap,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useOnboardingStore } from "@/stores/onboarding-store";

interface DependencyStatus {
  id: string;
  label: string;
  installed: boolean;
  version: string | null;
  path: string | null;
}

const OPTIONAL = new Set(["codex", "copilot"]);

const INSTALL_URLS: Record<string, string> = {
  claude: "https://docs.anthropic.com/en/docs/claude-code",
  gh: "https://cli.github.com",
  codex: "https://github.com/openai/codex",
  copilot: "https://cli.github.com",
};

const FEATURES = [
  {
    icon: FolderGit2,
    color: "text-blue-400",
    bg: "bg-blue-500/10",
    title: "Repositories",
    description: "Connect GitHub orgs, sync repos and branches",
  },
  {
    icon: Bot,
    color: "text-purple-400",
    bg: "bg-purple-500/10",
    title: "AI Agents",
    description: "Delegate issues to Claude, Codex or Copilot",
  },
  {
    icon: CircleDot,
    color: "text-emerald-400",
    bg: "bg-emerald-500/10",
    title: "Issues",
    description: "Browse, assign and close issues across all repos",
  },
  {
    icon: GitPullRequest,
    color: "text-amber-400",
    bg: "bg-amber-500/10",
    title: "Pull Requests",
    description: "Review, comment and merge without leaving the app",
  },
  {
    icon: Sparkles,
    color: "text-pink-400",
    bg: "bg-pink-500/10",
    title: "Skills",
    description: "Extend agents with local or remote skills",
  },
  {
    icon: Zap,
    color: "text-orange-400",
    bg: "bg-orange-500/10",
    title: "Background Sync",
    description: "Issues, PRs and stats stay fresh automatically",
  },
];

const STEPS = ["welcome", "dependencies", "ready"] as const;
type Step = (typeof STEPS)[number];

const STEP_META: Record<Step, { title: string; subtitle: string }> = {
  welcome: { title: "Welcome", subtitle: "What's inside" },
  dependencies: { title: "Environment", subtitle: "CLI tools" },
  ready: { title: "Ready", subtitle: "Let's go" },
};

export function OnboardingOverlay() {
  const { complete, reset } = useOnboardingStore();
  const [step, setStep] = useState<Step>("welcome");

  // Always show during development — remove this block when ready for production
  useEffect(() => { reset(); }, []);
  const [deps, setDeps] = useState<DependencyStatus[] | null>(null);
  const [checking, setChecking] = useState(false);

  useEffect(() => {
    if (step === "dependencies" && deps === null) {
      runCheck();
    }
  }, [step]);

  async function runCheck() {
    setChecking(true);
    try {
      const result = await invoke<DependencyStatus[]>("check_dependencies");
      setDeps(result);
    } finally {
      setChecking(false);
    }
  }

  const stepIndex = STEPS.indexOf(step);

  function next() {
    setStep(STEPS[stepIndex + 1]);
  }

  function back() {
    if (stepIndex > 0) setStep(STEPS[stepIndex - 1]);
  }

  const isLast = step === "ready";
  const isFirst = step === "welcome";

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-md">
      <div className="relative flex w-full max-w-3xl mx-4 rounded-2xl border border-white/8 bg-zinc-950 shadow-2xl overflow-hidden min-h-[500px]">

        {/* Left panel — fixed branding */}
        <div className="w-56 shrink-0 bg-gradient-to-b from-purple-950/60 to-zinc-950 border-r border-white/6 flex flex-col p-6">
          <div className="flex items-center gap-2.5 mb-8">
            <div className="h-8 w-8 rounded-lg bg-[#7c3aed] flex items-center justify-center shrink-0 shadow-lg shadow-purple-900/40">
              <Layers className="h-4 w-4 text-white" />
            </div>
            <span className="text-xs font-black uppercase tracking-widest text-purple-300">
              Unified Dev
            </span>
          </div>

          {/* Step list */}
          <nav className="flex flex-col gap-1">
            {STEPS.map((s, i) => {
              const done = i < stepIndex;
              const active = s === step;
              return (
                <div
                  key={s}
                  className={cn(
                    "flex items-center gap-3 px-3 py-2.5 rounded-lg transition-colors",
                    active && "bg-white/8",
                  )}
                >
                  <div
                    className={cn(
                      "h-5 w-5 rounded-full flex items-center justify-center shrink-0 text-[10px] font-black transition-colors",
                      done
                        ? "bg-purple-500 text-white"
                        : active
                          ? "bg-purple-500/20 text-purple-300 ring-1 ring-purple-500/40"
                          : "bg-white/5 text-zinc-600",
                    )}
                  >
                    {done ? <CheckCircle2 className="h-3 w-3" /> : i + 1}
                  </div>
                  <div>
                    <p
                      className={cn(
                        "text-xs font-semibold leading-none",
                        active ? "text-white" : done ? "text-zinc-400" : "text-zinc-600",
                      )}
                    >
                      {STEP_META[s].title}
                    </p>
                    <p className="text-[10px] text-zinc-600 mt-0.5 leading-none">
                      {STEP_META[s].subtitle}
                    </p>
                  </div>
                </div>
              );
            })}
          </nav>

          <div className="mt-auto">
            <p className="text-[10px] text-zinc-700 leading-relaxed">
              You can revisit setup anytime in Settings.
            </p>
          </div>
        </div>

        {/* Right panel — step content */}
        <div className="flex flex-col flex-1 min-w-0">
          <div className="flex-1 overflow-y-auto p-8">
            {step === "welcome" && <WelcomeStep />}
            {step === "dependencies" && (
              <DependenciesStep deps={deps} checking={checking} onRecheck={runCheck} />
            )}
            {step === "ready" && <ReadyStep />}
          </div>

          {/* Footer */}
          <div className="flex items-center justify-between px-8 py-5 border-t border-white/6">
            <div>
              {!isFirst && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={back}
                  className="text-zinc-500 hover:text-zinc-300"
                >
                  Back
                </Button>
              )}
            </div>
            <div className="flex items-center gap-3">
              {!isLast && (
                <button
                  onClick={complete}
                  className="text-xs text-zinc-600 hover:text-zinc-400 transition-colors"
                >
                  Skip for now
                </button>
              )}
              <Button
                onClick={isLast ? complete : next}
                disabled={step === "dependencies" && checking}
                className="bg-purple-600 hover:bg-purple-500 text-white gap-2"
              >
                {step === "dependencies" && checking ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : isLast ? (
                  <Rocket className="h-3.5 w-3.5" />
                ) : (
                  <ArrowRight className="h-3.5 w-3.5" />
                )}
                {isLast ? "Launch Unified Dev" : "Continue"}
              </Button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function WelcomeStep() {
  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-white leading-tight">
          Stop context-switching.
        </h1>
        <p className="text-sm text-zinc-400 mt-2 leading-relaxed">
          Issues, PRs, repositories and AI agents — one window, zero tabs.
        </p>
      </div>
      <div className="grid grid-cols-2 gap-2.5">
        {FEATURES.map((f) => (
          <div
            key={f.title}
            className="flex items-start gap-3 p-3.5 rounded-xl bg-white/[0.03] border border-white/[0.05] hover:border-white/10 transition-colors"
          >
            <div
              className={cn(
                "h-7 w-7 rounded-lg flex items-center justify-center shrink-0 mt-0.5",
                f.bg,
              )}
            >
              <f.icon className={cn("h-3.5 w-3.5", f.color)} />
            </div>
            <div className="min-w-0">
              <p className="text-xs font-bold text-white leading-none">{f.title}</p>
              <p className="text-[11px] text-zinc-500 mt-1 leading-relaxed">
                {f.description}
              </p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function DependenciesStep({
  deps,
  checking,
  onRecheck,
}: {
  deps: DependencyStatus[] | null;
  checking: boolean;
  onRecheck: () => void;
}) {
  const missingRequired = deps?.some((d) => !d.installed && !OPTIONAL.has(d.id));

  return (
    <div>
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-white leading-tight">
          Environment check
        </h2>
        <p className="text-sm text-zinc-400 mt-2 leading-relaxed">
          Unified Dev relies on a few CLI tools to run agents and manage PRs.
        </p>
      </div>

      <div className="flex flex-col gap-2">
        {checking || deps === null ? (
          Array.from({ length: 4 }).map((_, i) => (
            <div
              key={i}
              className="h-14 rounded-xl bg-white/[0.03] border border-white/[0.05] animate-pulse"
            />
          ))
        ) : (
          deps.map((dep) => <DependencyRow key={dep.id} dep={dep} />)
        )}
      </div>

      {deps !== null && (
        <div className="mt-4 flex items-center justify-between">
          <div className="flex items-center gap-1.5">
            {checking ? (
              <>
                <Loader2 className="h-3.5 w-3.5 text-zinc-500 shrink-0 animate-spin" />
                <p className="text-xs text-zinc-500">Checking...</p>
              </>
            ) : missingRequired ? (
              <>
                <TriangleAlert className="h-3.5 w-3.5 text-amber-400 shrink-0" />
                <p className="text-xs text-amber-400">
                  Some required tools are missing — you can install them and recheck.
                </p>
              </>
            ) : (
              <>
                <CheckCircle2 className="h-3.5 w-3.5 text-emerald-400 shrink-0" />
                <p className="text-xs text-emerald-400">
                  All required tools are ready.
                </p>
              </>
            )}
          </div>
          <button
            onClick={onRecheck}
            disabled={checking}
            className="flex items-center gap-1 text-[11px] text-zinc-500 hover:text-zinc-300 transition-colors shrink-0 ml-4 disabled:opacity-50 cursor-pointer disabled:cursor-not-allowed"
          >
            <RefreshCcw className={cn("h-3 w-3", checking && "animate-spin")} />
            Recheck
          </button>
        </div>
      )}
    </div>
  );
}

function DependencyRow({ dep }: { dep: DependencyStatus }) {
  const isOptional = OPTIONAL.has(dep.id);

  return (
    <div
      className={cn(
        "flex items-center justify-between px-4 py-3 rounded-xl border transition-colors",
        dep.installed
          ? "bg-emerald-500/5 border-emerald-500/15"
          : isOptional
            ? "bg-white/[0.02] border-white/[0.05]"
            : "bg-amber-500/5 border-amber-500/15",
      )}
    >
      <div className="flex items-center gap-3 min-w-0">
        {dep.installed ? (
          <CheckCircle2 className="h-4 w-4 text-emerald-400 shrink-0" />
        ) : (
          <XCircle
            className={cn(
              "h-4 w-4 shrink-0",
              isOptional ? "text-zinc-600" : "text-amber-400",
            )}
          />
        )}
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <p className="text-sm font-semibold text-white leading-none">
              {dep.label}
            </p>
            {isOptional && (
              <span className="text-[9px] font-black uppercase tracking-wider text-zinc-600 bg-white/5 px-1.5 py-0.5 rounded">
                Optional
              </span>
            )}
          </div>
          <p className="text-[11px] text-zinc-500 mt-0.5 truncate">
            {dep.installed
              ? dep.version ?? dep.path ?? "installed"
              : dep.id === "copilot"
                ? "Requires gh CLI — install or update it"
                : "Not found in PATH"}
          </p>
        </div>
      </div>
      {!dep.installed && INSTALL_URLS[dep.id] && (
        <button
          onClick={() => openUrl(INSTALL_URLS[dep.id])}
          className="text-xs text-purple-400 hover:text-purple-300 transition-colors font-semibold shrink-0 ml-4"
        >
          Install →
        </button>
      )}
    </div>
  );
}

function ReadyStep() {
  return (
    <div className="flex flex-col items-center justify-center text-center h-full py-8">
      <div className="h-16 w-16 rounded-2xl bg-purple-600/15 border border-purple-500/20 flex items-center justify-center mb-6">
        <Rocket className="h-7 w-7 text-purple-400" />
      </div>
      <h2 className="text-2xl font-bold text-white mb-2">Ready to launch</h2>
      <p className="text-sm text-zinc-400 leading-relaxed max-w-xs">
        Start by connecting a GitHub organization, then import your repositories.
        Agents and issues follow from there.
      </p>
      <div className="mt-8 grid grid-cols-3 gap-3 w-full max-w-xs text-center">
        {[
          { step: "1", label: "Add organization" },
          { step: "2", label: "Import repos" },
          { step: "3", label: "Run agents" },
        ].map((item) => (
          <div key={item.step} className="flex flex-col items-center gap-2 p-3 rounded-xl bg-white/[0.03] border border-white/[0.05]">
            <div className="h-6 w-6 rounded-full bg-purple-500/20 text-purple-400 text-xs font-black flex items-center justify-center">
              {item.step}
            </div>
            <p className="text-[11px] text-zinc-400 leading-tight">{item.label}</p>
          </div>
        ))}
      </div>
    </div>
  );
}
