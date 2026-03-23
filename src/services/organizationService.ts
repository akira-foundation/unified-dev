import { invoke } from "@tauri-apps/api/core";

import type { CreateOrganizationInput, OrganizationSummary, UpdateOrganizationInput } from "../types/organization";

export const organizationService = {
  async listOrganizations(): Promise<OrganizationSummary[]> {
    return invoke<OrganizationSummary[]>("list_organizations");
  },
  async createOrganization(input: CreateOrganizationInput): Promise<OrganizationSummary> {
    return invoke<OrganizationSummary>("create_organization", { input });
  },
  async updateOrganization(input: UpdateOrganizationInput): Promise<OrganizationSummary> {
    return invoke<OrganizationSummary>("update_organization", { input });
  },
  async deleteOrganization(organizationId: string): Promise<void> {
    await invoke<void>("delete_organization", { organizationId });
  },
  async listOrganizationsByProvider(providerId: string): Promise<OrganizationSummary[]> {
    return invoke<OrganizationSummary[]>("list_organizations_by_provider", { providerId });
  },
};
