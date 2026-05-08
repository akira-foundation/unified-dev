use serde::Deserialize;

pub const VIEWER_QUERY: &str = r#"
query Viewer {
  viewer {
    login
    name
    avatarUrl
    bio
    followers { totalCount }
    following { totalCount }
  }
}
"#;

#[derive(Debug, Deserialize)]
pub struct ViewerData {
    pub viewer: Viewer,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Viewer {
    pub login: String,
    pub name: Option<String>,
    pub avatar_url: Option<String>,
    pub bio: Option<String>,
    pub followers: TotalCount,
    pub following: TotalCount,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TotalCount {
    pub total_count: i64,
}

pub const CONTRIBUTIONS_QUERY: &str = r#"
query Contributions($from: DateTime!, $to: DateTime!) {
  viewer {
    contributionsCollection(from: $from, to: $to) {
      totalCommitContributions
      totalIssueContributions
      totalPullRequestContributions
      totalPullRequestReviewContributions
      totalRepositoriesWithContributedCommits
      totalRepositoriesWithContributedIssues
      totalRepositoriesWithContributedPullRequests
      totalRepositoriesWithContributedPullRequestReviews
      contributionCalendar {
        totalContributions
        weeks {
          contributionDays {
            date
            contributionCount
            color
          }
        }
      }
      commitContributionsByRepository(maxRepositories: 10) {
        repository { nameWithOwner url }
        contributions { totalCount }
      }
    }
  }
}
"#;

#[derive(Debug, Deserialize)]
pub struct ContributionsData {
    pub viewer: ContributionsViewer,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContributionsViewer {
    pub contributions_collection: ContributionsCollection,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContributionsCollection {
    pub total_commit_contributions: i64,
    pub total_issue_contributions: i64,
    pub total_pull_request_contributions: i64,
    pub total_pull_request_review_contributions: i64,
    pub total_repositories_with_contributed_commits: i64,
    pub total_repositories_with_contributed_issues: i64,
    pub total_repositories_with_contributed_pull_requests: i64,
    pub total_repositories_with_contributed_pull_request_reviews: i64,
    pub contribution_calendar: ContributionCalendar,
    pub commit_contributions_by_repository: Vec<CommitContributionByRepo>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContributionCalendar {
    pub total_contributions: i64,
    pub weeks: Vec<CalendarWeek>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CalendarWeek {
    pub contribution_days: Vec<CalendarDay>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CalendarDay {
    pub date: String,
    pub contribution_count: i64,
    pub color: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CommitContributionByRepo {
    pub repository: RepoRef,
    pub contributions: TotalCount,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepoRef {
    pub name_with_owner: String,
    pub url: String,
}

pub const REPOS_CONTRIBUTED_QUERY: &str = r#"
query ReposContributedTo($after: String) {
  viewer {
    repositoriesContributedTo(
      first: 100
      after: $after
      includeUserRepositories: false
      contributionTypes: [COMMIT, PULL_REQUEST, ISSUE, PULL_REQUEST_REVIEW]
    ) {
      pageInfo { hasNextPage endCursor }
      totalCount
      nodes {
        id
        nameWithOwner
        owner { login avatarUrl url }
        description
        primaryLanguage { name }
        stargazerCount
        forkCount
        url
        isFork
        isArchived
        pushedAt
      }
    }
  }
}
"#;

#[derive(Debug, Deserialize)]
pub struct ReposContributedData {
    pub viewer: ReposViewer,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReposViewer {
    pub repositories_contributed_to: ReposConnection,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReposConnection {
    pub page_info: PageInfo,
    pub total_count: i64,
    pub nodes: Vec<Option<RepoNode>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PageInfo {
    pub has_next_page: bool,
    pub end_cursor: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepoNode {
    pub id: String,
    pub name_with_owner: String,
    pub owner: RepoOwner,
    pub description: Option<String>,
    pub primary_language: Option<RepoLanguage>,
    pub stargazer_count: i64,
    pub fork_count: i64,
    pub url: String,
    pub is_fork: bool,
    pub is_archived: bool,
    pub pushed_at: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepoOwner {
    pub login: String,
    pub avatar_url: Option<String>,
    pub url: String,
}

#[derive(Debug, Deserialize)]
pub struct RepoLanguage {
    pub name: String,
}

pub const PULL_REQUESTS_QUERY: &str = r#"
query PullRequests($after: String) {
  viewer {
    pullRequests(
      first: 100
      after: $after
      states: [OPEN, MERGED, CLOSED]
      orderBy: { field: CREATED_AT, direction: DESC }
    ) {
      pageInfo { hasNextPage endCursor }
      nodes {
        id
        number
        title
        state
        merged
        url
        additions
        deletions
        createdAt
        mergedAt
        closedAt
        repository {
          id
          nameWithOwner
          description
          primaryLanguage { name }
          stargazerCount
          forkCount
          url
          isFork
          isArchived
          pushedAt
          owner { login avatarUrl url }
        }
      }
    }
  }
}
"#;

#[derive(Debug, Deserialize)]
pub struct PullRequestsData {
    pub viewer: PullRequestsViewer,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PullRequestsViewer {
    pub pull_requests: PrConnection,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PrConnection {
    pub page_info: PageInfo,
    pub nodes: Vec<Option<PrNode>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PrNode {
    pub id: String,
    pub number: i64,
    pub title: String,
    pub state: String,
    pub merged: bool,
    pub url: String,
    pub additions: i64,
    pub deletions: i64,
    pub created_at: String,
    pub merged_at: Option<String>,
    pub closed_at: Option<String>,
    pub repository: SimpleRepoRef,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SimpleRepoRef {
    pub id: String,
    pub name_with_owner: String,
    pub description: Option<String>,
    pub primary_language: Option<RepoLanguage>,
    pub stargazer_count: i64,
    pub fork_count: i64,
    pub url: String,
    pub is_fork: bool,
    pub is_archived: bool,
    pub pushed_at: Option<String>,
    pub owner: RepoOwner,
}

pub const ISSUES_QUERY: &str = r#"
query Issues($after: String) {
  viewer {
    issues(
      first: 100
      after: $after
      orderBy: { field: CREATED_AT, direction: DESC }
    ) {
      pageInfo { hasNextPage endCursor }
      nodes {
        id
        number
        title
        state
        url
        comments { totalCount }
        createdAt
        closedAt
        repository {
          id
          nameWithOwner
          description
          primaryLanguage { name }
          stargazerCount
          forkCount
          url
          isFork
          isArchived
          pushedAt
          owner { login avatarUrl url }
        }
      }
    }
  }
}
"#;

#[derive(Debug, Deserialize)]
pub struct IssuesData {
    pub viewer: IssuesViewer,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IssuesViewer {
    pub issues: IssueConnection,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IssueConnection {
    pub page_info: PageInfo,
    pub nodes: Vec<Option<IssueNode>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IssueNode {
    pub id: String,
    pub number: i64,
    pub title: String,
    pub state: String,
    pub url: String,
    pub comments: TotalCount,
    pub created_at: String,
    pub closed_at: Option<String>,
    pub repository: SimpleRepoRef,
}

pub const REVIEWS_QUERY: &str = r#"
query Reviews($from: DateTime!, $to: DateTime!) {
  viewer {
    contributionsCollection(from: $from, to: $to) {
      pullRequestReviewContributionsByRepository(maxRepositories: 50) {
        repository {
          id
          nameWithOwner
          description
          primaryLanguage { name }
          stargazerCount
          forkCount
          url
          isFork
          isArchived
          pushedAt
          owner { login avatarUrl url }
        }
        contributions(first: 50) {
          nodes {
            pullRequestReview {
              id
              url
              state
              submittedAt
              pullRequest { number title }
            }
          }
        }
      }
    }
  }
}
"#;

#[derive(Debug, Deserialize)]
pub struct ReviewsData {
    pub viewer: ReviewsViewer,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewsViewer {
    pub contributions_collection: ReviewsCollection,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewsCollection {
    pub pull_request_review_contributions_by_repository: Vec<ReviewByRepo>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewByRepo {
    pub repository: SimpleRepoRef,
    pub contributions: ReviewContributions,
}

#[derive(Debug, Deserialize)]
pub struct ReviewContributions {
    pub nodes: Vec<ReviewContributionNode>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewContributionNode {
    pub pull_request_review: PullRequestReview,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PullRequestReview {
    pub id: String,
    pub url: String,
    pub state: String,
    pub submitted_at: Option<String>,
    pub pull_request: PullRequestRef,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PullRequestRef {
    pub number: i64,
    pub title: String,
}

pub const YEAR_OVERVIEW_QUERY: &str = r#"
query YearOverview($from: DateTime!, $to: DateTime!) {
  viewer {
    contributionsCollection(from: $from, to: $to) {
      totalCommitContributions
      totalIssueContributions
      totalPullRequestContributions
      totalPullRequestReviewContributions
      commitContributionsByRepository(maxRepositories: 100) {
        repository {
          id nameWithOwner description primaryLanguage { name }
          stargazerCount forkCount url isFork isArchived pushedAt
          owner { login avatarUrl url }
        }
        contributions { totalCount }
      }
      issueContributionsByRepository(maxRepositories: 100) {
        repository {
          id nameWithOwner description primaryLanguage { name }
          stargazerCount forkCount url isFork isArchived pushedAt
          owner { login avatarUrl url }
        }
        contributions { totalCount }
      }
      pullRequestContributionsByRepository(maxRepositories: 100) {
        repository {
          id nameWithOwner description primaryLanguage { name }
          stargazerCount forkCount url isFork isArchived pushedAt
          owner { login avatarUrl url }
        }
        contributions { totalCount }
      }
      pullRequestReviewContributionsByRepository(maxRepositories: 100) {
        repository {
          id nameWithOwner description primaryLanguage { name }
          stargazerCount forkCount url isFork isArchived pushedAt
          owner { login avatarUrl url }
        }
        contributions { totalCount }
      }
    }
  }
}
"#;

#[derive(Debug, Deserialize)]
pub struct YearOverviewData {
    pub viewer: YearOverviewViewer,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct YearOverviewViewer {
    pub contributions_collection: YearOverviewCollection,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct YearOverviewCollection {
    pub total_commit_contributions: i64,
    pub total_issue_contributions: i64,
    pub total_pull_request_contributions: i64,
    pub total_pull_request_review_contributions: i64,
    pub commit_contributions_by_repository: Vec<RepoContribGroup>,
    pub issue_contributions_by_repository: Vec<RepoContribGroup>,
    pub pull_request_contributions_by_repository: Vec<RepoContribGroup>,
    pub pull_request_review_contributions_by_repository: Vec<RepoContribGroup>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepoContribGroup {
    pub repository: YearRepoRef,
    pub contributions: TotalCount,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct YearRepoRef {
    pub id: String,
    pub name_with_owner: String,
    pub description: Option<String>,
    pub primary_language: Option<RepoLanguage>,
    pub stargazer_count: i64,
    pub fork_count: i64,
    pub url: String,
    pub is_fork: bool,
    pub is_archived: bool,
    pub pushed_at: Option<String>,
    pub owner: YearRepoOwner,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct YearRepoOwner {
    pub login: String,
    pub avatar_url: Option<String>,
    pub url: String,
}

pub const FIRST_CONTRIBUTION_YEAR_QUERY: &str = r#"
query FirstYear {
  viewer {
    contributionsCollection {
      contributionYears
    }
  }
}
"#;

#[derive(Debug, Deserialize)]
pub struct YearsData {
    pub viewer: YearsViewer,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct YearsViewer {
    pub contributions_collection: ContributionYears,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContributionYears {
    pub contribution_years: Vec<i32>,
}
