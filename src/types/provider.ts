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
