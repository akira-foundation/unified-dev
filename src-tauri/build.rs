fn main() {
    // Load .env from the workspace root (one level above src-tauri/)
    let env_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join(".env");

    if let Ok(contents) = std::fs::read_to_string(&env_path) {
        for line in contents.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some((key, value)) = line.split_once('=') {
                let key = key.trim();
                let value = value.trim().trim_matches('"').trim_matches('\'');
                // Only set if not already in the environment (shell env takes priority)
                if std::env::var(key).is_err() {
                    println!("cargo:rustc-env={key}={value}");
                }
            }
        }
    }

    // Re-run if .env changes
    println!("cargo:rerun-if-changed=../.env");

    // Validate required build-time billing envs. We don't fail debug builds
    // because contributors may not have all secrets locally, but we surface
    // a warning. Release builds must have them set.
    let billing_envs = [
        "AKIRA_BILLING_URL",
        "AKIRA_BILLING_SECRET",
        "AKIRA_LICENSE_PUBKEY",
    ];
    let profile = std::env::var("PROFILE").unwrap_or_default();
    for key in billing_envs {
        if std::env::var(key).is_err() {
            if profile == "release" {
                panic!("required build env `{key}` is missing for release build");
            } else {
                println!("cargo:warning=billing env `{key}` not set; using empty default");
                println!("cargo:rustc-env={key}=");
            }
        }
    }

    tauri_build::build()
}
