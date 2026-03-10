use std::collections::HashSet;
use std::path::Path;
use std::{env, fs};

use reqwest::Client;

use super::AiProviderKind;

const ANTHROPIC_KEY: &str = "ANTHROPIC_API_KEY";
const OPENAI_KEY: &str = "OPENAI_API_KEY";

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

fn detect_from_shell_config() -> Vec<AiProviderKind> {
    let mut found = Vec::new();

    let home = match dirs::home_dir() {
        Some(h) => h,
        None => return found,
    };

    let shell_files = [
        home.join(".zshrc"),
        home.join(".zprofile"),
        home.join(".zshenv"),
        home.join(".bash_profile"),
        home.join(".bashrc"),
        home.join(".profile"),
    ];

    let mut has_anthropic = false;
    let mut has_openai = false;

    for path in &shell_files {
        if let Ok(content) = fs::read_to_string(path) {
            if !has_anthropic && shell_exports_key(&content, ANTHROPIC_KEY) {
                eprintln!("[detector] Detected provider: Claude (shell config: {})", path.display());
                found.push(AiProviderKind::Claude);
                has_anthropic = true;
            }
            if !has_openai && shell_exports_key(&content, OPENAI_KEY) {
                eprintln!("[detector] Detected provider: OpenAI (shell config: {})", path.display());
                found.push(AiProviderKind::OpenAi);
                has_openai = true;
            }
            if has_anthropic && has_openai {
                break;
            }
        }
    }

    found
}

fn shell_exports_key(content: &str, key: &str) -> bool {
    content.lines().any(|line| {
        let trimmed = line.trim();
        if trimmed.starts_with('#') {
            return false;
        }
        if trimmed.starts_with("export ") {
            let after_export = trimmed["export ".len()..].trim_start();
            return after_export.starts_with(key)
                && after_export[key.len()..].starts_with('=');
        }
        trimmed.starts_with(key) && trimmed[key.len()..].starts_with('=')
    })
}

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

fn detect_from_config_dirs() -> Vec<AiProviderKind> {
    let mut found = Vec::new();

    let home = match dirs::home_dir() {
        Some(h) => h,
        None => return found,
    };

    let claude_paths = [
        home.join(".claude"),
        home.join(".claude.json"),
        home.join(".config").join("anthropic"),
    ];

    let openai_paths = [
        home.join(".codex"),
        home.join(".openai"),
        home.join(".cursor"),
        home.join(".config").join("openai"),
    ];

    let copilot_paths = [
        home.join(".config").join("github-copilot"),
    ];

    for path in &claude_paths {
        if path.exists() {
            eprintln!("[detector] Detected provider: Claude (config path: {})", path.display());
            found.push(AiProviderKind::Claude);
            break;
        }
    }

    for path in &openai_paths {
        if path.exists() {
            eprintln!("[detector] Detected provider: OpenAI (config path: {})", path.display());
            found.push(AiProviderKind::OpenAi);
            break;
        }
    }

    for path in &copilot_paths {
        if path.exists() {
            eprintln!("[detector] Detected provider: Copilot (config path: {})", path.display());
            found.push(AiProviderKind::Copilot);
            break;
        }
    }

    found
}

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
        AiProviderKind::Copilot => "copilot",
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

pub async fn detect_providers() -> Vec<AiProviderKind> {
    let mut seen = HashSet::new();
    let mut result = Vec::new();

    for kind in detect_from_env() {
        push_unique(kind, &mut seen, &mut result);
    }

    for kind in detect_from_shell_config() {
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
