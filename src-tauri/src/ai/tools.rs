use serde_json::{json, Value};

/// Split a shell command string into tokens, respecting single and double quoted strings.
/// e.g. `git commit -m "chore: add routes"` → ["git", "commit", "-m", "chore: add routes"]
/// Shell redirections (2>&1, >/dev/null, 2>/dev/null, etc.) are stripped — we capture
/// stdout/stderr directly via tokio::process::Command, so they are never needed.
fn shell_split(cmd: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut in_single = false;
    let mut in_double = false;
    let mut chars = cmd.chars().peekable();

    while let Some(c) = chars.next() {
        match c {
            '\'' if !in_double => in_single = !in_single,
            '"' if !in_single => in_double = !in_double,
            ' ' | '\t' if !in_single && !in_double => {
                if !current.is_empty() {
                    tokens.push(current.clone());
                    current.clear();
                }
            }
            '\\' if in_double => {
                if let Some(next) = chars.next() {
                    current.push(next);
                }
            }
            _ => current.push(c),
        }
    }
    if !current.is_empty() {
        tokens.push(current);
    }

    let mut filtered = Vec::new();
    let mut skip_next = false;
    for token in tokens {
        if skip_next {
            skip_next = false;
            continue;
        }
        if token == ">" || token == ">>" || token == "2>" || token == "&>" || token == "&>>" {
            skip_next = true;
            continue;
        }
        if token.starts_with("2>&")
            || token.starts_with(">&")
            || (token.starts_with('>') && token.len() > 1)
            || (token.starts_with("2>") && token.len() > 2)
        {
            continue;
        }
        filtered.push(token);
    }
    filtered
}

/// Anthropic tool definitions (uses `input_schema`).
pub fn tool_definitions_anthropic() -> Value {
    json!([
        {
            "name": "read_file",
            "description": "Read the contents of a file in the workspace. Use this to examine source code, config files, or any text file.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path to the file, relative to the workspace root (e.g. 'src/helpers.php')."
                    }
                },
                "required": ["path"]
            }
        },
        {
            "name": "write_file",
            "description": "Write or overwrite a file in the workspace with new content. Use this to apply code changes.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path to the file, relative to the workspace root."
                    },
                    "content": {
                        "type": "string",
                        "description": "Full content to write to the file."
                    }
                },
                "required": ["path", "content"]
            }
        },
        {
            "name": "list_files",
            "description": "List files and directories at a given path in the workspace.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Directory path relative to workspace root. Use '.' for root."
                    }
                },
                "required": ["path"]
            }
        },
        {
            "name": "run_command",
            "description": "Run a shell command in the workspace directory.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "The shell command to run (e.g. 'git diff HEAD~1')."
                    }
                },
                "required": ["command"]
            }
        },
        {
            "name": "search_in_file",
            "description": "Search for a pattern (plain text or regex) in a file and return matching lines with line numbers.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "File path relative to workspace root."
                    },
                    "pattern": {
                        "type": "string",
                        "description": "Text or regex pattern to search for."
                    }
                },
                "required": ["path", "pattern"]
            }
        }
    ])
}

/// OpenAI Chat Completions tool definitions (uses `function.parameters`).
pub fn tool_definitions_openai() -> Value {
    json!([
        {
            "type": "function",
            "function": {
                "name": "read_file",
                "description": "Read the contents of a file in the workspace.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "File path relative to workspace root." }
                    },
                    "required": ["path"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "write_file",
                "description": "Write or overwrite a file in the workspace with new content.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "File path relative to workspace root." },
                        "content": { "type": "string", "description": "Full content to write to the file." }
                    },
                    "required": ["path", "content"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "list_files",
                "description": "List files and directories at a given path in the workspace.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "Directory path relative to workspace root. Use '.' for root." }
                    },
                    "required": ["path"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "run_command",
                "description": "Run a shell command in the workspace.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "command": { "type": "string", "description": "The shell command to run." }
                    },
                    "required": ["command"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "search_in_file",
                "description": "Search for a pattern in a file and return matching lines with line numbers.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "File path relative to workspace root." },
                        "pattern": { "type": "string", "description": "Text or regex pattern to search for." }
                    },
                    "required": ["path", "pattern"]
                }
            }
        }
    ])
}

