import { useMemo } from "react";

import { useFiltersStore } from "@/stores/filters-store";
import type { OrganizationRepoWithOrg } from "@/types/organization";

export function useFilteredRepos(repos: OrganizationRepoWithOrg[], namespace: string): OrganizationRepoWithOrg[] {
  const f = useFiltersStore((s) => s.filters[namespace]);
  return useMemo(() => {
    if (!f) return repos;
    const visibility = f.visibility ?? [];
    const organizations = f.organizations ?? [];
    const defaultBranch = f.defaultBranch ?? [];
    const hasOpenPrs = (f.hasOpenPrs ?? []).includes("true");
    return repos.filter((r) => {
      if (visibility.length > 0 && !visibility.includes(r.visibility)) return false;
      if (organizations.length > 0 && !organizations.includes(r.organization_name)) return false;
      if (defaultBranch.length > 0 && !defaultBranch.includes(r.default_branch)) return false;
      if (hasOpenPrs && (r.open_prs_count ?? 0) === 0) return false;
      return true;
    });
  }, [repos, f]);
}
