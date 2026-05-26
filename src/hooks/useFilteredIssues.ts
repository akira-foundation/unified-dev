import { useMemo } from "react";

import { useFiltersStore } from "@/stores/filters-store";
import type { IssueDto } from "@/types/issue";

export function useFilteredIssues(issues: IssueDto[], namespace: string): IssueDto[] {
  const f = useFiltersStore((s) => s.filters[namespace]);
  return useMemo(() => {
    if (!f) return issues;
    return issues.filter((issue) => {
      if ((f.statuses?.length ?? 0) > 0 && !f.statuses.includes(issue.status)) return false;
      if ((f.providers?.length ?? 0) > 0 && !f.providers.includes(issue.provider)) return false;
      if ((f.sources?.length ?? 0) > 0 && !f.sources.includes(issue.syncWithProvider ? "synced" : "local")) return false;
      if ((f.labels?.length ?? 0) > 0 && !f.labels.some((l) => issue.labels.includes(l))) return false;
      if ((f.assignees?.length ?? 0) > 0 && !f.assignees.some((a) => issue.assignees.includes(a))) return false;
      if ((f.repos?.length ?? 0) > 0 && !f.repos.includes(issue.containerName ?? issue.repoName)) return false;
      if ((f.projects?.length ?? 0) > 0 && !f.projects.includes(issue.projectName ?? "No project")) return false;
      return true;
    });
  }, [issues, f]);
}
