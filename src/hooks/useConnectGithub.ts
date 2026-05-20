import { useQueryClient, useMutation } from "@tanstack/react-query";

import { providerService } from "../services/providerService";
import { queryKeys } from "../lib/query-keys";
import { useBrowserHandoffToast } from "./use-browser-handoff-toast";

export function useConnectGithub() {
  const queryClient = useQueryClient();
  const browserHandoffToast = useBrowserHandoffToast();

  const mutation = useMutation({
    mutationFn: async () => {
      const handoff = browserHandoffToast("Abrindo GitHub...");
      try {
        const created = await providerService.connectGithub();
        handoff.success("GitHub conectado");
        return created;
      } catch (error) {
        handoff.error(error, "Falha ao conectar GitHub");
        throw error;
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.providers() });
      queryClient.invalidateQueries({ queryKey: queryKeys.organizations() });
      queryClient.invalidateQueries({ queryKey: queryKeys.allRepositories() });
      queryClient.invalidateQueries({ queryKey: queryKeys.rateLimits() });
    },
  });

  return {
    connectGithub: mutation.mutateAsync,
    isConnectingGithub: mutation.isPending,
  };
}
