import type { ReactNode } from "react";

export type AppPage = "dashboard" | "providers" | "organization" | "import-repositories" | "repository" | "settings" | "agents" | "skills";

export interface NavItem {
  id: AppPage;
  label: string;
  icon: ReactNode;
}
