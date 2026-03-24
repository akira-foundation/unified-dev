import { useMemo, useState } from "react";

import { useOrganizations } from "./useOrganizations";
import { useProviders } from "./useProviders";

export function useProviderHierarchy() {
  const { providers, isLoading: providersLoading, createProvider, removeProvider } = useProviders();
  const { organizations, isLoading: organizationsLoading, createOrganization, removeOrganization } = useOrganizations();

  const [providerDialogOpen, setProviderDialogOpen] = useState(false);
  const [organizationDialogOpen, setOrganizationDialogOpen] = useState(false);

  const providersWithOrganizations = useMemo(() => {
    return providers.map((provider) => ({
      ...provider,
      organizations: organizations.filter(
        (organization) => organization.provider_id === provider.id,
      ),
    }));
  }, [providers, organizations]);

  return {
    providers,
    organizations,
    providersWithOrganizations,
    providersLoading,
    organizationsLoading,
    createProvider,
    removeProvider,
    createOrganization,
    removeOrganization,
    providerDialogOpen,
    setProviderDialogOpen,
    organizationDialogOpen,
    setOrganizationDialogOpen,
  };
}
