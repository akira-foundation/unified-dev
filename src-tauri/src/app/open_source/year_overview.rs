use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashMap;
use tauri::State;

use crate::state::AppState;

use super::graphql::{YearOverviewData, YEAR_OVERVIEW_QUERY};
use super::models::{ActivityBreakdownDto, OssOrgSummaryDto};
use super::provider::find_github_driver;

type OrgAggregate = (Option<String>, String, i64);

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct YearOverviewDto {
    pub year: i32,
    pub breakdown: ActivityBreakdownDto,
    pub organizations: Vec<OssOrgSummaryDto>,
    pub repos_preview: Vec<String>,
    pub repos_total: i64,
}

struct RepoAccumulator {
    name_with_owner: String,
    total: i64,
}

pub async fn fetch_year_overview(
    state: State<'_, AppState>,
    year: i32,
) -> Result<YearOverviewDto, String> {
    let ctx = find_github_driver(&state).await?;
    let from = format!("{}-01-01T00:00:00Z", year);
    let to = format!("{}-12-31T23:59:59Z", year);

    let data: YearOverviewData = ctx
        .driver
        .graphql(YEAR_OVERVIEW_QUERY, json!({ "from": from, "to": to }))
        .await
        .map_err(|e| e.to_string())?;

    let cc = data.viewer.contributions_collection;

    let denom = (cc.total_commit_contributions
        + cc.total_pull_request_contributions
        + cc.total_issue_contributions
        + cc.total_pull_request_review_contributions) as f64;

    let breakdown = if denom <= 0.0 {
        ActivityBreakdownDto::default()
    } else {
        let pct = |n: i64| (n as f64 / denom) * 100.0;
        ActivityBreakdownDto {
            commits: pct(cc.total_commit_contributions),
            pull_requests: pct(cc.total_pull_request_contributions),
            issues: pct(cc.total_issue_contributions),
            code_review: pct(cc.total_pull_request_review_contributions),
        }
    };

    let groups = [
        cc.commit_contributions_by_repository,
        cc.issue_contributions_by_repository,
        cc.pull_request_contributions_by_repository,
        cc.pull_request_review_contributions_by_repository,
    ];

    let mut repo_map: HashMap<String, RepoAccumulator> = HashMap::new();
    let mut org_map: HashMap<String, (Option<String>, String, i64)> = HashMap::new();

    for group in groups {
        for entry in group {
            let count = entry.contributions.total_count;
            let nwo = entry.repository.name_with_owner.clone();
            let owner_login = entry.repository.owner.login.clone();
            let owner_avatar = entry.repository.owner.avatar_url.clone();
            let owner_url = entry.repository.owner.url.clone();

            repo_map
                .entry(nwo.clone())
                .and_modify(|r| r.total += count)
                .or_insert(RepoAccumulator {
                    name_with_owner: nwo,
                    total: count,
                });

            org_map
                .entry(owner_login)
                .and_modify(|o| o.2 += count)
                .or_insert((owner_avatar, owner_url, count));
        }
    }

    let mut repos_sorted: Vec<RepoAccumulator> = repo_map.into_values().collect();
    repos_sorted.sort_by(|a, b| b.total.cmp(&a.total).then(a.name_with_owner.cmp(&b.name_with_owner)));

    let repos_total = repos_sorted.len() as i64;
    let repos_preview = repos_sorted.iter().take(3).map(|r| r.name_with_owner.clone()).collect();

    let mut orgs_sorted: Vec<(String, OrgAggregate)> = org_map.into_iter().collect();
    orgs_sorted.sort_by(|a, b| b.1.2.cmp(&a.1.2).then(a.0.cmp(&b.0)));
    let organizations = orgs_sorted
        .into_iter()
        .map(|(login, (avatar, url, _))| OssOrgSummaryDto {
            login,
            avatar_url: avatar,
            url,
        })
        .collect();

    Ok(YearOverviewDto {
        year,
        breakdown,
        organizations,
        repos_preview,
        repos_total,
    })
}
