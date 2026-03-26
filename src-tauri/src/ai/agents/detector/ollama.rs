use std::env;

use reqwest::Client;

use crate::ai::agents::types::AiProviderKind;

pub async fn detect_ollama_server() -> Option<AiProviderKind> {
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
