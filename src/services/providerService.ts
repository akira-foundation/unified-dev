import { invoke } from "@tauri-apps/api/core";

import type { CreateProviderInput, ProviderSummary } from "../types/provider";

export const providerService = {
  async listProviders(): Promise<ProviderSummary[]> {
    return invoke<ProviderSummary[]>("list_providers");
  },
  async createProvider(input: CreateProviderInput): Promise<ProviderSummary> {
    return invoke<ProviderSummary>("create_provider", { input });
  },
  async deleteProvider(providerId: string): Promise<void> {
    await invoke<void>("delete_provider", { providerId });
  },
};
