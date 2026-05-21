import { useMemo } from "react";

import { useFiltersStore } from "@/stores/filters-store";
import type { OrganizationSummary } from "@/types/organization";

export const ORG_FILTER_NS = "orgs";

export function useFilteredOrgs(
  orgs: OrganizationSummary[],
  providerNameById: Record<string, string>,
): OrganizationSummary[] {
  const f = useFiltersStore((s) => s.filters[ORG_FILTER_NS]);
  return useMemo(() => {
    const providers = f?.provider ?? [];
    if (providers.length === 0) return orgs;
    return orgs.filter((o) => {
      const name = o.provider_id ? providerNameById[o.provider_id] : undefined;
      return name ? providers.includes(name) : false;
    });
  }, [orgs, f, providerNameById]);
}
