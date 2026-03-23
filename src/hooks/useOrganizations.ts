import { useCallback, useEffect, useState } from "react";

import { organizationService } from "../services/organizationService";
import { useNavigationStore } from "../stores/navigation-store";
import type { OrganizationSummary, UpdateOrganizationInput } from "../types/organization";

export function useOrganizations() {
  const [organizations, setOrganizations] = useState<OrganizationSummary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [editOrganization, setEditOrganization] = useState<OrganizationSummary | null>(null);
  const { navigateTo, setActiveOrganizationId } = useNavigationStore();

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
      navigateTo("organization");
    },
    [setActiveOrganizationId, navigateTo],
  );

  const updateOrganization = useCallback(async (input: UpdateOrganizationInput) => {
    const updated = await organizationService.updateOrganization(input);
    setOrganizations((prev) => prev.map((org) => (org.id === updated.id ? updated : org)));
  }, []);

  const removeOrganization = useCallback(async (organizationId: string) => {
    await organizationService.deleteOrganization(organizationId);
    setOrganizations((prev) => prev.filter((org) => org.id !== organizationId));
  }, []);

  return {
    organizations,
    isLoading,
    isDialogOpen,
    setIsDialogOpen,
    editOrganization,
    setEditOrganization,
    createOrganization,
    updateOrganization,
    removeOrganization,
    reload: loadOrganizations,
  };
}
