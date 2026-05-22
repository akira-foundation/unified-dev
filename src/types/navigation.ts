import type { ReactNode } from "react";

export type AppPage =
  | "dashboard"
  | "organizations"
  | "organization"
  | "import-repositories"
  | "prs"
  | "repository"
  | "repository-prs"
  | "repository-detail"
  | "settings"
  | "agents"
  | "skills"
  | "provider-detail"
  | "pr-review"
  | "pr-detail"
  | "issues"
  | "issue-detail"
  | "open-source"
  | "notifications";

export type NavBadgeTone = "red" | "green" | "amber" | "blue" | "muted";

export interface NavBadge {
  text: string | number;
  tone?: NavBadgeTone;
}

export type NavSection = "workspace" | "browse";

export interface NavItem {
  id: AppPage;
  label: string;
  icon: ReactNode;
  section?: NavSection;
  badge?: NavBadge;
}

export interface NavRecentItem {
  id: string;
  label: string;
  page: AppPage;
  tone?: NavBadgeTone;
  payload?: Record<string, unknown>;
}
