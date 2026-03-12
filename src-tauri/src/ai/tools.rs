use serde_json::{json, Value};

// ---------------------------------------------------------------------------
// Tool definitions (three wire-format variants)
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Tool executor
// ---------------------------------------------------------------------------

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

            // Security allowlist — git read-only + write operations needed for PR workflow.
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
                "gh auth status",
            ];
            if !allowed_prefixes
                .iter()
                .any(|p| cmd_str.trim_start().starts_with(p))
            {
                return format!(
                    "Error: command not allowed. Permitted: git (status/diff/log/branch/show/rev-parse/add/commit/push/fetch/pull/checkout/stash) and gh pr commands."
                );
            }

            let parts: Vec<&str> = cmd_str.split_whitespace().collect();
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
        "read_file" => format!(
            "read_file: {}",
            args.get("path").and_then(|v| v.as_str()).unwrap_or("?")
        ),
        "write_file" => format!(
            "write_file: {}",
            args.get("path").and_then(|v| v.as_str()).unwrap_or("?")
        ),
        "list_files" => format!(
            "list_files: {}",
            args.get("path").and_then(|v| v.as_str()).unwrap_or(".")
        ),
        "run_command" => format!(
            "run: {}",
            args.get("command").and_then(|v| v.as_str()).unwrap_or("?")
        ),
        "search_in_file" => format!(
            "search '{}' in {}",
            args.get("pattern").and_then(|v| v.as_str()).unwrap_or("?"),
            args.get("path").and_then(|v| v.as_str()).unwrap_or("?")
        ),
        other => other.to_string(),
    }
}
