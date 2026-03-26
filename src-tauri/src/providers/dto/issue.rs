#[derive(Debug, Clone)]
pub struct VcsIssue {
    pub external_id: String,
    pub number: u64,
    pub title: String,
    pub body: Option<String>,
    pub status: String,
    pub state_reason: Option<String>,
    pub labels: Vec<String>,
    pub label_colors: Vec<String>,
    pub assignees: Vec<String>,
    pub author: Option<String>,
    pub url: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IssueDto {
    pub id: String,
    pub external_id: String,
    pub provider: String,
    pub org_id: String,
    pub repo_name: String,
    pub number: i64,
    pub title: String,
    pub body: Option<String>,
    pub status: String,
    pub state_reason: Option<String>,
    pub labels: Vec<String>,
    pub label_colors: Vec<String>,
    pub assignees: Vec<String>,
    pub author: Option<String>,
    pub url: String,
    pub linked_pr_numbers: Vec<u64>,
    pub created_at: String,
    pub updated_at: String,
    pub synced_at: String,
}
