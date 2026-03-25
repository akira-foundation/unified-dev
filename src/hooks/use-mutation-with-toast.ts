import { useMutation, useQueryClient, type InvalidateQueryFilters, type UseMutationOptions } from "@tanstack/react-query";
import { toast } from "sonner";

interface MutationWithToastOptions<TData, TVariables> {
  mutationFn: (variables: TVariables) => Promise<TData>;
  loadingMessage: string;
  successMessage: string | ((data: TData, variables: TVariables) => string);
  invalidateKeys?: InvalidateQueryFilters[];
  onSuccess?: (data: TData, variables: TVariables) => void;
  onError?: (error: unknown, variables: TVariables) => void;
  options?: Omit<UseMutationOptions<TData, unknown, TVariables>, "mutationFn" | "onSuccess" | "onError">;
}

export function useMutationWithToast<TData = unknown, TVariables = void>({
  mutationFn,
  loadingMessage,
  successMessage,
  invalidateKeys,
  onSuccess,
  onError,
  options,
}: MutationWithToastOptions<TData, TVariables>) {
  const queryClient = useQueryClient();

  return useMutation<TData, unknown, TVariables>({
    ...options,
    mutationFn: async (variables) => {
      const id = toast.loading(loadingMessage);
      try {
        const data = await mutationFn(variables);
        const message = typeof successMessage === "function"
          ? successMessage(data, variables)
          : successMessage;
        toast.success(message, { id });
        return data;
      } catch (error) {
        toast.error(error instanceof Error ? error.message : String(error), { id });
        throw error;
      }
    },
    onSuccess: (data, variables) => {
      if (invalidateKeys) {
        for (const key of invalidateKeys) {
          void queryClient.invalidateQueries(key);
        }
      }
      onSuccess?.(data, variables);
    },
    onError: (error, variables) => {
      onError?.(error, variables);
    },
  });
}
