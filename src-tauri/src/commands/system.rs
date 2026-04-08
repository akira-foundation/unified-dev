use serde::Serialize;

#[derive(Serialize)]
pub struct DependencyStatus {
    pub id: String,
    pub label: String,
    pub installed: bool,
    pub version: Option<String>,
    pub path: Option<String>,
}

fn find_binary(name: &str) -> Option<std::path::PathBuf> {
    let home = dirs::home_dir();
    let mut candidates: Vec<std::path::PathBuf> = vec![
        std::path::PathBuf::from(format!("/usr/local/bin/{}", name)),
        std::path::PathBuf::from(format!("/opt/homebrew/bin/{}", name)),
        std::path::PathBuf::from(format!("/usr/bin/{}", name)),
    ];
    if let Some(ref h) = home {
        candidates.insert(0, h.join(format!(".local/bin/{}", name)));
    }
    if let Ok(path_var) = std::env::var("PATH") {
        for dir in path_var.split(':') {
            candidates.push(std::path::PathBuf::from(dir).join(name));
        }
    }
    candidates.into_iter().find(|p| p.exists())
}

fn get_version(name: &str) -> Option<String> {
    let output = std::process::Command::new(name)
        .arg("--version")
        .output()
        .ok()?;
    let raw = if output.stdout.is_empty() {
        String::from_utf8_lossy(&output.stderr).to_string()
    } else {
        String::from_utf8_lossy(&output.stdout).to_string()
    };
    raw.lines().next().map(|l| l.trim().to_string())
}

fn check_copilot() -> DependencyStatus {
    // Since gh CLI 2.x, `gh copilot` is built-in — no separate extension needed
    let output = std::process::Command::new("gh")
        .args(["copilot", "--version"])
        .output();

    let installed = output
        .as_ref()
        .map(|o| o.status.success())
        .unwrap_or(false);

    let version = output.ok().filter(|_| installed).and_then(|o| {
        let raw = String::from_utf8_lossy(&o.stdout).to_string();
        raw.lines().next().map(|l| l.trim().to_string())
    });

    DependencyStatus {
        id: "copilot".to_string(),
        label: "GitHub Copilot CLI".to_string(),
        installed,
        version,
        path: None,
    }
}

#[tauri::command]
pub fn check_dependencies() -> Vec<DependencyStatus> {
    let mut result: Vec<DependencyStatus> = [
        ("claude", "Claude CLI"),
        ("gh", "GitHub CLI"),
        ("codex", "Codex CLI"),
    ]
    .iter()
    .map(|(id, label)| {
        let path = find_binary(id);
        let installed = path.is_some();
        let version = if installed { get_version(id) } else { None };
        DependencyStatus {
            id: id.to_string(),
            label: label.to_string(),
            installed,
            version,
            path: path.map(|p| p.to_string_lossy().to_string()),
        }
    })
    .collect();

    result.push(check_copilot());
    result
}
