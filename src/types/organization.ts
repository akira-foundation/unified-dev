export interface OrganizationSummary {
  id: string;
  name: string;
  provider_id: string;
  created_at: string;
}

export interface CreateOrganizationInput {
  name: string;
  provider_id: string;
}

export interface OrganizationRepoSummary {
  id: number;
  organization_id: string;
  owner: string;
  repo_name: string;
  visibility: string;
  is_selected: boolean;
  auto_sync: boolean;
  created_at: string;
}

export interface AttachRepoInput {
  organization_id: string;
  owner: string;
  repo_name: string;
  visibility?: string;
  is_selected?: boolean;
  auto_sync?: boolean;
}

export interface ProviderRepo {
  id: string;
  owner: string;
  name: string;
  visibility: string;
  is_private: boolean;
}

export interface SelectedRepositoryInput {
  owner: string;
  repo_name: string;
  visibility: string;
  is_selected: boolean;
  auto_sync?: boolean;
}
