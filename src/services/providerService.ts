import { invoke } from "@tauri-apps/api/core";

import type { CreateProviderInput, ProviderOrg, ProviderSummary } from "../types/provider";
import type { ProviderRepo } from "../types/organization";

export const providerService = {
  async listProviders(): Promise<ProviderSummary[]> {
    return invoke<ProviderSummary[]>("list_providers");
  },
  async updateProviderAuth(input: { providerId: string; token: string }): Promise<void> {
    await invoke<void>("update_provider_auth", {
      input: {
        provider_id: input.providerId,
        auth: {
          auth_type: "pat",
          auth_payload: { token: input.token },
        },
      },
    });
  },
  async listProviderOrganizations(providerId: string): Promise<ProviderOrg[]> {
    return invoke<ProviderOrg[]>("list_provider_organizations", { providerId });
  },
  async listProviderRepositories(input: {
    providerId: string;
    scope: "personal" | "organization";
    organizationLogin?: string;
  }): Promise<ProviderRepo[]> {
    return invoke<ProviderRepo[]>("list_provider_repositories", {
      input: {
        provider_id: input.providerId,
        scope: input.scope,
        organization_login: input.organizationLogin,
      },
    });
  },
  async testConnection(input: { kind: string; auth: { auth_type: "pat"; auth_payload: { token: string } } }): Promise<void> {
    await invoke<void>("test_provider_connection", { input });
  },
  async createProvider(input: CreateProviderInput): Promise<ProviderSummary> {
    return invoke<ProviderSummary>("create_provider", { input });
  },
  async deleteProvider(providerId: string): Promise<void> {
    await invoke<void>("delete_provider", { providerId });
  },
};
