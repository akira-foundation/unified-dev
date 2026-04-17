use crate::ai::agents::types::AiProviderKind;

pub fn detect_from_config_dirs() -> Vec<AiProviderKind> {
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

    let copilot_paths = [home.join(".config").join("github-copilot")];

    let gemini_paths = [home.join(".gemini").join("oauth_creds.json")];

    for path in &claude_paths {
        if path.exists() {
            found.push(AiProviderKind::Claude);
            break;
        }
    }

    for path in &openai_paths {
        if path.exists() {
            found.push(AiProviderKind::OpenAi);
            break;
        }
    }

    for path in &copilot_paths {
        if path.exists() {
            found.push(AiProviderKind::Copilot);
            break;
        }
    }

    for path in &gemini_paths {
        if path.exists() {
            found.push(AiProviderKind::Gemini);
            break;
        }
    }

    found
}
