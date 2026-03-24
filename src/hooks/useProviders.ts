import { useQueryClient, useQuery, useMutation } from "@tanstack/react-query";
import { toast } from "sonner";

import { providerService } from "../services/providerService";
import { queryKeys } from "../lib/query-keys";
import type { ProviderKind } from "../types/provider";

export function useProviders() {
  const queryClient = useQueryClient();

  const { data: providers = [], isLoading } = useQuery({
    queryKey: queryKeys.providers(),
    queryFn: () => providerService.listProviders(),
  });

  const createProvider = useMutation({
    mutationFn: async (input: { name: string; kind: ProviderKind; token: string }) => {
      const auth = {
        auth_type: "pat" as const,
        auth_payload: { token: input.token },
      };
      const toastId = toast.loading("Iniciando conexao...");
      try {
        toast.loading("Verificando conexao...", { id: toastId });
        await providerService.testConnection({ kind: input.kind, auth });
        toast.success("Conexao verificada com sucesso", { id: toastId });
        const created = await providerService.createProvider({
          name: input.name,
          kind: input.kind,
          auth,
        });
        toast.success("Provider salvo", { id: toastId });
        return created;
      } catch (error) {
        const message = error instanceof Error ? error.message : "Falha ao verificar conexao";
        toast.error(message, { id: toastId });
        throw error;
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.providers() });
    },
  });

  const updateProviderAuth = useMutation({
    mutationFn: async (input: { providerId: string; token: string }) => {
      const toastId = toast.loading("Atualizando token...");
      try {
        await providerService.updateProviderAuth(input);
        toast.success("Token atualizado", { id: toastId });
      } catch (error) {
        const message = error instanceof Error ? error.message : "Falha ao atualizar token";
        toast.error(message, { id: toastId });
        throw error;
      }
    },
  });

  const removeProvider = useMutation({
    mutationFn: ({ providerId, keepOrganizations }: { providerId: string; keepOrganizations: boolean }) =>
      providerService.deleteProvider(providerId, keepOrganizations),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.providers() });
    },
  });

  const connectGithub = useMutation({
    mutationFn: async () => {
      const toastId = toast.loading("Abrindo GitHub...");
      try {
        const created = await providerService.connectGithub();
        toast.success("GitHub conectado", { id: toastId });
        return created;
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        toast.error(message, { id: toastId });
        throw error;
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.providers() });
    },
  });

  return {
    providers,
    isLoading,
    createProvider: createProvider.mutateAsync,
    updateProviderAuth: updateProviderAuth.mutateAsync,
    removeProvider: (providerId: string, keepOrganizations: boolean) =>
      removeProvider.mutateAsync({ providerId, keepOrganizations }),
    connectGithub: connectGithub.mutateAsync,
  };
}
