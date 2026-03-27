export type IssueScope = "my_queue" | "all_open" | "all";

export type PullRequestScope = "mine_or_review_requested" | "all_open";

export interface ScopePreferenceMaps {
  organizationIssueScopes: Record<string, IssueScope>;
  organizationPrScopes: Record<string, PullRequestScope>;
  repositoryIssueScopes: Record<string, IssueScope>;
  repositoryPrScopes: Record<string, PullRequestScope>;
}

export const DEFAULT_ISSUE_SCOPE: IssueScope = "my_queue";
export const DEFAULT_PR_SCOPE: PullRequestScope = "mine_or_review_requested";

export function repositoryScopeKey(orgId: string, repoName: string): string {
  return `${orgId}:${repoName}`;
}