/// Responses API tool definitions (no `function` wrapper).
pub fn tool_definitions_responses() -> Value {
    json!([
        {
            "type": "function",
            "name": "read_file",
            "description": "Read the contents of a file in the workspace.",
            "parameters": {
                "type": "object",
                "properties": { "path": { "type": "string", "description": "File path relative to workspace root." } },
                "required": ["path"]
            }
        },
        {
            "type": "function",
            "name": "write_file",
            "description": "Write or overwrite a file in the workspace with new content.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": { "type": "string" },
                    "content": { "type": "string" }
                },
                "required": ["path", "content"]
            }
        },
        {
            "type": "function",
            "name": "list_files",
            "description": "List files and directories at a given path in the workspace.",
            "parameters": {
                "type": "object",
                "properties": { "path": { "type": "string", "description": "Directory path relative to workspace root. Use '.' for root." } },
                "required": ["path"]
            }
        },
        {
            "type": "function",
            "name": "run_command",
            "description": "Run a shell command in the workspace.",
            "parameters": {
                "type": "object",
                "properties": { "command": { "type": "string" } },
                "required": ["command"]
            }
        },
        {
            "type": "function",
            "name": "search_in_file",
            "description": "Search for a pattern in a file and return matching lines with line numbers.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": { "type": "string" },
                    "pattern": { "type": "string" }
                },
                "required": ["path", "pattern"]
            }
        }
    ])
}

