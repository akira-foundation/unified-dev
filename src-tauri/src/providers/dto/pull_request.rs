use crate::providers::enums::PullRequestState;

#[derive(Debug, Clone)]
pub struct VcsPullRequest {
    pub id: String,
    pub number: u64,
    pub title: String,
    pub state: PullRequestState,
    pub url: String,
    pub head: String,
    pub base: String,
    pub head_sha: String,
    pub updated_at: String,
    pub is_draft: bool,
    pub merged_at: Option<String>,
    pub body: Option<String>,
    pub author: Option<String>,
    pub labels: Vec<String>,
    pub reviewers: Vec<String>,
    pub ci_status: Option<String>,
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
    pub head_sha: String,
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
            head_sha: pr.head_sha,
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
