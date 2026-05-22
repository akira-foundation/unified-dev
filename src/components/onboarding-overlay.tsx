import { useEffect, useState, type ReactNode } from "react";
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
import { useLicenseStore } from "@/stores/license-store";

interface DependencyStatus {
  id: string;
  label: string;
  installed: boolean;
  version: string | null;
  path: string | null;
}

const OPTIONAL = new Set(["codex", "copilot", "gemini"]);

const INSTALL_URLS: Record<string, string> = {
  claude: "https://docs.anthropic.com/en/docs/claude-code",
  gh: "https://cli.github.com",
  codex: "https://github.com/openai/codex",
  copilot: "https://cli.github.com",
  gemini: "https://github.com/google-gemini/gemini-cli",
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
        description: "Delegate issues to Claude, Gemini, Codex or Copilot",
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

const STEPS = ["welcome", "dependencies", "auth", "ready"] as const;
type Step = (typeof STEPS)[number];

const STEP_META: Record<Step, { title: string; subtitle: string }> = {
  welcome: { title: "Welcome", subtitle: "What's inside" },
  dependencies: { title: "Environment", subtitle: "CLI tools" },
  auth: { title: "Sign in", subtitle: "Connect provider" },
  ready: { title: "Ready", subtitle: "Let's go" },
};

interface OauthLoginResult {
  customer_id: string;
  customer_email: string;
  customer_name: string | null;
  entitlement: { plan_key: string | null; source: string; ends_at: string | null } | null;
  requires_plan_selection: boolean;
}

export function OnboardingOverlay() {
  const { complete, authOnly, clearRequireAuth } = useOnboardingStore();
  const [step, setStep] = useState<Step>(authOnly ? "auth" : "welcome");

  const [deps, setDeps] = useState<DependencyStatus[] | null>(null);
  const [checking, setChecking] = useState(false);
  const [authResult, setAuthResult] = useState<OauthLoginResult | null>(null);
  const [authing, setAuthing] = useState(false);
  const [authError, setAuthError] = useState<string | null>(null);

  useEffect(() => {
    if (deps === null) runCheck();
  }, []);

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

  async function handleOauth(provider: string) {
    setAuthing(true);
    setAuthError(null);
    try {
      const result = await invoke<OauthLoginResult>("oauth_login", { provider });
      setAuthResult(result);
      await useLicenseStore.getState().load();
      await useLicenseStore.getState().verify();
      if (authOnly) {
        clearRequireAuth();
        return;
      }
      next();
    } catch (err) {
      setAuthError(err instanceof Error ? err.message : String(err));
    } finally {
      setAuthing(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-md">
      <div className="relative flex w-full max-w-3xl mx-4 rounded-2xl border border-border bg-card shadow-2xl overflow-hidden min-h-[500px]">

        <div className="w-56 shrink-0 bg-gradient-to-b from-purple-500/10 to-card dark:from-purple-950/60 dark:to-zinc-950 border-r border-border flex flex-col p-6">
          <div className="flex items-center gap-2.5 mb-8">
            <div className="h-8 w-8 rounded-lg bg-[#7c3aed] flex items-center justify-center shrink-0 shadow-lg shadow-purple-900/40">
              <Layers className="h-4 w-4 text-white" />
            </div>
            <span className="text-xs font-black uppercase tracking-widest text-purple-300">
              Unified Dev
            </span>
          </div>

          <nav className="flex flex-col gap-1">
            {STEPS.map((s, i) => {
              const done = i < stepIndex;
              const active = s === step;
              return (
                <div
                  key={s}
                  className={cn(
                    "flex items-center gap-3 px-3 py-2.5 rounded-lg transition-colors",
                    active && "bg-accent",
                  )}
                >
                  <div
                    className={cn(
                      "h-5 w-5 rounded-full flex items-center justify-center shrink-0 text-[10px] font-black transition-colors",
                      done
                        ? "bg-purple-500 text-white"
                        : active
                          ? "bg-purple-500/20 text-purple-300 ring-1 ring-purple-500/40"
                          : "bg-muted text-muted-foreground",
                    )}
                  >
                    {done ? <CheckCircle2 className="h-3 w-3" /> : i + 1}
                  </div>
                  <div>
                    <p
                      className={cn(
                        "text-xs font-semibold leading-none",
                        active ? "text-foreground" : done ? "text-muted-foreground" : "text-muted-foreground",
                      )}
                    >
                      {STEP_META[s].title}
                    </p>
                    <p className="text-[10px] text-muted-foreground mt-0.5 leading-none">
                      {STEP_META[s].subtitle}
                    </p>
                  </div>
                </div>
              );
            })}
          </nav>

          <div className="mt-auto">
            <p className="text-[10px] text-muted-foreground leading-relaxed">
              You can revisit setup anytime in Settings.
            </p>
          </div>
        </div>

        <div className="flex flex-col flex-1 min-w-0">
          <div key={step} className="flex-1 overflow-y-auto p-8 animate-in fade-in slide-in-from-right-2 duration-200">
            {step === "welcome" && <WelcomeStep />}
            {step === "dependencies" && (
              <DependenciesStep deps={deps} checking={checking} onRecheck={runCheck} />
            )}
            {step === "auth" && (
              <AuthStep
                authing={authing}
                authError={authError}
                authResult={authResult}
                onOauth={handleOauth}
              />
            )}
            {step === "ready" && <ReadyStep authResult={authResult} />}
          </div>

          <div className="flex items-center justify-between px-8 py-5 border-t border-border">
            <div>
              {!isFirst && !authOnly && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={back}
                  className="text-muted-foreground hover:text-foreground"
                >
                  Back
                </Button>
              )}
            </div>
            <div className="flex items-center gap-3">
              {!isLast && step !== "auth" && !authOnly && (
                <button
                  onClick={complete}
                  className="text-xs text-muted-foreground hover:text-muted-foreground transition-colors"
                >
                  Skip for now
                </button>
              )}
              {step !== "auth" && !authOnly && (
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
              )}
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
        <h1 className="text-2xl font-bold text-foreground leading-tight">
          Stop context-switching.
        </h1>
        <p className="text-sm text-muted-foreground mt-2 leading-relaxed">
          Issues, PRs, repositories and AI agents — one window, zero tabs.
        </p>
      </div>
      <div className="grid grid-cols-2 gap-2.5">
        {FEATURES.map((f) => (
          <div
            key={f.title}
            className="flex items-start gap-3 p-3.5 rounded-xl bg-muted/50 border border-border hover:border-foreground/20 transition-colors"
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
              <p className="text-xs font-bold text-foreground leading-none">{f.title}</p>
              <p className="text-[11px] text-muted-foreground mt-1 leading-relaxed">
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
        <h2 className="text-2xl font-bold text-foreground leading-tight">
          Environment check
        </h2>
        <p className="text-sm text-muted-foreground mt-2 leading-relaxed">
          Unified Dev relies on a few CLI tools to run agents and manage PRs.
        </p>
      </div>

      <div className="flex flex-col gap-2">
        {checking || deps === null ? (
          Array.from({ length: 4 }).map((_, i) => (
            <div
              key={i}
              className="h-14 rounded-xl bg-muted/50 border border-border animate-pulse"
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
                <Loader2 className="h-3.5 w-3.5 text-muted-foreground shrink-0 animate-spin" />
                <p className="text-xs text-muted-foreground">Checking...</p>
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
            className="flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors shrink-0 ml-4 disabled:opacity-50 cursor-pointer disabled:cursor-not-allowed"
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
            ? "bg-muted/40 border-border"
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
              isOptional ? "text-muted-foreground" : "text-amber-400",
            )}
          />
        )}
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <p className="text-sm font-semibold text-foreground leading-none">
              {dep.label}
            </p>
            {isOptional && (
              <span className="text-[9px] font-black uppercase tracking-wider text-muted-foreground bg-muted px-1.5 py-0.5 rounded">
                Optional
              </span>
            )}
          </div>
          <p className="text-[11px] text-muted-foreground mt-0.5 truncate">
              {dep.installed
              ? dep.version ?? dep.path ?? "installed"
              : dep.id === "copilot"
                ? "Requires gh CLI — install or update it"
                : dep.id === "gemini"
                  ? "Optional — needed for Gemini models (Google One)"
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

interface OauthProviderDto {
  provider: string;
  label: string;
  scopes: string[];
}

const PROVIDER_ICON: Record<string, ReactNode> = {
  github: (
    <svg className="h-5 w-5 text-foreground shrink-0" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M12 0C5.37 0 0 5.37 0 12c0 5.3 3.44 9.8 8.21 11.39.6.11.82-.26.82-.58v-2.02c-3.34.73-4.04-1.61-4.04-1.61-.55-1.39-1.34-1.76-1.34-1.76-1.09-.74.08-.73.08-.73 1.2.08 1.84 1.24 1.84 1.24 1.07 1.84 2.81 1.31 3.5 1 .11-.78.42-1.31.76-1.61-2.67-.3-5.47-1.33-5.47-5.93 0-1.31.47-2.38 1.24-3.22-.13-.31-.54-1.53.11-3.18 0 0 1.01-.32 3.31 1.23a11.5 11.5 0 016.02 0c2.3-1.55 3.31-1.23 3.31-1.23.65 1.65.24 2.87.12 3.18.77.84 1.23 1.91 1.23 3.22 0 4.61-2.81 5.62-5.49 5.92.43.37.81 1.1.81 2.22v3.29c0 .32.21.69.83.58A12 12 0 0024 12c0-6.63-5.37-12-12-12z" />
    </svg>
  ),
  gitlab: (
    <svg className="h-5 w-5 shrink-0" viewBox="0 0 24 24" fill="#FC6D26" aria-hidden>
      <path d="M23.6 9.6L23.6 9.5 20.3 1.1c-.1-.2-.2-.3-.4-.4-.2-.1-.4-.1-.6 0-.2.1-.3.2-.4.4l-2.3 6.9H7.4L5.1 1.1c-.1-.2-.2-.3-.4-.4-.2-.1-.4-.1-.6 0-.2.1-.3.2-.4.4L.4 9.5v.1c-.4 1.1 0 2.3.9 3l10.4 7.5L22.6 12.5c1-.7 1.4-1.9 1-3z" />
    </svg>
  ),
  bitbucket: (
    <svg className="h-5 w-5 shrink-0" viewBox="0 0 24 24" fill="#2684FF" aria-hidden>
      <path d="M.78 1.5C.347 1.495-.012 1.84 0 2.273c0 .033 0 .066.008.099l3.264 19.812c.067.405.42.704.83.706h15.65c.308.004.574-.216.626-.52l3.264-19.99c.066-.426-.225-.825-.65-.891-.034-.005-.067-.008-.1-.008zM14.55 15.7H9.46l-1.38-7.207h7.764z" />
    </svg>
  ),
  google: (
    <svg className="h-5 w-5 shrink-0" viewBox="0 0 24 24" aria-hidden>
      <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
      <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
      <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
      <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
    </svg>
  ),
  apple: (
    <svg className="h-5 w-5 text-foreground shrink-0" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z"/>
    </svg>
  ),
  microsoft: (
    <svg className="h-5 w-5 shrink-0" viewBox="0 0 24 24" aria-hidden>
      <path fill="#F25022" d="M1 1h10v10H1z"/>
      <path fill="#7FBA00" d="M13 1h10v10H13z"/>
      <path fill="#00A4EF" d="M1 13h10v10H1z"/>
      <path fill="#FFB900" d="M13 13h10v10H13z"/>
    </svg>
  ),
};

function AuthStep({
  authing,
  authError,
  authResult,
  onOauth,
}: {
  authing: boolean;
  authError: string | null;
  authResult: { customer_email: string; customer_name: string | null } | null;
  onOauth: (provider: string) => void;
}) {
  const [providers, setProviders] = useState<OauthProviderDto[]>([]);
  const [loadingProviders, setLoadingProviders] = useState(true);
  const [activeProvider, setActiveProvider] = useState<string | null>(null);

  useEffect(() => {
    if (!authing) setActiveProvider(null);
  }, [authing]);

  useEffect(() => {
    invoke<OauthProviderDto[]>("list_oauth_providers")
      .then((list) => setProviders(list))
      .catch(() => setProviders([{ provider: "github", label: "GitHub", scopes: [] }]))
      .finally(() => setLoadingProviders(false));
  }, []);
  if (authResult) {
    return (
      <div className="flex flex-col h-full">
        <div className="mb-6">
          <h2 className="text-2xl font-bold text-foreground leading-tight">
            Signed in
          </h2>
          <p className="text-sm text-muted-foreground mt-2 leading-relaxed">
            Linked to {authResult.customer_email}. You're ready to import repos and run agents.
          </p>
        </div>
        <div className="flex items-center gap-3 rounded-xl border border-emerald-500/20 bg-emerald-500/5 px-4 py-3">
          <CheckCircle2 className="h-5 w-5 text-emerald-400 shrink-0" />
          <div className="min-w-0">
            <p className="text-sm font-semibold text-foreground truncate">
              {authResult.customer_name ?? authResult.customer_email}
            </p>
            <p className="text-[11px] text-muted-foreground truncate">{authResult.customer_email}</p>
          </div>
        </div>
      </div>
    );
  }

  const sortedProviders = [...providers].sort((a, b) => {
    if (a.provider === "github") return -1;
    if (b.provider === "github") return 1;
    return a.label.localeCompare(b.label);
  });

  return (
    <div className="flex flex-col h-full">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-foreground leading-tight">
          Sign in to Unified Dev
        </h2>
        <p className="text-sm text-muted-foreground mt-2 leading-relaxed">
          One account for repos, agents and sync — across every Akira app.
        </p>
      </div>

      <div className="flex flex-col gap-2.5">
        {loadingProviders ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-5 w-5 text-muted-foreground animate-spin" />
          </div>
        ) : providers.length === 0 ? (
          <p className="text-[12px] text-muted-foreground text-center py-4">
            No login providers configured.
          </p>
        ) : (
          sortedProviders.map((p) => {
            const isThisLoading = authing && activeProvider === p.provider;
            return (
              <button
                key={p.provider}
                onClick={() => {
                  setActiveProvider(p.provider);
                  onOauth(p.provider);
                }}
                disabled={authing}
                className="group flex items-center gap-3 rounded-xl border border-border bg-muted/50 px-4 py-3 text-left transition-colors hover:border-border hover:bg-accent disabled:cursor-not-allowed disabled:opacity-60"
              >
                {isThisLoading ? (
                  <Loader2 className="h-5 w-5 text-muted-foreground shrink-0 animate-spin" />
                ) : (
                  PROVIDER_ICON[p.provider] ?? <span className="h-5 w-5 shrink-0" />
                )}
                <p className="text-sm font-semibold text-foreground flex-1 min-w-0">
                  Continue with {p.label}
                </p>
                <ArrowRight className="h-4 w-4 text-muted-foreground shrink-0 group-hover:text-foreground transition-colors" />
              </button>
            );
          })
        )}
      </div>

      {authError ? (
        <div className="mt-3 flex items-start gap-2 rounded-lg border border-rose-500/30 bg-rose-500/5 px-3 py-2">
          <XCircle className="h-3.5 w-3.5 text-rose-400 shrink-0 mt-0.5" />
          <p className="text-[11px] text-rose-300 leading-relaxed">{authError}</p>
        </div>
      ) : null}

      <div className="mt-auto pt-6 border-t border-border">
        <p className="text-[11px] text-muted-foreground leading-relaxed">
          We never see your password. Tokens stay encrypted on your device.
        </p>
      </div>
    </div>
  );
}

function ReadyStep({ authResult }: { authResult: { customer_email: string; entitlement: { plan_key: string | null } | null } | null }) {
  const planLabel = authResult?.entitlement?.plan_key ?? "free";
  return (
    <div className="flex flex-col items-center justify-center text-center h-full py-8">
      <div className="h-16 w-16 rounded-2xl bg-purple-600/15 border border-purple-500/20 flex items-center justify-center mb-6">
        <Rocket className="h-7 w-7 text-purple-400" />
      </div>
      <h2 className="text-2xl font-bold text-foreground mb-2">Ready to launch</h2>
      <p className="text-sm text-muted-foreground leading-relaxed max-w-xs">
        {authResult ? (
          <>
            Signed in as <span className="text-foreground">{authResult.customer_email}</span>{" "}
            on the <span className="text-purple-300 font-semibold">{planLabel}</span> plan.
          </>
        ) : (
          <>Start by connecting a GitHub organization, then import your repositories. Agents and issues follow from there.</>
        )}
      </p>
      <div className="mt-8 grid grid-cols-3 gap-3 w-full max-w-xs text-center">
        {[
          { step: "1", label: "Add organization" },
          { step: "2", label: "Import repos" },
          { step: "3", label: "Run agents" },
        ].map((item) => (
          <div key={item.step} className="flex flex-col items-center gap-2 p-3 rounded-xl bg-muted/50 border border-border">
            <div className="h-6 w-6 rounded-full bg-purple-500/20 text-purple-400 text-xs font-black flex items-center justify-center">
              {item.step}
            </div>
            <p className="text-[11px] text-muted-foreground leading-tight">{item.label}</p>
          </div>
        ))}
      </div>
    </div>
  );
}
