use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum ProviderKind {
    GitHub,
    GitLab,
    Bitbucket,
    Other(String),
}

impl ProviderKind {
    pub fn as_str(&self) -> &str {
        match self {
            ProviderKind::GitHub => "github",
            ProviderKind::GitLab => "gitlab",
            ProviderKind::Bitbucket => "bitbucket",
            ProviderKind::Other(value) => value.as_str(),
        }
    }

    pub fn from_str(value: &str) -> Self {
        match value {
            "github" => ProviderKind::GitHub,
            "gitlab" => ProviderKind::GitLab,
            "bitbucket" => ProviderKind::Bitbucket,
            other => ProviderKind::Other(other.to_string()),
        }
    }
}

impl fmt::Display for ProviderKind {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

#[derive(Debug, Clone)]
pub struct VcsRepository {
    pub id: String,
    pub owner: String,
    pub name: String,
    pub full_name: String,
    pub default_branch: String,
    pub is_private: bool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ProviderRepo {
    pub id: String,
    pub owner: String,
    pub name: String,
    pub visibility: String,
    pub is_private: bool,
    pub default_branch: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProviderOrgKind {
    Personal,
    Organization,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ProviderOrg {
    pub id: String,
    pub login: String,
    pub kind: ProviderOrgKind,
}

#[derive(Debug, Clone)]
pub struct VcsPullRequest {
    pub id: String,
    pub number: u64,
    pub title: String,
    pub state: PullRequestState,
    pub url: String,
    pub head: String,
    pub base: String,
    pub updated_at: String,
    pub is_draft: bool,
    pub merged_at: Option<String>,
    pub body: Option<String>,
    pub author: Option<String>,
    pub labels: Vec<String>,
    pub reviewers: Vec<String>,
    pub ci_status: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PullRequestState {
    Open,
    Closed,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PullRequestDto {
    pub id: String,
    pub number: u64,
    pub title: String,
    pub state: String,
    pub url: String,
    pub head: String,
    pub base: String,
    pub updated_at: String,
    pub is_draft: bool,
    pub merged_at: Option<String>,
    pub body: Option<String>,
    pub author: Option<String>,
    pub labels: Vec<String>,
    pub reviewers: Vec<String>,
    pub ci_status: Option<String>,
}

impl From<VcsPullRequest> for PullRequestDto {
    fn from(pr: VcsPullRequest) -> Self {
        Self {
            id: pr.id,
            number: pr.number,
            title: pr.title,
            state: match pr.state {
                PullRequestState::Open => "open".to_string(),
                PullRequestState::Closed => "closed".to_string(),
            },
            url: pr.url,
            head: pr.head,
            base: pr.base,
            updated_at: pr.updated_at,
            is_draft: pr.is_draft,
            merged_at: pr.merged_at,
            body: pr.body,
            author: pr.author,
            labels: pr.labels,
            reviewers: pr.reviewers,
            ci_status: pr.ci_status,
        }
    }
}

#[derive(Debug, Clone)]
pub struct VcsPrComment {
    pub id: String,
    pub author: String,
    pub body: String,
    pub created_at: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PrCommentDto {
    pub id: String,
    pub author: String,
    pub body: String,
    pub created_at: String,
}

impl From<VcsPrComment> for PrCommentDto {
    fn from(c: VcsPrComment) -> Self {
        Self {
            id: c.id,
            author: c.author,
            body: c.body,
            created_at: c.created_at,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PrReviewEvent {
    Approve,
    RequestChanges,
    Comment,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PrMergeStrategy {
    Merge,
    Squash,
    Rebase,
}

#[derive(Debug, Clone)]
pub struct VcsPrFile {
    pub filename: String,
    pub status: String,
    pub additions: u64,
    pub deletions: u64,
    pub patch: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PrFileDto {
    pub filename: String,
    pub status: String,
    pub additions: u64,
    pub deletions: u64,
    pub patch: Option<String>,
}

impl From<VcsPrFile> for PrFileDto {
    fn from(f: VcsPrFile) -> Self {
        Self {
            filename: f.filename,
            status: f.status,
            additions: f.additions,
            deletions: f.deletions,
            patch: f.patch,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(tag = "auth_type", content = "auth_payload")]
pub enum ProviderAuth {
    #[serde(rename = "pat")]
    PersonalAccessToken { token: String },

    #[serde(rename = "github_oauth")]
    GitHubOAuth {
        access_token: String,
        refresh_token: Option<String>,
        expires_at: Option<i64>,
    },

    #[serde(rename = "app_password")]
    AppPassword { username: String, password: String },
}
