use std::path::PathBuf;

static SEARCH_PATHS: &[&str] = &["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"];

pub fn resolve_binary(name: &str) -> Option<PathBuf> {
    for dir in SEARCH_PATHS {
        let candidate = PathBuf::from(dir).join(name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}
