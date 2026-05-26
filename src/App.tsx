import { useCallback, useEffect, useRef, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { toast } from "sonner";
import { cn } from "@/lib/utils";

import { AppContent } from "./components/layout/app-content";
import { AppShell } from "./components/layout/app-shell";
import { AppHeader } from "./components/layout/app-header";
import { AppSidebar } from "./components/layout/sidebar";
import { AgentsSidebar } from "./components/agents/agents-sidebar";
import { AgentWorkspaceLayout } from "./components/agents/agent-workspace-layout";
import { Toaster } from "./components/ui/sonner";
import { CommandPalette } from "./components/layout/command-palette";
import { SearchOverlay } from "./components/layout/search-overlay";
import { LicenseActivationDialog } from "./components/license-activation-dialog";
import { OnboardingOverlay } from "./components/onboarding-overlay";
import { UpgradeModal } from "./components/upgrade-modal";
import { useOnboardingStore } from "./stores/onboarding-store";
import { useLicenseStore } from "./stores/license-store";
import { DashboardPage } from "./pages/dashboard";
import { OrganizationPage } from "./pages/organization";
import { OrganizationsPage } from "./pages/organizations";
import { ImportRepositoriesPage } from "./pages/import-repositories";
import { RepositoryPage } from "./pages/repository";
import { RepositoryPRsPage } from "./pages/repository-prs";
import { RepositoryDetailPage } from "./pages/repository-detail";
import { PrDetailPage } from "./pages/pr-detail";
import { SettingsPage } from "./pages/settings";
import { NotificationsPage } from "./pages/notifications";
import { ProviderDetailPage } from "./pages/provider-detail";
import { Bot, Building2, CircleDot, FolderGit2, FolderKanban, GitFork, GitPullRequest, LayoutDashboard, Settings } from "lucide-react";
import { useNavigation } from "./hooks/useNavigation";
import { useNavigationStore } from "./stores/navigation-store";
import { useAgentsStore } from "./stores/useAgentsStore";
import { useAutopilotStore } from "./stores/useAutopilotStore";
import { IssuesPage } from "./pages/issues";
import { IssueDetailPage } from "./pages/issue-detail";
import { ProjectsPage } from "./pages/projects";
import { PrsPage } from "./pages/prs";
import { OpenSourcePage } from "./pages/open-source";
import type { NavItem } from "./types/navigation";

const navigationItems: NavItem[] = [
  { id: "dashboard", label: "Dashboard", icon: <LayoutDashboard className="h-4 w-4" />, section: "workspace" },
  { id: "agents", label: "Agents", icon: <Bot className="h-4 w-4" />, section: "workspace" },
  { id: "issues", label: "Issues", icon: <CircleDot className="h-4 w-4" />, section: "workspace" },
  { id: "projects", label: "Projects", icon: <FolderKanban className="h-4 w-4" />, section: "workspace" },
  { id: "prs", label: "Pull Requests", icon: <GitPullRequest className="h-4 w-4" />, section: "workspace" },
  { id: "open-source", label: "Open Source", icon: <GitFork className="h-4 w-4" />, section: "workspace" },
  { id: "repository", label: "Repositories", icon: <FolderGit2 className="h-4 w-4" />, section: "browse" },
  { id: "organizations", label: "Organizations", icon: <Building2 className="h-4 w-4" />, section: "browse" },
  { id: "settings", label: "Settings", icon: <Settings className="h-4 w-4" /> },
];

export default function App() {
  const { currentPage, navigateTo } = useNavigation("dashboard");
  const isAgentMode = useNavigationStore((state) => state.isAgentMode);
  const onboardingCompleted = useOnboardingStore((s) => s.completed);
  const onboardingAuthOnly = useOnboardingStore((s) => s.authOnly);
  const requireOnboardingAuth = useOnboardingStore((s) => s.requireAuth);
  const loadRepositories = useAgentsStore((state) => state.loadRepositories);
  const loadAiProviders = useAgentsStore((state) => state.loadAiProviders);
  const loadAutopilotJobs = useAutopilotStore((state) => state.loadJobs);
  const verifyLicense = useLicenseStore((s) => s.verify);
  const lastVerifyRef = useRef(0);
  const [activationSessionId, setActivationSessionId] = useState<string | null>(null);

  const verifyThrottled = useCallback(() => {
    const now = Date.now();
    if (now - lastVerifyRef.current < 30_000) return;
    lastVerifyRef.current = now;
    void verifyLicense();
  }, [verifyLicense]);

  useEffect(() => {
    loadRepositories();
    loadAiProviders();
    loadAutopilotJobs();
  }, []);

  useEffect(() => {
    if (!onboardingCompleted) return;
    void (async () => {
      try {
        const authed = await invoke<boolean>("is_authenticated");
        if (!authed) {
          requireOnboardingAuth();
          return;
        }
        lastVerifyRef.current = Date.now();
        void verifyLicense();
      } catch {
      }
    })();

    const onVisible = () => {
      if (document.visibilityState === "visible") verifyThrottled();
    };
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("online", verifyThrottled);
    const unlistenFocus = getCurrentWindow().onFocusChanged(({ payload: focused }) => {
      if (focused) verifyThrottled();
    });
    const interval = setInterval(verifyThrottled, 30 * 60 * 1000);

    return () => {
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("online", verifyThrottled);
      void unlistenFocus.then((fn) => fn());
      clearInterval(interval);
    };
  }, [onboardingCompleted, verifyLicense, verifyThrottled]);

  useEffect(() => {
    const unlisten = listen<string>("license://activate", (event) => {
      setActivationSessionId(event.payload);
    });
    return () => { unlisten.then((fn) => fn()); };
  }, []);

  useEffect(() => {
    const unlisten = listen<{ tool: string; current: string; latest: string; command: string }>(
      "app-update-available",
      (event) => {
        const { tool, current, latest, command } = event.payload;
        toast.warning(`${tool} update available: ${current} → ${latest}`, {
          id: `update-${tool}`,
          description: `Run: ${command}`,
          duration: 10000,
        });
      }
    );
    return () => { unlisten.then((fn) => fn()); };
  }, []);

  return (
    <AppShell variant="sidebar">
      {isAgentMode ? (
        <AgentsSidebar />
      ) : (
        <AppSidebar items={navigationItems} activeId={currentPage} onSelect={navigateTo} />
      )}
      <AppContent className="flex h-svh flex-col overflow-hidden">
        <AppHeader />
        <main className={cn(
          "flex-1 custom-scrollbar",
          isAgentMode ? "h-full overflow-hidden" : "overflow-y-auto"
        )}>
          <div className={cn(
            isAgentMode ? "h-full w-full" : "min-h-full w-full"
          )}>
            <div className={cn("h-full w-full", !isAgentMode && "hidden")}>
              <AgentWorkspaceLayout />
            </div>
            {!isAgentMode && currentPage === "dashboard" && <DashboardPage />}
            {!isAgentMode && currentPage === "issues" && <IssuesPage />}
            {!isAgentMode && currentPage === "projects" && <ProjectsPage />}
            {!isAgentMode && currentPage === "issue-detail" && <IssueDetailPage />}
            {!isAgentMode && currentPage === "prs" && <PrsPage />}
            {!isAgentMode && currentPage === "open-source" && <OpenSourcePage />}
            {!isAgentMode && currentPage === "organizations" && <OrganizationsPage />}
            {!isAgentMode && currentPage === "organization" && <OrganizationPage />}
            {!isAgentMode && currentPage === "import-repositories" && <ImportRepositoriesPage />}
            {!isAgentMode && currentPage === "repository" && <RepositoryPage />}
            {!isAgentMode && currentPage === "repository-prs" && <RepositoryPRsPage />}
            {!isAgentMode && currentPage === "repository-detail" && <RepositoryDetailPage />}
            {!isAgentMode && (currentPage === "pr-review" || currentPage === "pr-detail") && <PrDetailPage />}
            {!isAgentMode && currentPage === "settings" && <SettingsPage />}
            {!isAgentMode && currentPage === "notifications" && <NotificationsPage />}
            {!isAgentMode && currentPage === "provider-detail" && <ProviderDetailPage />}
          </div>
        </main>
        <Toaster richColors />
        <CommandPalette />
        <SearchOverlay />
        <UpgradeModal />
        <LicenseActivationDialog
          open={activationSessionId !== null}
          initialSessionId={activationSessionId ?? ""}
          onClose={() => setActivationSessionId(null)}
        />
        {(!onboardingCompleted || onboardingAuthOnly) && <OnboardingOverlay />}
      </AppContent>
    </AppShell>
  );
}
