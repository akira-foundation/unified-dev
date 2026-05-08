use chrono::{Datelike, Duration, Utc};

use super::models::*;

pub fn summary() -> ContributionSummaryDto {
    ContributionSummaryDto {
        profile: OssProfileDto {
            login: "octocat".to_string(),
            name: Some("The Octocat".to_string()),
            avatar_url: Some("https://avatars.githubusercontent.com/u/583231?v=4".to_string()),
            bio: Some("Open source enthusiast.".to_string()),
            followers: 12_400,
            following: 9,
        },
        totals: OssTotalsDto {
            repositories: 87,
            pull_requests: 312,
            merged_pull_requests: 254,
            commits: 4_812,
            issues: 96,
            reviews: 178,
            organizations: 14,
        },
        streaks: OssStreaksDto { current: 23, best: 142 },
        most_active_language: Some("Rust".to_string()),
        most_active_repo: Some("rust-lang/rust".to_string()),
        last_synced_at: Some(Utc::now().to_rfc3339()),
        connected: false,
    }
}

pub fn repositories() -> Vec<ContributedRepoDto> {
    let seeds = [
        ("rust-lang/rust", "rust-lang", "Empowering everyone to build reliable and efficient software.", "Rust", 95_000, 12_300),
        ("tauri-apps/tauri", "tauri-apps", "Build smaller, faster, and more secure desktop applications.", "Rust", 81_000, 2_400),
        ("facebook/react", "facebook", "The library for web and native user interfaces.", "JavaScript", 228_000, 46_000),
        ("vercel/next.js", "vercel", "The React Framework.", "TypeScript", 124_000, 26_500),
        ("microsoft/vscode", "microsoft", "Visual Studio Code.", "TypeScript", 162_000, 28_700),
        ("laravel/framework", "laravel", "The Laravel framework.", "PHP", 32_000, 11_000),
        ("vuejs/core", "vuejs", "Vue.js core.", "TypeScript", 47_000, 8_100),
        ("denoland/deno", "denoland", "A modern runtime for JavaScript and TypeScript.", "Rust", 95_000, 5_300),
        ("nestjs/nest", "nestjs", "Progressive Node.js framework.", "TypeScript", 67_000, 7_700),
        ("sveltejs/svelte", "sveltejs", "Cybernetically enhanced web apps.", "TypeScript", 80_000, 4_300),
    ];

    seeds
        .into_iter()
        .enumerate()
        .map(|(i, (nwo, owner, desc, lang, stars, forks))| ContributedRepoDto {
            id: format!("repo-{}", i),
            name_with_owner: nwo.to_string(),
            owner_login: owner.to_string(),
            description: Some(desc.to_string()),
            primary_language: Some(lang.to_string()),
            stars,
            forks,
            url: format!("https://github.com/{}", nwo),
            is_fork: false,
            is_archived: false,
            last_contribution_at: Some((Utc::now() - Duration::days((i as i64) * 7)).to_rfc3339()),
        })
        .collect()
}

pub fn pull_requests() -> Vec<OssPullRequestDto> {
    let seeds = [
        ("rust-lang/rust", 1, "Improve diagnostics for trait bounds", "MERGED", true, 312, 78),
        ("rust-lang/rust", 2, "Stabilize feature X", "OPEN", false, 12, 4),
        ("tauri-apps/tauri", 14, "Fix window resize on macOS", "MERGED", true, 84, 32),
        ("facebook/react", 9, "Update useEffect docs", "MERGED", true, 2, 0),
        ("vercel/next.js", 21, "Add edge runtime guard", "CLOSED", false, 56, 12),
        ("laravel/framework", 7, "Add validation rule for cuid2", "MERGED", true, 142, 8),
        ("vuejs/core", 11, "Reactivity perf improvement", "OPEN", false, 23, 7),
        ("denoland/deno", 5, "Add --allow-import flag", "MERGED", true, 412, 95),
        ("nestjs/nest", 3, "Improve dependency resolution", "MERGED", true, 67, 14),
        ("sveltejs/svelte", 8, "Fix transition glitch", "MERGED", true, 18, 3),
    ];

    seeds
        .into_iter()
        .enumerate()
        .map(|(i, (nwo, n, title, state, merged, add, del))| OssPullRequestDto {
            id: format!("pr-{}", i),
            repo_id: format!("repo-{}", i),
            name_with_owner: nwo.to_string(),
            number: n,
            title: title.to_string(),
            state: state.to_string(),
            merged,
            url: format!("https://github.com/{}/pull/{}", nwo, n),
            additions: add,
            deletions: del,
            created_at: (Utc::now() - Duration::days((i as i64) * 6)).to_rfc3339(),
            merged_at: if merged {
                Some((Utc::now() - Duration::days((i as i64) * 5)).to_rfc3339())
            } else {
                None
            },
            closed_at: if state == "CLOSED" || merged {
                Some((Utc::now() - Duration::days((i as i64) * 5)).to_rfc3339())
            } else {
                None
            },
        })
        .collect()
}

