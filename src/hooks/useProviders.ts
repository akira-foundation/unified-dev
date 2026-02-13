import { useCallback, useEffect, useState } from "react";

import { providerService } from "../services/providerService";
import type { ProviderKind, ProviderSummary } from "../types/provider";

export function useProviders() {
  const [providers, setProviders] = useState<ProviderSummary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isDialogOpen, setIsDialogOpen] = useState(false);

  const loadProviders = useCallback(async () => {
    setIsLoading(true);
    try {
      const data = await providerService.listProviders();
      setProviders(data);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    loadProviders();
  }, [loadProviders]);

  const createProvider = useCallback(async (input: { name: string; kind: ProviderKind; token: string }) => {
    const payload = {
      name: input.name,
      kind: input.kind,
      auth: {
        auth_type: "pat" as const,
        auth_payload: {
          token: input.token,
        },
      },
    };
    const created = await providerService.createProvider(payload);
    setProviders((prev) => [created, ...prev]);
  }, []);

  const removeProvider = useCallback(async (providerId: string) => {
    await providerService.deleteProvider(providerId);
    setProviders((prev) => prev.filter((provider) => provider.id !== providerId));
  }, []);

  return {
    providers,
    isLoading,
    isDialogOpen,
    setIsDialogOpen,
    createProvider,
    removeProvider,
    reload: loadProviders,
  };
}
