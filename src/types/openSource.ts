export interface OssProfile {
  login: string;
  name?: string | null;
  avatarUrl?: string | null;
  bio?: string | null;
  followers: number;
  following: number;
}

export interface OssTotals {
  repositories: number;
  pullRequests: number;
  mergedPullRequests: number;
  commits: number;
  issues: number;
  reviews: number;
  organizations: number;
}

export interface OssStreaks {
  current: number;
  best: number;
}

export interface OssOrgSummary {
  login: string;
  avatarUrl?: string | null;
  url: string;
}

export interface ActivityBreakdown {
  commits: number;
  pullRequests: number;
  issues: number;
  codeReview: number;
}

export interface ContributionSummary {
  profile: OssProfile;
  totals: OssTotals;
  streaks: OssStreaks;
  mostActiveLanguage?: string | null;
  mostActiveRepo?: string | null;
  lastSyncedAt?: string | null;
  connected: boolean;
  years: number[];
  organizationsList: OssOrgSummary[];
  activityBreakdown: ActivityBreakdown;
  contributedReposPreview: string[];
  contributedReposTotal: number;
}

export interface ContributedRepo {
  id: string;
  nameWithOwner: string;
  ownerLogin: string;
  description?: string | null;
  primaryLanguage?: string | null;
  stars: number;
  forks: number;
  url: string;
  isFork: boolean;
  isArchived: boolean;
  lastContributionAt?: string | null;
}

export type OssPullRequestState = "OPEN" | "MERGED" | "CLOSED";

export interface OssPullRequest {
  id: string;
  repoId: string;
  nameWithOwner: string;
  number: number;
  title: string;
  state: OssPullRequestState;
  merged: boolean;
  url: string;
  additions: number;
  deletions: number;
  createdAt: string;
  mergedAt?: string | null;
  closedAt?: string | null;
}

export type OssIssueState = "OPEN" | "CLOSED";

export interface OssIssue {
  id: string;
  repoId: string;
  nameWithOwner: string;
  number: number;
  title: string;
  state: OssIssueState;
  url: string;
  commentsCount: number;
  createdAt: string;
  closedAt?: string | null;
}

export type OssReviewState = "APPROVED" | "CHANGES_REQUESTED" | "COMMENTED" | "DISMISSED";

export interface OssReview {
  id: string;
  repoId: string;
  nameWithOwner: string;
  prNumber: number;
  prTitle?: string | null;
  state: OssReviewState;
  url: string;
  submittedAt: string;
}

export interface ContributionCalendarDay {
  date: string;
  count: number;
  color?: string | null;
}

export type OssContributionType = "pr" | "issue" | "review" | "commit";

export interface OssFilters {
  year?: number;
  org?: string;
  repo?: string;
  type?: OssContributionType;
  state?: string;
}

export interface YearOverview {
  year: number;
  breakdown: ActivityBreakdown;
  organizations: OssOrgSummary[];
  reposPreview: string[];
  reposTotal: number;
}

export interface OssSyncResult {
  synced: boolean;
  lastSyncedAt?: string | null;
  repositories: number;
  pullRequests: number;
  issues: number;
  reviews: number;
}
