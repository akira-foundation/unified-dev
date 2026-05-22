import type { ElementType } from "react";
import { CloudUpload, GitCommitHorizontal, GitPullRequest, Monitor } from "lucide-react";

export type HeaderAction = "merge_local" | "merge_push" | "draft_pr" | "create_pr" | "merge_commit";

export interface ActionConfig {
  label: string;
  description: string;
  icon: ElementType;
}

export function buildActionConfigs(t: (key: string) => string): Record<HeaderAction, ActionConfig> {
  return {
    merge_local: {
      label: t("agents.header.action.mergeLocal.label"),
      description: t("agents.header.action.mergeLocal.description"),
      icon: Monitor,
    },
    merge_push: {
      label: t("agents.header.action.mergePush.label"),
      description: t("agents.header.action.mergePush.description"),
      icon: CloudUpload,
    },
    draft_pr: {
      label: t("agents.header.action.draftPr.label"),
      description: t("agents.header.action.draftPr.description"),
      icon: GitPullRequest,
    },
    create_pr: {
      label: t("agents.header.action.createPr.label"),
      description: t("agents.header.action.createPr.description"),
      icon: GitPullRequest,
    },
    merge_commit: {
      label: t("agents.header.action.mergeCommit.label"),
      description: t("agents.header.action.mergeCommit.description"),
      icon: GitCommitHorizontal,
    },
  };
}
