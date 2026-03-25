export const queryKeys = {
  organizations: () => ["organizations"] as const,
  providers: () => ["providers"] as const,
  selectedRepositories: (orgId: string) => ["selected-repos", orgId] as const,
  providerOrganizations: (providerId: string) => ["provider-orgs", providerId] as const,
  providerRepositories: (providerId: string, scope: string, orgLogin?: string) =>
    ["provider-repos", providerId, scope, orgLogin] as const,
  pullRequests: (orgId: string, repo: string) => ["pull-requests", orgId, repo] as const,
  prComments: (orgId: string, repo: string, prNumber: number) =>
    ["pr-comments", orgId, repo, prNumber] as const,
  prFiles: (orgId: string, repo: string, prNumber: number) =>
    ["pr-files", orgId, repo, prNumber] as const,
  prChecks: (orgId: string, repo: string, headSha: string) =>
    ["pr-checks", orgId, repo, headSha] as const,
  jobLogs: (orgId: string, repo: string, jobId: number) =>
    ["job-logs", orgId, repo, jobId] as const,
  skills: () => ["skills"] as const,
  allRepositories: () => ["all-repositories"] as const,
  issues: (orgId: string, repo: string) => ["issues", orgId, repo] as const,
  issueDetail: (orgId: string, repo: string, number: number) =>
    ["issue-detail", orgId, repo, number] as const,
  branches: (orgId: string, repo: string) => ["branches", orgId, repo] as const,
};
