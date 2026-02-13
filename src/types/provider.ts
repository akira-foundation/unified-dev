export type ProviderKind = "github" | "gitlab" | "bitbucket";

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
