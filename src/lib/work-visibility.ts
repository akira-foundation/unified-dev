import type { OrganizationSummary } from "@/types/organization";
import type { ProviderSummary } from "@/types/provider";
import type { IssueScope, PullRequestScope } from "@/types/work-visibility";

export function resolveCurrentLogin(
  orgId: string,
  organizations: OrganizationSummary[],
  providers: ProviderSummary[],
): string | null {
  const organization = organizations.find((item) => item.id === orgId);
  if (!organization?.provider_id) {
    return null;
  }

  const provider = providers.find((item) => item.id === organization.provider_id);
  return provider?.account_login ?? null;
}

export function issueScopeLabelKey(scope: IssueScope): string {
  switch (scope) {
    case "all_open":
      return "visibility.issueScope.allOpen";
    case "all":
      return "visibility.issueScope.all";
    default:
      return "visibility.issueScope.myQueue";
  }
}

export function prScopeLabelKey(scope: PullRequestScope): string {
  switch (scope) {
    case "all_open":
      return "visibility.prScope.allOpen";
    default:
      return "visibility.prScope.mineOrReviewRequested";
  }
}
