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