pub fn issues() -> Vec<OssIssueDto> {
    let seeds = [
        ("rust-lang/rust", 100, "Lifetime inference inconsistency", "OPEN", 12),
        ("tauri-apps/tauri", 42, "macOS notarization failure on M1", "CLOSED", 8),
        ("facebook/react", 17, "Hydration mismatch in suspense boundary", "OPEN", 23),
        ("vercel/next.js", 33, "Edge cache invalidation", "CLOSED", 5),
        ("laravel/framework", 9, "Eloquent N+1 with morphs", "OPEN", 7),
    ];

    seeds
        .into_iter()
        .enumerate()
        .map(|(i, (nwo, n, title, state, comments))| OssIssueDto {
            id: format!("issue-{}", i),
            repo_id: format!("repo-{}", i),
            name_with_owner: nwo.to_string(),
            number: n,
            title: title.to_string(),
            state: state.to_string(),
            url: format!("https://github.com/{}/issues/{}", nwo, n),
            comments_count: comments,
            created_at: (Utc::now() - Duration::days((i as i64) * 4)).to_rfc3339(),
            closed_at: if state == "CLOSED" {
                Some((Utc::now() - Duration::days((i as i64) * 2)).to_rfc3339())
            } else {
                None
            },
        })
        .collect()
}

pub fn reviews() -> Vec<OssReviewDto> {
    let seeds = [
        ("rust-lang/rust", 144, "Refactor borrow checker", "APPROVED"),
        ("tauri-apps/tauri", 88, "WebView2 update", "COMMENTED"),
        ("facebook/react", 222, "Concurrent rendering tweaks", "APPROVED"),
        ("vercel/next.js", 304, "Middleware bundling", "CHANGES_REQUESTED"),
        ("denoland/deno", 19, "Permission prompt UX", "APPROVED"),
    ];

    seeds
        .into_iter()
        .enumerate()
        .map(|(i, (nwo, pr_n, pr_title, state))| OssReviewDto {
            id: format!("review-{}", i),
            repo_id: format!("repo-{}", i),
            name_with_owner: nwo.to_string(),
            pr_number: pr_n,
            pr_title: Some(pr_title.to_string()),
            state: state.to_string(),
            url: format!("https://github.com/{}/pull/{}", nwo, pr_n),
            submitted_at: (Utc::now() - Duration::days((i as i64) * 3)).to_rfc3339(),
        })
        .collect()
}

pub fn calendar(year: i32) -> Vec<ContributionCalendarDayDto> {
    let now = Utc::now().date_naive();
    let target_year = if year > 0 { year } else { now.year() };
    let start = chrono::NaiveDate::from_ymd_opt(target_year, 1, 1).unwrap();
    let end = chrono::NaiveDate::from_ymd_opt(target_year, 12, 31).unwrap();
    let mut days = Vec::new();
    let mut day = start;
    while day <= end {
        let seed = (day.ordinal() as i64 + day.weekday().num_days_from_monday() as i64) % 7;
        let count = match seed {
            0 => 0,
            1 => 1,
            2 => 3,
            3 => 6,
            4 => 9,
            5 => 12,
            _ => 4,
        };
        let color = match count {
            0 => None,
            1..=2 => Some("#0e4429".to_string()),
            3..=5 => Some("#006d32".to_string()),
            6..=9 => Some("#26a641".to_string()),
            _ => Some("#39d353".to_string()),
        };
        days.push(ContributionCalendarDayDto {
            date: day.to_string(),
            count,
            color,
        });
        day = day + Duration::days(1);
    }
    days
}
