use serde::{Deserialize, Serialize};
use sqlx::FromRow;

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NotificationSeverity {
    Info,
    Success,
    Warning,
    Error,
}

impl NotificationSeverity {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Info => "info",
            Self::Success => "success",
            Self::Warning => "warning",
            Self::Error => "error",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NotificationCategory {
    Autopilot,
    PullRequest,
    Issue,
    Sync,
    Workspace,
    Update,
    Auth,
    Skill,
    UsageLimit,
}

impl NotificationCategory {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Autopilot => "autopilot",
            Self::PullRequest => "pull_request",
            Self::Issue => "issue",
            Self::Sync => "sync",
            Self::Workspace => "workspace",
            Self::Update => "update",
            Self::Auth => "auth",
            Self::Skill => "skill",
            Self::UsageLimit => "usage_limit",
        }
    }
}

#[derive(Debug, Clone)]
pub struct NotificationInput {
    pub category: NotificationCategory,
    pub severity: NotificationSeverity,
    pub title: String,
    pub body: Option<String>,
    pub action_type: Option<String>,
    pub action_payload: Option<String>,
    pub ttl_days: Option<i64>,
}

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct Notification {
    pub id: String,
    pub category: String,
    pub severity: String,
    pub title: String,
    pub body: Option<String>,
    pub action_type: Option<String>,
    pub action_payload: Option<String>,
    pub read_at: Option<String>,
    pub created_at: String,
    pub expires_at: Option<String>,
}
