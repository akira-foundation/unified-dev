import { useEffect, useState } from "react";
import { useQueryClient, useQuery, useMutation } from "@tanstack/react-query";
import { listen } from "@tauri-apps/api/event";

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

  useEffect(() => {
    const unlisten = listen<{ kind: string; orgId: string }>("sync:completed", (event) => {
      const { orgId } = event.payload;
      queryClient.invalidateQueries({ queryKey: queryKeys.organizations() });
      setSyncingIds((prev) => new Set(prev).add(orgId));
      setTimeout(() => {
        setSyncingIds((prev) => {
          const next = new Set(prev);
          next.delete(orgId);
          return next;
        });
      }, 2000);
    });
    return () => { unlisten.then((fn) => fn()); };
  }, [queryClient]);

  const [syncingIds, setSyncingIds] = useState<Set<string>>(new Set());

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
    syncingIds,
    createOrganization: createOrganization.mutateAsync,
    updateOrganization: updateOrganization.mutateAsync,
    removeOrganization: removeOrganization.mutateAsync,
  };
}
