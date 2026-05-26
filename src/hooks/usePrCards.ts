import { useMemo } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useQueries, useQuery } from "@tanstack/react-query";

import { repositorySelectionService } from "@/services/repositorySelectionService";
import { useFiltersStore } from "@/stores/filters-store";
import { useSettingsStore } from "@/stores/settings-store";
import { useOrganizations } from "@/hooks/useOrganizations";
import { useProviders } from "@/hooks/useProviders";
import { queryKeys } from "@/lib/query-keys";
import { resolveCurrentLogin } from "@/lib/work-visibility";
import { cache } from "@/config/cache";
import { mapPrToColumn, type PrColumnId } from "@/lib/pr-column";
import type { OrganizationRepoWithOrg, PullRequestDto } from "@/types/organization";

export const PR_FILTER_NS = "kanban-prs";

export interface PrCardType {
  id: string;
  pr: PullRequestDto;
  columnId: PrColumnId;
  repoName: string;
  owner: string;
  organizationId: string;
}

interface UsePrCardsResult {
  cards: PrCardType[];
  allPrs: PullRequestDto[];
  isLoading: boolean;
}

export function usePrCards(): UsePrCardsResult {
  const { organizations } = useOrganizations();
  const { providers } = useProviders();
  const { resolvePrScope } = useSettingsStore();

  const { data: allRepos = [], isLoading: reposLoading } = useQuery({
    queryKey: queryKeys.allRepositories(),
    queryFn: () => repositorySelectionService.listAllSelectedRepositories(),
    staleTime: cache.staleTime.short,
  });

  const prQueries = useQueries({
    queries: allRepos.map((repo: OrganizationRepoWithOrg) => ({
      queryKey: queryKeys.pullRequests(repo.organization_id, repo.repo_name, resolvePrScope(repo.organization_id, repo.repo_name)),
      queryFn: () =>
        invoke<PullRequestDto[]>("list_repo_pull_requests", {
          organizationId: repo.organization_id,
          repoName: repo.repo_name,
          scope: resolvePrScope(repo.organization_id, repo.repo_name),
          currentLogin: resolveCurrentLogin(repo.organization_id, organizations, providers),
        }),
      staleTime: cache.staleTime.short,
    })),
  });

  const isLoading = reposLoading || prQueries.some((q) => q.isLoading);

  const allCards = useMemo<PrCardType[]>(() => {
    return allRepos.flatMap((repo: OrganizationRepoWithOrg, idx: number) => {
      const prs = prQueries[idx]?.data ?? [];
      return prs
        .filter((pr) => pr.state === "open" || pr.merged_at !== null)
        .map((pr): PrCardType => ({
          id: `${repo.organization_id}:${repo.repo_name}:${pr.id}`,
          pr,
          columnId: mapPrToColumn(pr),
          repoName: repo.repo_name,
          owner: repo.owner,
          organizationId: repo.organization_id,
        }));
    });
  }, [allRepos, prQueries]);

  const allPrs = useMemo(() => allCards.map((c) => c.pr), [allCards]);

  const storeFilters = useFiltersStore((s) => s.filters[PR_FILTER_NS]);

  const cards = useMemo<PrCardType[]>(() => {
    const f = {
      state: storeFilters?.state ?? [],
      isDraft: storeFilters?.isDraft ?? [],
      author: storeFilters?.author ?? [],
      labels: storeFilters?.labels ?? [],
      ciStatus: storeFilters?.ciStatus ?? [],
      reviewers: storeFilters?.reviewers ?? [],
    };
    const draftsOnly = f.isDraft.includes("true");

    return allCards.filter(({ pr }) => {
      if (f.state.length > 0 && !f.state.includes(pr.merged_at ? "merged" : pr.state)) return false;
      if (draftsOnly && !pr.is_draft) return false;
      if (f.author.length > 0 && (!pr.author || !f.author.includes(pr.author))) return false;
      if (f.labels.length > 0 && !f.labels.some((l) => pr.labels.includes(l))) return false;
      if (f.ciStatus.length > 0 && (!pr.ci_status || !f.ciStatus.includes(pr.ci_status))) return false;
      if (f.reviewers.length > 0 && !f.reviewers.some((r) => pr.reviewers.includes(r))) return false;
      return true;
    });
  }, [allCards, storeFilters]);

  return { cards, allPrs, isLoading };
}
