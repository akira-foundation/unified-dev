import { invoke } from "@tauri-apps/api/core";

import type {
  AttachRepoInput,
  CreateOrganizationInput,
  OrganizationRepoSummary,
  OrganizationSummary,
} from "../types/organization";

export const organizationService = {
  async listOrganizations(): Promise<OrganizationSummary[]> {
    return invoke<OrganizationSummary[]>("list_organizations");
  },
  async createOrganization(input: CreateOrganizationInput): Promise<OrganizationSummary> {
    return invoke<OrganizationSummary>("create_organization", { input });
  },
  async deleteOrganization(organizationId: string): Promise<void> {
    await invoke<void>("delete_organization", { organizationId });
  },
  async attachRepo(input: AttachRepoInput): Promise<OrganizationRepoSummary> {
    return invoke<OrganizationRepoSummary>("attach_repo_to_organization", { input });
  },
  async listOrganizationRepos(organizationId: string): Promise<OrganizationRepoSummary[]> {
    return invoke<OrganizationRepoSummary[]>("list_organization_repos", { organizationId });
  },
};
