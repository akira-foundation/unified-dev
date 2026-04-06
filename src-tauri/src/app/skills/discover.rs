use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use futures_util::future::join_all;

#[derive(Debug, Serialize, Clone)]
pub struct DiscoveredSkill {
    pub uid: String,
    pub id: String,
    pub name: String,
    pub description: String,
    pub repo_url: String,
    pub installs: u64,
}

#[derive(Debug, Deserialize)]
struct SearchResponse {
    skills: Vec<SearchEntry>,
}

#[derive(Debug, Deserialize, Clone)]
struct SearchEntry {
    id: String,
    #[serde(rename = "skillId")]
    skill_id: String,
    installs: u64,
    source: String,
}

fn to_display_name(skill_id: &str) -> String {
    skill_id
        .split('-')
        .map(|w| {
            let mut chars = w.chars();
            match chars.next() {
                None => String::new(),
                Some(f) => f.to_uppercase().to_string() + chars.as_str(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn parse_description(markdown: &str) -> Option<String> {
    let block_start = markdown.find("---\n").map(|i| i + 4)?;
    let block_end = markdown[block_start..].find("\n---").map(|i| i + block_start)?;
    let block = &markdown[block_start..block_end];

    for line in block.lines() {
        if let Some(rest) = line.strip_prefix("description:") {
            let value = rest.trim();
            if !value.is_empty() && value != ">-" && value != ">" {
                return Some(value.to_string());
            }
        }
    }
    None
}

fn extract_skills_sh_description(html: &str) -> Option<String> {
    let prose_start = html.find("class=\"prose")?;
    let tag_end = html[prose_start..].find('>')?;
    let content_start = prose_start + tag_end + 1;

    let remaining = &html[content_start..];
    let para_start = remaining.find("<p")?;
    let para_inner_start = remaining[para_start..].find('>')? + para_start + 1;
    let para_end = remaining[para_inner_start..].find("</p>")? + para_inner_start;

    let raw = &remaining[para_inner_start..para_end];
    let text = raw
        .replace("<br>", " ")
        .replace("<br/>", " ")
        .replace("<br />", " ");

    let stripped: String = {
        let mut out = String::with_capacity(text.len());
        let mut inside_tag = false;
        for ch in text.chars() {
            match ch {
                '<' => inside_tag = true,
                '>' => inside_tag = false,
                _ if !inside_tag => out.push(ch),
                _ => {}
            }
        }
        out
    };

    let result = stripped.trim().to_string();
    if result.is_empty() { None } else { Some(result) }
}

async fn fetch_description(client: &reqwest::Client, source: &str, skill_id: &str) -> String {
    let parts: Vec<&str> = source.splitn(2, '/').collect();
    if parts.len() != 2 {
        return String::new();
    }
    let (owner, repo) = (parts[0], parts[1]);
    let base = format!("https://raw.githubusercontent.com/{owner}/{repo}/main");

    let candidates = [
        format!("{base}/skills/{skill_id}/SKILL.md"),
        format!("{base}/plugin/skills/{skill_id}/SKILL.md"),
        format!("{base}/plugins/{owner}/skills/{skill_id}/SKILL.md"),
        format!("{base}/plugins/{skill_id}/SKILL.md"),
        format!("{base}/{skill_id}/SKILL.md"),
        format!("{base}/SKILL.md"),
    ];

    for url in &candidates {
        if let Ok(res) = client.get(url).send().await {
            if res.status().is_success() {
                if let Ok(text) = res.text().await {
                    if let Some(desc) = parse_description(&text) {
                        return desc;
                    }
                }
            }
        }
    }

    let fallback_url = format!("https://skills.sh/{owner}/{repo}/{skill_id}");
    if let Ok(res) = client.get(&fallback_url).send().await {
        if res.status().is_success() {
            if let Ok(html) = res.text().await {
                if let Some(desc) = extract_skills_sh_description(&html) {
                    return desc;
                }
            }
        }
    }

    String::new()
}

pub async fn fetch_recommended() -> Vec<DiscoveredSkill> {
    let client = match reqwest::Client::builder()
        .user_agent("akira-maintainer/1.0")
        .timeout(std::time::Duration::from_secs(15))
        .build()
    {
        Ok(c) => c,
        Err(_) => return vec![],
    };

    let queries = ["er", "on", "ing", "the", "de", "al", "re", "en"];

    let search_futures = queries.iter().map(|q| {
        let client = client.clone();
        let url = format!("https://skills.sh/api/search?q={q}&limit=200");
        async move {
            let res = client.get(&url).send().await.ok()?;
            if !res.status().is_success() {
                return None;
            }
            res.json::<SearchResponse>().await.ok()
        }
    });

    let responses = join_all(search_futures).await;

    let mut seen: HashMap<String, SearchEntry> = HashMap::new();
    let mut order: Vec<String> = Vec::new();

    for response in responses.into_iter().flatten() {
        for entry in response.skills {
            if !seen.contains_key(&entry.id) {
                order.push(entry.id.clone());
                seen.insert(entry.id.clone(), entry);
            }
        }
    }

    let mut sorted: Vec<SearchEntry> = order
        .into_iter()
        .filter_map(|id| seen.remove(&id))
        .collect();
    sorted.sort_by(|a, b| b.installs.cmp(&a.installs));

    const BATCH: usize = 30;
    let mut results: Vec<DiscoveredSkill> = Vec::with_capacity(sorted.len());

    for chunk in sorted.chunks(BATCH) {
        let desc_futures = chunk
            .iter()
            .map(|s| fetch_description(&client, &s.source, &s.skill_id));

        let descriptions = join_all(desc_futures).await;

        for (entry, description) in chunk.iter().zip(descriptions) {
            results.push(DiscoveredSkill {
                uid: entry.id.clone(),
                id: entry.skill_id.clone(),
                name: to_display_name(&entry.skill_id),
                description,
                repo_url: format!("https://github.com/{}", entry.source),
                installs: entry.installs,
            });
        }
    }

    results
}
