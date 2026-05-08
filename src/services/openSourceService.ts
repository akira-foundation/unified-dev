import { invoke } from "@tauri-apps/api/core";

import type {
  ContributedRepo,
  ContributionCalendarDay,
  ContributionSummary,
  OssFilters,
  OssIssue,
  OssPullRequest,
  OssReview,
  OssSyncResult,
  YearOverview,
} from "@/types/openSource";

export const openSourceService = {
  fetchSummary: () =>
    invoke<ContributionSummary>("fetch_github_contribution_summary"),

  fetchRepositories: (filters: OssFilters = {}) =>
    invoke<ContributedRepo[]>("fetch_github_contributed_repositories", { filters }),

  fetchPullRequests: (filters: OssFilters = {}) =>
    invoke<OssPullRequest[]>("fetch_github_pull_requests", { filters }),

  fetchIssues: (filters: OssFilters = {}) =>
    invoke<OssIssue[]>("fetch_github_issues", { filters }),

  fetchReviews: (filters: OssFilters = {}) =>
    invoke<OssReview[]>("fetch_github_reviews", { filters }),

  fetchCalendar: (year?: number) =>
    invoke<ContributionCalendarDay[]>("fetch_github_contribution_calendar", { year }),

  fetchYearOverview: (year: number) =>
    invoke<YearOverview>("fetch_github_year_overview", { year }),

  sync: () => invoke<OssSyncResult>("sync_github_open_source_contributions"),
};
