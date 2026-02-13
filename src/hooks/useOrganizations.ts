import { useCallback, useEffect, useState } from "react";

import { organizationService } from "../services/organizationService";
import type { CreateOrganizationInput, OrganizationSummary } from "../types/organization";

export function useOrganizations() {
  const [organizations, setOrganizations] = useState<OrganizationSummary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isDialogOpen, setIsDialogOpen] = useState(false);

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

  const createOrganization = useCallback(async (input: CreateOrganizationInput) => {
    const created = await organizationService.createOrganization(input);
    setOrganizations((prev) => [created, ...prev]);
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
    createOrganization,
    removeOrganization,
    reload: loadOrganizations,
  };
}
