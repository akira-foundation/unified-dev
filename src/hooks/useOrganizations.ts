import { useCallback, useEffect, useState } from "react";

import { organizationService } from "../services/organizationService";
import { useNavigationStore } from "../stores/navigation-store";
import type { OrganizationSummary } from "../types/organization";

export function useOrganizations() {
  const [organizations, setOrganizations] = useState<OrganizationSummary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const { setCurrentPage, setActiveOrganizationId } = useNavigationStore();

  const loadOrganizations = useCallback(async () => {
    setIsLoading(true);
    try {
      const data = await organizationService.listOrganizations();
      setOrganizations(data);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    loadOrganizations();
  }, [loadOrganizations]);

  const createOrganization = useCallback(
    async (input: { name: string; provider_id: string }) => {
      const created = await organizationService.createOrganization(input);
      setOrganizations((prev) => [created, ...prev]);
      setActiveOrganizationId(created.id);
      setCurrentPage("organization");
    },
    [setActiveOrganizationId, setCurrentPage],
  );

  const removeOrganization = useCallback(async (organizationId: string) => {
    await organizationService.deleteOrganization(organizationId);
    setOrganizations((prev) => prev.filter((org) => org.id !== organizationId));
  }, []);

  return {
    organizations,
    isLoading,
    isDialogOpen,
    setIsDialogOpen,
    createOrganization,
    removeOrganization,
    reload: loadOrganizations,
  };
}
