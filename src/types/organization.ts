export interface OrganizationSummary {
  id: string;
  name: string;
  provider_id: string;
  created_at: string;
}

export type ProviderAuth =
  | {
      auth_type: "pat";
      auth_payload: {
        token: string;
      };
    };

export interface CreateOrganizationInput {
  name: string;
  provider_id: string;
  auth: ProviderAuth;
}

export interface OrganizationRepoSummary {
  id: number;
  organization_id: string;
  owner: string;
  repo_name: string;
  auto_sync: boolean;
}

export interface AttachRepoInput {
  organization_id: string;
  owner: string;
  repo_name: string;
  auto_sync?: boolean;
}
