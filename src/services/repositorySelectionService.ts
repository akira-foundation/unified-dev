import { invoke } from "@tauri-apps/api/core";

import type { OrganizationRepoSummary, OrganizationRepoWithOrg, ProviderRepo, SelectedRepositoryInput } from "../types/organization";

export const repositorySelectionService = {
  async fetchOrganizationRepositories(organizationId: string): Promise<ProviderRepo[]> {
    return invoke<ProviderRepo[]>("fetch_organization_repositories", { organizationId });
  },
  async saveSelectedRepositories(organizationId: string, repoList: SelectedRepositoryInput[]): Promise<void> {
    await invoke<void>("save_selected_repositories", { organizationId, repoList });
  },
  async listSelectedRepositories(organizationId: string): Promise<OrganizationRepoSummary[]> {
    return invoke<OrganizationRepoSummary[]>("list_selected_repositories", { organizationId });
  },
  async listAllSelectedRepositories(): Promise<OrganizationRepoWithOrg[]> {
    return invoke<OrganizationRepoWithOrg[]>("list_all_selected_repositories");
  },
};
