use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OssProfileDto {
    pub login: String,
    pub name: Option<String>,
    pub avatar_url: Option<String>,
    pub bio: Option<String>,
    pub followers: i64,
    pub following: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct OssTotalsDto {
    pub repositories: i64,
    pub pull_requests: i64,
    pub merged_pull_requests: i64,
    pub commits: i64,
    pub issues: i64,
    pub reviews: i64,
    pub organizations: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct OssStreaksDto {
    pub current: i64,
    pub best: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OssOrgSummaryDto {
    pub login: String,
    pub avatar_url: Option<String>,
    pub url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ActivityBreakdownDto {
    pub commits: f64,
    pub pull_requests: f64,
    pub issues: f64,
    pub code_review: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContributionSummaryDto {
    pub profile: OssProfileDto,
    pub totals: OssTotalsDto,
    pub streaks: OssStreaksDto,
    pub most_active_language: Option<String>,
    pub most_active_repo: Option<String>,
    pub last_synced_at: Option<String>,
    pub connected: bool,
    pub years: Vec<i32>,
    pub organizations_list: Vec<OssOrgSummaryDto>,
    pub activity_breakdown: ActivityBreakdownDto,
    pub contributed_repos_preview: Vec<String>,
    pub contributed_repos_total: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContributedRepoDto {
    pub id: String,
    pub name_with_owner: String,
    pub owner_login: String,
    pub description: Option<String>,
    pub primary_language: Option<String>,
    pub stars: i64,
    pub forks: i64,
    pub url: String,
    pub is_fork: bool,
    pub is_archived: bool,
    pub last_contribution_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OssPullRequestDto {
    pub id: String,
    pub repo_id: String,
    pub name_with_owner: String,
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
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OssIssueDto {
    pub id: String,
    pub repo_id: String,
    pub name_with_owner: String,
    pub number: i64,
    pub title: String,
    pub state: String,
    pub url: String,
    pub comments_count: i64,
    pub created_at: String,
    pub closed_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OssReviewDto {
    pub id: String,
    pub repo_id: String,
    pub name_with_owner: String,
    pub pr_number: i64,
    pub pr_title: Option<String>,
    pub state: String,
    pub url: String,
    pub submitted_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContributionCalendarDayDto {
    pub date: String,
    pub count: i64,
    pub color: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct OssFiltersDto {
    pub year: Option<i32>,
    pub org: Option<String>,
    pub repo: Option<String>,
    pub r#type: Option<String>,
    pub state: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OssSyncResultDto {
    pub synced: bool,
    pub last_synced_at: Option<String>,
    pub repositories: i64,
    pub pull_requests: i64,
    pub issues: i64,
    pub reviews: i64,
}