/// Execute a tool call and return the result string.
pub fn execute_tool(name: &str, args: &Value, workspace_path: &str) -> String {
    let root = std::path::Path::new(workspace_path);

    match name {
        "read_file" => {
            let Some(rel) = args.get("path").and_then(|v| v.as_str()) else {
                return "Error: missing 'path' argument".to_string();
            };
            let rel = rel.trim_start_matches('/');
            if rel.contains("..") {
                return "Error: path traversal ('..') is not allowed".to_string();
            }
            let path = root.join(rel);
            eprintln!("[tool] read_file: {:?}", path);
            match std::fs::read_to_string(&path) {
                Ok(content) => content
                    .lines()
                    .enumerate()
                    .map(|(i, line)| format!("{:>4}: {}", i + 1, line))
                    .collect::<Vec<_>>()
                    .join("\n"),
                Err(e) => format!("Error reading '{}': {}", path.display(), e),
            }
        }

        "write_file" => {
            let (Some(rel), Some(content)) = (
                args.get("path").and_then(|v| v.as_str()),
                args.get("content").and_then(|v| v.as_str()),
            ) else {
                return "Error: missing 'path' or 'content' argument".to_string();
            };
            let rel = rel.trim_start_matches('/');
            if rel.contains("..") {
                return "Error: path traversal ('..') is not allowed".to_string();
            }
            let path = root.join(rel);
            if let Some(parent) = path.parent() {
                if let Err(e) = std::fs::create_dir_all(parent) {
                    return format!("Error creating directories for {rel}: {e}");
                }
            }
            match std::fs::write(&path, content) {
                Ok(_) => format!("Successfully wrote {} bytes to {rel}", content.len()),
                Err(e) => format!("Error writing {rel}: {e}"),
            }
        }

        "list_files" => {
            let rel = args.get("path").and_then(|v| v.as_str()).unwrap_or(".");
            let rel = rel.trim_start_matches('/');
            let path = root.join(rel);
            eprintln!("[tool] list_files: {:?}", path);
            match std::fs::read_dir(&path) {
                Ok(entries) => {
                    let mut items: Vec<String> = entries
                        .filter_map(|e| {
                            let e = e.ok()?;
                            let name = e.file_name().to_string_lossy().to_string();
                            let is_dir = e.file_type().ok()?.is_dir();
                            Some(if is_dir { format!("{name}/") } else { name })
                        })
                        .collect();
                    items.sort();
                    if items.is_empty() {
                        format!("{}: (empty directory)", path.display())
                    } else {
                        items.join("\n")
                    }
                }
                Err(e) => format!("Error listing '{}': {}", path.display(), e),
            }
        }

        "run_command" => {
            let Some(cmd_str) = args.get("command").and_then(|v| v.as_str()) else {
                return "Error: missing 'command' argument".to_string();
            };

            let allowed_prefixes = [
                "git status",
                "git diff",
                "git log",
                "git branch",
                "git show",
                "git rev-parse",
                "git add",
                "git commit",
                "git push",
                "git fetch",
                "git pull",
                "git checkout",
                "git stash",
                "gh pr create",
                "gh pr list",
                "gh pr view",
                "gh pr merge",
                "gh pr checks",
                "gh pr comment",
                "gh pr edit",
                "gh pr close",
                "gh pr reopen",
                "gh pr diff",
                "gh repo view",
                "gh auth status",
            ];
            if !allowed_prefixes
                .iter()
                .any(|p| cmd_str.trim_start().starts_with(p))
            {
                return format!(
                    "Error: command not allowed. Permitted: git (status/diff/log/branch/show/rev-parse/add/commit/push/fetch/pull/checkout/stash) and gh pr/repo commands."
                );
            }

            let parts = shell_split(cmd_str);
            let (prog, rest) = match parts.split_first() {
                Some(s) => s,
                None => return "Error: empty command".to_string(),
            };

            match std::process::Command::new(prog)
                .args(rest)
                .current_dir(root)
                .output()
            {
                Ok(out) => {
                    let stdout = String::from_utf8_lossy(&out.stdout);
                    let stderr = String::from_utf8_lossy(&out.stderr);
                    if !out.status.success() && stdout.is_empty() {
                        format!("Exit {}: {}", out.status, stderr)
                    } else if stdout.is_empty() {
                        "(no output)".to_string()
                    } else {
                        stdout.to_string()
                    }
                }
                Err(e) => format!("Error running command: {e}"),
            }
        }

        "search_in_file" => {
            let (Some(rel), Some(pattern)) = (
                args.get("path").and_then(|v| v.as_str()),
                args.get("pattern").and_then(|v| v.as_str()),
            ) else {
                return "Error: missing 'path' or 'pattern' argument".to_string();
            };
            let path = root.join(rel);
            let content = match std::fs::read_to_string(&path) {
                Ok(c) => c,
                Err(e) => return format!("Error reading {rel}: {e}"),
            };

            let re = match regex::Regex::new(pattern) {
                Ok(r) => r,
                Err(_) => {
                    let matches: Vec<String> = content
                        .lines()
                        .enumerate()
                        .filter(|(_, line)| line.contains(pattern))
                        .map(|(i, line)| format!("{:>4}: {}", i + 1, line))
                        .collect();
                    if matches.is_empty() {
                        return format!("No matches for '{pattern}' in {rel}");
                    }
                    return matches.join("\n");
                }
            };

            let matches: Vec<String> = content
                .lines()
                .enumerate()
                .filter(|(_, line)| re.is_match(line))
                .map(|(i, line)| format!("{:>4}: {}", i + 1, line))
                .collect();

            if matches.is_empty() {
                format!("No matches for '{pattern}' in {rel}")
            } else {
                matches.join("\n")
            }
        }

        other => format!("Error: unknown tool '{other}'"),
    }
}

