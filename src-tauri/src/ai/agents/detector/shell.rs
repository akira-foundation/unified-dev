use std::fs;

use crate::ai::agents::types::AiProviderKind;

const ANTHROPIC_KEY: &str = "ANTHROPIC_API_KEY";
const OPENAI_KEY: &str = "OPENAI_API_KEY";

pub fn detect_from_shell_config() -> Vec<AiProviderKind> {
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
                eprintln!(
                    "[detector] Detected provider: Claude (shell config: {})",
                    path.display()
                );
                found.push(AiProviderKind::Claude);
                has_anthropic = true;
            }
            if !has_openai && shell_exports_key(&content, OPENAI_KEY) {
                eprintln!(
                    "[detector] Detected provider: OpenAI (shell config: {})",
                    path.display()
                );
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
            return after_export.starts_with(key) && after_export[key.len()..].starts_with('=');
        }
        trimmed.starts_with(key) && trimmed[key.len()..].starts_with('=')
    })
}
