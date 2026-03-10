use std::collections::HashSet;
use std::path::Path;
use std::{env, fs};

use reqwest::Client;

use super::AiProviderKind;

const ANTHROPIC_KEY: &str = "ANTHROPIC_API_KEY";
const OPENAI_KEY: &str = "OPENAI_API_KEY";

// Step 1 -- System environment variables
fn detect_from_env() -> Vec<AiProviderKind> {
    let mut found = Vec::new();

    if env::var(ANTHROPIC_KEY).is_ok() {
        eprintln!("[detector] Detected provider: Claude (environment variable)");
        found.push(AiProviderKind::Claude);
    }

    if env::var(OPENAI_KEY).is_ok() {
        eprintln!("[detector] Detected provider: OpenAI (environment variable)");
        found.push(AiProviderKind::OpenAi);
    }

    if env::var("OLLAMA_HOST").is_ok() || env::var("OLLAMA_URL").is_ok() {
        eprintln!("[detector] Detected provider: Ollama (environment variable)");
        found.push(AiProviderKind::Ollama);
    }

    found
}

// Step 2 -- .env file scanning
fn detect_from_dotenv() -> Vec<AiProviderKind> {
    let mut found = Vec::new();
    let candidates = [".env", ".env.local"];

    for name in &candidates {
        let path = Path::new(name);
        if let Ok(content) = fs::read_to_string(path) {
            if contains_key(&content, ANTHROPIC_KEY) {
                eprintln!("[detector] Detected provider: Claude (.env file: {name})");
                found.push(AiProviderKind::Claude);
            }
            if contains_key(&content, OPENAI_KEY) {
                eprintln!("[detector] Detected provider: OpenAI (.env file: {name})");
                found.push(AiProviderKind::OpenAi);
            }
        }
    }

    found
}

fn contains_key(content: &str, key: &str) -> bool {
    content.lines().any(|line| {
        let trimmed = line.trim();
        !trimmed.starts_with('#')
            && trimmed.starts_with(key)
            && trimmed[key.len()..].starts_with('=')
    })
}

// Step 3 -- Common config directories
fn detect_from_config_dirs() -> Vec<AiProviderKind> {
    let mut found = Vec::new();

    let home = match dirs::home_dir() {
        Some(h) => h,
        None => return found,
    };

    let claude_paths = [
        home.join(".claude"),
        home.join(".config").join("anthropic"),
    ];

    let openai_paths = [
        home.join(".openai"),
        home.join(".config").join("openai"),
    ];

    for path in &claude_paths {
        if path.exists() && dir_has_key_files(path) {
            eprintln!("[detector] Detected provider: Claude (config dir: {})", path.display());
            found.push(AiProviderKind::Claude);
            break;
        }
    }

    for path in &openai_paths {
        if path.exists() && dir_has_key_files(path) {
            eprintln!("[detector] Detected provider: OpenAI (config dir: {})", path.display());
            found.push(AiProviderKind::OpenAi);
            break;
        }
    }

    found
}

fn dir_has_key_files(dir: &Path) -> bool {
    let key_indicators = ["credentials", "config", "auth.json", "key", "api_key"];

    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy().to_lowercase();

            for indicator in &key_indicators {
                if name_str.contains(indicator) {
                    return true;
                }
            }
        }
    }

    // The directory existing at all is a strong signal (e.g. ~/.claude)
    dir.is_dir()
}

// Step 4 -- Ollama local server detection
async fn detect_ollama_server() -> Option<AiProviderKind> {
    let host = env::var("OLLAMA_HOST")
        .or_else(|_| env::var("OLLAMA_URL"))
        .unwrap_or_else(|_| "http://localhost:11434".to_string());

    let url = format!("{host}/api/tags");

    let client = Client::builder()
        .timeout(std::time::Duration::from_secs(2))
        .build()
        .ok()?;

    match client.get(&url).send().await {
        Ok(resp) if resp.status().is_success() => {
            eprintln!("[detector] Detected provider: Ollama (local server at {host})");
            Some(AiProviderKind::Ollama)
        }
        _ => None,
    }
}

fn kind_key(kind: &AiProviderKind) -> &'static str {
    match kind {
        AiProviderKind::Claude => "claude",
        AiProviderKind::OpenAi => "openai",
        AiProviderKind::Ollama => "ollama",
    }
}

fn push_unique(
    kind: AiProviderKind,
    seen: &mut HashSet<&'static str>,
    result: &mut Vec<AiProviderKind>,
) {
    let key = kind_key(&kind);
    if seen.insert(key) {
        result.push(kind);
    }
}

// Step 5 + 6 -- Aggregation with deduplication and logging
pub async fn detect_providers() -> Vec<AiProviderKind> {
    let mut seen = HashSet::new();
    let mut result = Vec::new();

    for kind in detect_from_env() {
        push_unique(kind, &mut seen, &mut result);
    }

    for kind in detect_from_dotenv() {
        push_unique(kind, &mut seen, &mut result);
    }

    for kind in detect_from_config_dirs() {
        push_unique(kind, &mut seen, &mut result);
    }

    if !seen.contains("ollama") {
        if let Some(ollama) = detect_ollama_server().await {
            push_unique(ollama, &mut seen, &mut result);
        }
    }

    eprintln!("[detector] Detection complete: {} provider(s) found", result.len());

    result
}