/// Build a human-readable label for a tool call event.
pub fn tool_label(name: &str, args: &Value) -> String {
    match name {
        "read_file" => {
            let path = args.get("path").and_then(|v| v.as_str()).unwrap_or("?");
            let filename = std::path::Path::new(path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or(path);
            format!("Reading {filename}")
        }
        "write_file" => {
            let path = args.get("path").and_then(|v| v.as_str()).unwrap_or("?");
            let filename = std::path::Path::new(path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or(path);
            format!("Editing {filename}")
        }
        "list_files" => {
            let path = args.get("path").and_then(|v| v.as_str()).unwrap_or(".");
            if path == "." || path.is_empty() {
                "Listing files".to_string()
            } else {
                format!("Listing {path}")
            }
        }
        "search_in_file" => {
            let pattern = args.get("pattern").and_then(|v| v.as_str()).unwrap_or("?");
            format!("Searching for '{pattern}'")
        }
        "run_command" => {
            let cmd = args.get("command").and_then(|v| v.as_str()).unwrap_or("?");
            let trimmed = cmd.trim();

            if trimmed.starts_with("git add") {
                "Staging changes".to_string()
            } else if trimmed.starts_with("git commit") {
                if let Some(msg_start) = trimmed.find("-m \"").or_else(|| trimmed.find("-m '")) {
                    let rest = &trimmed[msg_start + 4..];
                    let msg = rest.trim_end_matches('"').trim_end_matches('\'');
                    let short = if msg.len() > 60 { &msg[..60] } else { msg };
                    format!("Committing: {short}")
                } else {
                    "Committing changes".to_string()
                }
            } else if trimmed.starts_with("git push") {
                "Pushing to remote".to_string()
            } else if trimmed.starts_with("git status") {
                "Checking git status".to_string()
            } else if trimmed.starts_with("git diff") {
                "Reading diff".to_string()
            } else if trimmed.starts_with("git log") {
                "Reading git log".to_string()
            } else if trimmed.starts_with("git checkout") || trimmed.starts_with("git switch") {
                "Switching branch".to_string()
            } else if trimmed.starts_with("git merge") {
                "Merging branch".to_string()
            } else if trimmed.starts_with("git stash") {
                "Stashing changes".to_string()
            } else if trimmed.starts_with("git fetch") {
                "Fetching from remote".to_string()
            } else if trimmed.starts_with("git pull") {
                "Pulling from remote".to_string()
            } else if trimmed.starts_with("git rebase") {
                "Rebasing branch".to_string()
            } else if trimmed.starts_with("git rev-parse") || trimmed.starts_with("git branch") {
                "Reading branch info".to_string()
            } else if trimmed.starts_with("gh pr create") {
                "Creating pull request".to_string()
            } else if trimmed.starts_with("gh pr merge") {
                "Merging pull request".to_string()
            } else if trimmed.starts_with("gh pr") {
                "Checking pull request".to_string()
            } else if trimmed.starts_with("gh issue") {
                "Checking issue".to_string()
            } else if trimmed.starts_with("npm install")
                || trimmed.starts_with("pnpm install")
                || trimmed.starts_with("yarn install")
            {
                "Installing dependencies".to_string()
            } else if trimmed.starts_with("npm run")
                || trimmed.starts_with("pnpm run")
                || trimmed.starts_with("yarn run")
            {
                let script = trimmed.splitn(3, ' ').nth(2).unwrap_or("script");
                format!("Running {script}")
            } else if trimmed.starts_with("cargo build") {
                "Building project".to_string()
            } else if trimmed.starts_with("cargo test")
                || trimmed.starts_with("php artisan test")
                || trimmed.starts_with("pytest")
            {
                "Running tests".to_string()
            } else if trimmed.starts_with("cat ")
                || trimmed.starts_with("head ")
                || trimmed.starts_with("tail ")
            {
                let file = trimmed.split_whitespace().last().unwrap_or("file");
                let filename = std::path::Path::new(file)
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or(file);
                format!("Reading {filename}")
            } else if trimmed.starts_with("mkdir") {
                "Creating directory".to_string()
            } else if trimmed.starts_with("rm ") || trimmed.starts_with("rm -") {
                "Removing files".to_string()
            } else if trimmed.starts_with("cp ") || trimmed.starts_with("mv ") {
                "Moving files".to_string()
            } else if trimmed.starts_with("find ") || trimmed.starts_with("ls ") || trimmed == "ls"
            {
                "Listing files".to_string()
            } else if trimmed.starts_with("grep ") || trimmed.starts_with("rg ") {
                "Searching code".to_string()
            } else {
                let short = if trimmed.len() > 60 {
                    &trimmed[..60]
                } else {
                    trimmed
                };
                format!("run: {short}")
            }
        }
        other => other.to_string(),
    }
}
