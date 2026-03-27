export type ProviderKind = "github" | "gitlab" | "bitbucket";

export type ProviderOrgKind = "personal" | "organization";

export interface ProviderOrg {
  id: string;
  login: string;
  kind: ProviderOrgKind;
}

export interface ProviderSummary {
  id: string;
  name: string;
  kind: ProviderKind;
  created_at: string;
  account_login?: string;
  account_type?: string;
}

export type ProviderAuth = {
  auth_type: "pat";
  auth_payload: {
    token: string;
  };
};

export interface CreateProviderInput {
  name: string;
  kind: ProviderKind;
  auth: ProviderAuth;
}

export interface RateLimitResource {
  limit: number;
  used: number;
  remaining: number;
  reset: number;
}

export interface RateLimitDto {
  provider_id: string;
  provider_name: string;
  core: RateLimitResource;
  search: RateLimitResource;
  graphql: RateLimitResource;
}
