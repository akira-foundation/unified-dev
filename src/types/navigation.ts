import type { ReactNode } from "react";

export type AppPage = "dashboard" | "organizations" | "repository" | "settings";

export interface NavItem {
  id: AppPage;
  label: string;
  icon: ReactNode;
}
