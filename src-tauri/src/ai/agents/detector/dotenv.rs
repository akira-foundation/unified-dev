use std::fs;
use std::path::Path;

use crate::ai::agents::types::AiProviderKind;

const ANTHROPIC_KEY: &str = "ANTHROPIC_API_KEY";
const OPENAI_KEY: &str = "OPENAI_API_KEY";

pub fn detect_from_dotenv() -> Vec<AiProviderKind> {
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
