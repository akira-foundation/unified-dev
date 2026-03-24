import { useQueryClient, useQuery, useMutation } from "@tanstack/react-query";

import { organizationService } from "../services/organizationService";
import { useNavigationStore } from "../stores/navigation-store";
import { queryKeys } from "../lib/query-keys";
import type { UpdateOrganizationInput } from "../types/organization";

export function useOrganizations() {
  const queryClient = useQueryClient();
  const { navigateTo, setActiveOrganizationId } = useNavigationStore();

  const { data: organizations = [], isLoading } = useQuery({
    queryKey: queryKeys.organizations(),
    queryFn: () => organizationService.listOrganizations(),
  });

  const createOrganization = useMutation({
    mutationFn: (input: { name: string; provider_id: string }) =>
      organizationService.createOrganization(input),
    onSuccess: (created) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.organizations() });
      setActiveOrganizationId(created.id);
      navigateTo("organization");
    },
  });

  const updateOrganization = useMutation({
    mutationFn: (input: UpdateOrganizationInput) =>
      organizationService.updateOrganization(input),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.organizations() });
    },
  });

  const removeOrganization = useMutation({
    mutationFn: (organizationId: string) =>
      organizationService.deleteOrganization(organizationId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.organizations() });
    },
  });

  return {
    organizations,
    isLoading,
    createOrganization: createOrganization.mutateAsync,
    updateOrganization: updateOrganization.mutateAsync,
    removeOrganization: removeOrganization.mutateAsync,
  };
}
