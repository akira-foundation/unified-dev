use std::fs;
use std::path::PathBuf;

use chrono::{Duration, Utc};

use super::registry::ModelRegistry;

fn cache_path() -> Option<PathBuf> {
    dirs::home_dir().map(|home| home.join(".unifieddev").join("model_registry.json"))
}

pub fn load_cached_registry() -> Option<ModelRegistry> {
    let path = cache_path()?;
    let content = fs::read_to_string(&path).ok()?;
    let registry: ModelRegistry = serde_json::from_str(&content).ok()?;

    let age = Utc::now() - registry.last_updated;
    if age < Duration::hours(1) {
        Some(registry)
    } else {
        None
    }
}

pub fn save_registry_cache(registry: &ModelRegistry) {
    if let Some(path) = cache_path() {
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        if let Ok(json) = serde_json::to_string_pretty(registry) {
            let _ = fs::write(&path, json);
        }
    }
}
