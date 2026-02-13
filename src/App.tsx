import { Building2, FolderGit2, LayoutDashboard, Settings } from "lucide-react";

import { AppContent } from "./components/layout/app-content";
import { AppShell } from "./components/layout/app-shell";
import { AppHeader } from "./components/layout/app-header";
import { AppSidebar } from "./components/layout/sidebar";
import { DashboardPage } from "./pages/dashboard";
import { OrganizationsPage } from "./pages/organizations";
import { OrganizationReposPage } from "./pages/organization-repos";
import { RepositoryPage } from "./pages/repository";
import { SettingsPage } from "./pages/settings";
import { useNavigation } from "./hooks/useNavigation";
import type { NavItem } from "./types/navigation";

const navigationItems: NavItem[] = [
  { id: "dashboard", label: "Dashboard", icon: <LayoutDashboard className="h-4 w-4" /> },
  { id: "organizations", label: "Organizations", icon: <Building2 className="h-4 w-4" /> },
  { id: "repository", label: "Repositories", icon: <FolderGit2 className="h-4 w-4" /> },
  { id: "settings", label: "Settings", icon: <Settings className="h-4 w-4" /> },
];

export default function App() {
  const { currentPage, setCurrentPage } = useNavigation("dashboard");

  return (
    <AppShell variant="sidebar">
      <AppSidebar items={navigationItems} activeId={currentPage} onSelect={setCurrentPage} />
      <AppContent className="flex h-svh flex-col overflow-hidden">
        <AppHeader />
        <main className="flex-1 overflow-y-auto custom-scrollbar">
          <div className="mx-auto min-h-full w-full max-w-7xl">
            {currentPage === "dashboard" && <DashboardPage />}
            {currentPage === "organizations" && <OrganizationsPage />}
            {currentPage === "organization-repos" && <OrganizationReposPage />}
            {currentPage === "repository" && <RepositoryPage />}
            {currentPage === "settings" && <SettingsPage />}
          </div>
        </main>
      </AppContent>
    </AppShell>
  );
}
