import { useCallback, useEffect, useState } from "react";

import { toast } from "sonner";

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
    const auth = {
      auth_type: "pat" as const,
      auth_payload: {
        token: input.token,
      },
    };

    const toastId = toast.loading("Iniciando conexao...");
    try {
      toast.loading("Verificando conexao...", { id: toastId });
      await providerService.testConnection({ kind: input.kind, auth });
      toast.success("Conexao verificada com sucesso", { id: toastId });

      const payload = {
        name: input.name,
        kind: input.kind,
        auth,
      };
      const created = await providerService.createProvider(payload);
      setProviders((prev) => [created, ...prev]);
      toast.success("Provider salvo", { id: toastId });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Falha ao verificar conexao";
      toast.error(message, { id: toastId });
      throw error;
    }
  }, []);

  const updateProviderAuth = useCallback(async (input: { providerId: string; token: string }) => {
    const toastId = toast.loading("Atualizando token...");
    try {
      await providerService.updateProviderAuth(input);
      toast.success("Token atualizado", { id: toastId });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Falha ao atualizar token";
      toast.error(message, { id: toastId });
      throw error;
    }
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
    updateProviderAuth,
    removeProvider,
    reload: loadProviders,
  };
}
