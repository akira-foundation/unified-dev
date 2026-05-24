use crate::app::support::error::AppResult;

pub(crate) async fn unique_thread_branch(
    repo_id: &str,
    title: &str,
    pool: &sqlx::SqlitePool,
) -> AppResult<String> {
    let slug = sanitize_thread_title(title);
    let existing: Vec<(String,)> =
        sqlx::query_as("SELECT branch FROM threads WHERE repo_id = ?")
            .bind(repo_id)
            .fetch_all(pool)
            .await?;
    let taken: std::collections::HashSet<String> =
        existing.into_iter().map(|(b,)| b).collect();

    Ok(next_available_branch(&slug, &taken))
}

fn next_available_branch(slug: &str, taken: &std::collections::HashSet<String>) -> String {
    let base = format!("thread/{}", slug);
    if !taken.contains(&base) {
        return base;
    }

    let mut suffix = 2u32;
    loop {
        let candidate = format!("thread/{}-{}", slug, suffix);
        if !taken.contains(&candidate) {
            return candidate;
        }
        suffix += 1;
    }
}

pub fn sanitize_thread_title(value: &str) -> String {
    let title = value
        .to_lowercase()
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' })
        .collect::<String>()
        .split('-')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("-");

    if title.is_empty() {
        "thread".to_string()
    } else {
        title
    }
}

pub fn generate_thread_name(seed: u64) -> String {
    const ADJECTIVES: &[&str] = &[
        "gentle", "silver", "amber", "crimson", "silent", "hollow", "golden",
        "swift", "ancient", "bright", "calm", "dark", "eager", "faint",
        "grand", "heavy", "idle", "jade", "keen", "lean", "misty", "noble",
        "pale", "quiet", "rough", "sharp", "tall", "vast", "warm", "young",
    ];
    const NOUNS: &[&str] = &[
        "river", "hawk", "pine", "stone", "cloud", "flame", "ridge",
        "creek", "dawn", "dusk", "field", "forge", "gate", "grove",
        "hill", "isle", "lake", "marsh", "peak", "plain", "reef",
        "crest", "shade", "shore", "slope", "storm", "vale", "wave", "wind", "wood",
    ];
    let adj = ADJECTIVES[(seed as usize) % ADJECTIVES.len()];
    let noun = NOUNS[((seed >> 8) as usize) % NOUNS.len()];
    format!("{}-{}", adj, noun)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn slug_keeps_issue_identifier_and_kebabs() {
        assert_eq!(sanitize_thread_title("ENG-123 Fix the login"), "eng-123-fix-the-login");
    }

    #[test]
    fn slug_falls_back_when_empty() {
        assert_eq!(sanitize_thread_title("!!!"), "thread");
    }

    #[test]
    fn branch_uses_base_when_free() {
        let taken = HashSet::new();
        assert_eq!(next_available_branch("eng-123-fix", &taken), "thread/eng-123-fix");
    }

    #[test]
    fn branch_appends_next_free_suffix_on_collision() {
        let taken: HashSet<String> = ["thread/fix", "thread/fix-2"]
            .into_iter()
            .map(String::from)
            .collect();
        assert_eq!(next_available_branch("fix", &taken), "thread/fix-3");
    }
}
