import { Bot, FolderGit2, LayoutDashboard, Server, Settings } from "lucide-react";

import { AppContent } from "./components/layout/app-content";
import { AppShell } from "./components/layout/app-shell";
import { AppHeader } from "./components/layout/app-header";
import { AppSidebar } from "./components/layout/sidebar";
import { AgentsSidebar } from "./components/agents/agents-sidebar";
import { AgentWorkspaceLayout } from "./components/agents/agent-workspace-layout";
import { Toaster } from "./components/ui/sonner";
import { DashboardPage } from "./pages/dashboard";
import { OrganizationPage } from "./pages/organization";
import { ProvidersPage } from "./pages/providers";
import { ImportRepositoriesPage } from "./pages/import-repositories";
import { RepositoryPage } from "./pages/repository";
import { SettingsPage } from "./pages/settings";
import { useNavigation } from "./hooks/useNavigation";
import { useNavigationStore } from "./stores/navigation-store";
import type { NavItem } from "./types/navigation";

const navigationItems: NavItem[] = [
  { id: "dashboard", label: "Dashboard", icon: <LayoutDashboard className="h-4 w-4" /> },
  { id: "repository", label: "Repositories", icon: <FolderGit2 className="h-4 w-4" /> },
  { id: "providers", label: "Providers", icon: <Server className="h-4 w-4" /> },
  { id: "agents", label: "Agents", icon: <Bot className="h-4 w-4" /> },
  { id: "settings", label: "Settings", icon: <Settings className="h-4 w-4" /> },
];

export default function App() {
  const { currentPage, navigateTo } = useNavigation("dashboard");
  const isAgentMode = useNavigationStore((state) => state.isAgentMode);

  return (
    <AppShell variant="sidebar">
      {isAgentMode ? (
        <AgentsSidebar />
      ) : (
        <AppSidebar items={navigationItems} activeId={currentPage} onSelect={navigateTo} />
      )}
      <AppContent className="flex h-svh flex-col overflow-hidden">
        {!isAgentMode && <AppHeader />}
        <main className="flex-1 overflow-y-auto custom-scrollbar">
          <div className={isAgentMode ? "h-full w-full" : "mx-auto min-h-full w-full max-w-7xl"}>
            {currentPage === "dashboard" && <DashboardPage />}
            {currentPage === "providers" && <ProvidersPage />}
            {currentPage === "organization" && <OrganizationPage />}
            {currentPage === "import-repositories" && <ImportRepositoriesPage />}
            {currentPage === "repository" && <RepositoryPage />}
            {currentPage === "settings" && <SettingsPage />}
            {currentPage === "agents" && <AgentWorkspaceLayout />}
          </div>
        </main>
        <Toaster richColors />
      </AppContent>
    </AppShell>
  );
}
