use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum ProviderId {
    GitHub,
    GitLab,
    Bitbucket,
    Other(String),
}

impl ProviderId {
    pub fn as_str(&self) -> &str {
        match self {
            ProviderId::GitHub => "github",
            ProviderId::GitLab => "gitlab",
            ProviderId::Bitbucket => "bitbucket",
            ProviderId::Other(value) => value.as_str(),
        }
    }
}

impl fmt::Display for ProviderId {
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
    Pat { token: String },
}
