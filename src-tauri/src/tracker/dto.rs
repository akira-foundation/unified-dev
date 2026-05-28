use serde::{Deserialize, Serialize};

pub use omnitrack::StatusCategory;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrackerIssue {
    pub id: String,
    pub identifier: Option<String>,
    pub title: String,
    pub description: Option<String>,
    pub url: Option<String>,
    pub status: String,
    pub category: Option<StatusCategory>,
    pub project: Option<String>,
    pub milestone: Option<String>,
    pub team: Option<String>,
    pub assignee: Option<String>,
    pub author: Option<String>,
    pub labels: Vec<String>,
    pub priority: Option<u8>,
    pub created_at: Option<String>,
    pub updated_at: String,
    #[serde(default)]
    pub project_name: Option<String>,
    #[serde(default)]
    pub milestone_name: Option<String>,
    #[serde(default)]
    pub team_name: Option<String>,
    #[serde(default)]
    pub assignee_name: Option<String>,
    #[serde(default)]
    pub author_name: Option<String>,
    #[serde(default)]
    pub label_names: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrackerNamed {
    pub id: String,
    pub name: String,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrackerComment {
    pub id: String,
    pub body: String,
    pub author: Option<String>,
    pub created_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrackerPage<T> {
    pub items: Vec<T>,
    pub next: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrackerIssueFilter {
    pub team: Option<String>,
    pub project: Option<String>,
    pub assignee: Option<String>,
    pub category: Option<StatusCategory>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrackerIssueDraft {
    pub team: String,
    pub title: String,
    pub status: Option<String>,
    pub category: Option<StatusCategory>,
    pub project: Option<String>,
    pub milestone: Option<String>,
    pub assignee: Option<String>,
    pub priority: Option<u8>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrackerIssuePatch {
    pub title: Option<String>,
    pub category: Option<StatusCategory>,
    pub project: Option<String>,
    pub milestone: Option<String>,
    pub assignee: Option<String>,
    pub priority: Option<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrackerPageRequest {
    pub after: Option<String>,
    pub limit: Option<u32>,
}
