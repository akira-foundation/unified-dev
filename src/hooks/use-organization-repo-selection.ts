import { useCallback, useEffect, useState } from "react";

import { repositorySelectionService } from "../services/repositorySelectionService";
import type { ProviderRepo, SelectedRepositoryInput } from "../types/organization";

const repoKey = (repo: Pick<ProviderRepo, "owner" | "name">) => `${repo.owner}/${repo.name}`;

export function useOrganizationRepoSelection(organizationId: string | null) {
  const [repos, setRepos] = useState<ProviderRepo[]>([]);
  const [selectedKeys, setSelectedKeys] = useState<Set<string>>(new Set());
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

  const saveSelection = useCallback(async () => {
    if (!organizationId) return;

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
          default_branch: repo.default_branch,
        }));

      await repositorySelectionService.saveSelectedRepositories(organizationId, payload);
    } finally {
      setIsSaving(false);
    }
  }, [organizationId, repos, selectedKeys]);

  return {
    repos,
    selectedKeys,
    setSelectedKeys,
    isLoading,
    isSaving,
    saveSelection,
    reload: loadRepos,
  };
}
