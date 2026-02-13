import { useMemo } from "react";

import { useOrganizations } from "./useOrganizations";
import { useProviders } from "./useProviders";

export function useProviderHierarchy() {
  const providersState = useProviders();
  const organizationsState = useOrganizations();

  const providersWithOrganizations = useMemo(() => {
    return providersState.providers.map((provider) => ({
      ...provider,
      organizations: organizationsState.organizations.filter(
        (organization) => organization.provider_id === provider.id,
      ),
    }));
  }, [providersState.providers, organizationsState.organizations]);

  return {
    providers: providersState.providers,
    organizations: organizationsState.organizations,
    providersWithOrganizations,
    providersLoading: providersState.isLoading,
    organizationsLoading: organizationsState.isLoading,
    createProvider: providersState.createProvider,
    removeProvider: providersState.removeProvider,
    createOrganization: organizationsState.createOrganization,
    removeOrganization: organizationsState.removeOrganization,
    providerDialogOpen: providersState.isDialogOpen,
    setProviderDialogOpen: providersState.setIsDialogOpen,
    organizationDialogOpen: organizationsState.isDialogOpen,
    setOrganizationDialogOpen: organizationsState.setIsDialogOpen,
  };
}
