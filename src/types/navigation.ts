import type { ReactNode } from "react";

export type AppPage = "dashboard" | "organizations" | "organization" | "import-repositories" | "repository" | "settings" | "agents" | "skills" | "provider-detail";

export interface NavItem {
  id: AppPage;
  label: string;
  icon: ReactNode;
}
