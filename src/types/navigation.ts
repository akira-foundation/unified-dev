import type { ReactNode } from "react";

export type AppPage = "dashboard" | "organizations" | "organization" | "import-repositories" | "repository" | "repository-prs" | "settings" | "agents" | "skills" | "provider-detail" | "pr-review";

export interface NavItem {
  id: AppPage;
  label: string;
  icon: ReactNode;
}
