import type { ReactNode } from "react";

export type AppPage = "dashboard" | "organizations" | "organization" | "import-repositories" | "repository" | "repository-prs" | "repository-detail" | "settings" | "agents" | "skills" | "provider-detail" | "pr-review" | "issues" | "issue-detail";

export interface NavItem {
  id: AppPage;
  label: string;
  icon: ReactNode;
}
