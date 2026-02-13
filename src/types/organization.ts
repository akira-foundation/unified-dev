export interface OrganizationSummary {
  id: string;
  name: string;
  created_at: string;
}

export interface CreateOrganizationInput {
  name: string;
  token: string;
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
