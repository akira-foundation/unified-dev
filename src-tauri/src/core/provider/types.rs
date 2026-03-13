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
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PullRequestState {
    Open,
    Closed,
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
