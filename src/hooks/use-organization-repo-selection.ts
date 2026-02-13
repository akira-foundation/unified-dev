import { useCallback, useEffect, useMemo, useState } from "react";

import { repositorySelectionService } from "../services/repositorySelectionService";
import type { ProviderRepo, SelectedRepositoryInput } from "../types/organization";

export type VisibilityFilter = "all" | "public" | "private";

const repoKey = (repo: Pick<ProviderRepo, "owner" | "name">) => `${repo.owner}/${repo.name}`;

export function useOrganizationRepoSelection(organizationId: string | null) {
  const [repos, setRepos] = useState<ProviderRepo[]>([]);
  const [selectedKeys, setSelectedKeys] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState("");
  const [visibility, setVisibility] = useState<VisibilityFilter>("all");
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);

  const loadRepos = useCallback(async () => {
    if (!organizationId) {
      setRepos([]);
      setSelectedKeys(new Set());
      return;
    }

    setIsLoading(true);
    try {
      const [repoList, selected] = await Promise.all([
        repositorySelectionService.fetchOrganizationRepositories(organizationId),
        repositorySelectionService.listSelectedRepositories(organizationId),
      ]);
      const selectedSet = new Set(selected.map((repo) => `${repo.owner}/${repo.repo_name}`));

      setRepos(repoList);
      setSelectedKeys(new Set(repoList.filter((repo) => selectedSet.has(repoKey(repo))).map(repoKey)));
    } finally {
      setIsLoading(false);
    }
  }, [organizationId]);

  useEffect(() => {
    void loadRepos();
  }, [loadRepos]);

  const filteredRepos = useMemo(() => {
    return repos.filter((repo) => {
      const matchesSearch = repo.name.toLowerCase().includes(search.toLowerCase()) ||
        repo.owner.toLowerCase().includes(search.toLowerCase());
      const matchesVisibility =
        visibility === "all" || repo.visibility.toLowerCase() === visibility;

      return matchesSearch && matchesVisibility;
    });
  }, [repos, search, visibility]);

  const selectedCount = selectedKeys.size;

  const toggleRepo = useCallback((repo: ProviderRepo) => {
    setSelectedKeys((prev) => {
      const next = new Set(prev);
      const key = repoKey(repo);
      if (next.has(key)) {
        next.delete(key);
      } else {
        next.add(key);
      }
      return next;
    });
  }, []);

  const selectAllVisible = useCallback(() => {
    setSelectedKeys((prev) => {
      const next = new Set(prev);
      filteredRepos.forEach((repo) => next.add(repoKey(repo)));
      return next;
    });
  }, [filteredRepos]);

  const clearAllVisible = useCallback(() => {
    setSelectedKeys((prev) => {
      const next = new Set(prev);
      filteredRepos.forEach((repo) => next.delete(repoKey(repo)));
      return next;
    });
  }, [filteredRepos]);

  const saveSelection = useCallback(async () => {
    if (!organizationId) {
      return;
    }

    setIsSaving(true);
    try {
      const payload: SelectedRepositoryInput[] = repos
        .filter((repo) => selectedKeys.has(repoKey(repo)))
        .map((repo) => ({
          owner: repo.owner,
          repo_name: repo.name,
          visibility: repo.visibility,
          is_selected: true,
          auto_sync: true,
        }));

      await repositorySelectionService.saveSelectedRepositories(organizationId, payload);
    } finally {
      setIsSaving(false);
    }
  }, [organizationId, repos, selectedKeys]);

  return {
    repos,
    filteredRepos,
    selectedKeys,
    search,
    visibility,
    isLoading,
    isSaving,
    selectedCount,
    setSearch,
    setVisibility,
    toggleRepo,
    selectAllVisible,
    clearAllVisible,
    saveSelection,
    reload: loadRepos,
  };
}
