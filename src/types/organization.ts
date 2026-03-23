export interface OrganizationSummary {
  id: string;
  name: string;
  provider_id: string | null;
  created_at: string;
}

export interface CreateOrganizationInput {
  name: string;
  provider_id: string;
}

export interface UpdateOrganizationInput {
  id: string;
  name: string;
  provider_id: string | null;
}

export interface OrganizationRepoSummary {
  id: number;
  organization_id: string;
  owner: string;
  repo_name: string;
  visibility: string;
  is_selected: boolean;
  auto_sync: boolean;
  default_branch: string;
  open_prs_count: number;
  created_at: string;
}

export interface OrganizationRepoWithOrg extends OrganizationRepoSummary {
  organization_name: string;
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
  default_branch: string;
}

export interface SelectedRepositoryInput {
  owner: string;
  repo_name: string;
  visibility: string;
  is_selected: boolean;
  auto_sync?: boolean;
  default_branch?: string;
}
