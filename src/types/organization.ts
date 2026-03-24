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

export interface PullRequestDto {
  id: string;
  number: number;
  title: string;
  state: string;
  url: string;
  head: string;
  base: string;
  updated_at: string;
  is_draft: boolean;
  merged_at: string | null;
  body: string | null;
  author: string | null;
  labels: string[];
  reviewers: string[];
}

export interface PrCommentDto {
  id: string;
  author: string;
  body: string;
  created_at: string;
}

export type PrReviewEvent = "approve" | "request_changes" | "comment";

export type PrMergeStrategy = "merge" | "squash" | "rebase";

export interface PrFileDto {
  filename: string;
  status: string;
  additions: number;
  deletions: number;
  patch: string | null;
}
