pub mod bitbucket;
pub mod github;
pub mod gitlab;

use std::path::Path;
use crate::app::support::error::AppResult;

pub trait RemoteProvider: Send {
    fn clone(&self, nwo: &str, destination: &Path) -> AppResult<()>;
}

pub fn detect(url: &str) -> Option<(Box<dyn RemoteProvider>, String)> {
    let trimmed = url.trim().trim_end_matches('/').trim_end_matches(".git");

    if let Some(path) = trimmed
        .strip_prefix("https://github.com/")
        .or_else(|| trimmed.strip_prefix("http://github.com/"))
        .or_else(|| trimmed.strip_prefix("git@github.com:"))
    {
        let nwo = parse_nwo(path)?;
        return Some((Box::new(github::GitHubProvider), nwo));
    }

    if let Some(path) = trimmed
        .strip_prefix("https://gitlab.com/")
        .or_else(|| trimmed.strip_prefix("http://gitlab.com/"))
        .or_else(|| trimmed.strip_prefix("git@gitlab.com:"))
    {
        let nwo = parse_nwo(path)?;
        return Some((Box::new(gitlab::GitLabProvider), nwo));
    }

    if let Some(path) = trimmed
        .strip_prefix("https://bitbucket.org/")
        .or_else(|| trimmed.strip_prefix("http://bitbucket.org/"))
        .or_else(|| trimmed.strip_prefix("git@bitbucket.org:"))
    {
        let nwo = parse_nwo(path)?;
        return Some((Box::new(bitbucket::BitbucketProvider), nwo));
    }

    None
}

fn parse_nwo(path: &str) -> Option<String> {
    let mut parts = path.splitn(2, '/');
    let owner = parts.next()?.trim();
    let repo = parts.next()?.trim();
    if owner.is_empty() || repo.is_empty() {
        return None;
    }
    Some(format!("{owner}/{repo}"))
}
