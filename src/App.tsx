import { Building2, FolderGit2, LayoutDashboard, Settings } from "lucide-react";

import { AppContent } from "./components/layout/app-content";
import { AppShell } from "./components/layout/app-shell";
import { AppSidebar } from "./components/layout/sidebar";
import { DashboardPage } from "./pages/dashboard";
import { OrganizationsPage } from "./pages/organizations";
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

  const activeItem = navigationItems.find((item) => item.id === currentPage) ?? navigationItems[0];
  return (
    <AppShell variant="sidebar">
      <AppSidebar items={navigationItems} activeId={currentPage} onSelect={setCurrentPage} />
      <AppContent>
        <div className="mx-auto flex h-full w-full max-w-7xl flex-1 flex-col gap-4 p-4 md:p-8">
          {currentPage === "dashboard" && <DashboardPage />}
          {currentPage === "organizations" && <OrganizationsPage />}
          {currentPage === "repository" && <RepositoryPage />}
          {currentPage === "settings" && <SettingsPage />}
        </div>
      </AppContent>
    </AppShell>
  );
}
