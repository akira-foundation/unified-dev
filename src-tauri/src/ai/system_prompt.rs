pub fn collect_file_tree(root: &std::path::Path, max_depth: usize) -> String {
    let ignore = [
        ".git",
        "node_modules",
        "target",
        ".next",
        "dist",
        "build",
        ".cache",
        "__pycache__",
        ".venv",
        "venv",
        ".idea",
        ".vscode",
    ];

    let mut entries: Vec<String> = Vec::new();

    fn walk(
        dir: &std::path::Path,
        root: &std::path::Path,
        depth: usize,
        max_depth: usize,
        ignore: &[&str],
        entries: &mut Vec<String>,
    ) {
        if depth > max_depth {
            return;
        }
        let Ok(iter) = std::fs::read_dir(dir) else {
            return;
        };
        let mut children: Vec<std::path::PathBuf> =
            iter.filter_map(|e| e.ok().map(|e| e.path())).collect();
        children.sort();

        for path in children {
            let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
            if name.starts_with('.') && name != ".env" {
                continue;
            }
            if ignore.contains(&name) {
                continue;
            }
            if let Ok(rel) = path.strip_prefix(root) {
                let rel_str = rel.to_string_lossy().to_string();
                if path.is_dir() {
                    entries.push(format!("{rel_str}/"));
                    walk(&path, root, depth + 1, max_depth, ignore, entries);
                } else {
                    entries.push(rel_str);
                }
            }
        }
    }

    walk(root, root, 0, max_depth, &ignore, &mut entries);
    entries.join("\n")
}

pub fn build_system_prompt(
    repo_name: &str,
    workspace_path: &str,
    branch: &str,
    model: &str,
    plan_mode: bool,
    thinking_budget: &str,
    fast_mode: bool,
    skills: &[(String, String)],
    mcp_tools: &[crate::app::mcp::McpTool],
    mcp_disconnected_servers: &[crate::app::mcp::McpServer],
) -> String {
    let root = std::path::Path::new(workspace_path);
    let file_tree = collect_file_tree(root, 4);

    let tree_section = if file_tree.is_empty() {
        String::new()
    } else {
        format!("\n\nRepository file tree:\n```\n{file_tree}\n```")
    };

    let plan_section = if plan_mode {
        "\n\nPLAN MODE IS ACTIVE. Before making any changes or running any tools, you MUST:\n\
         1. Outline your full plan step by step in a numbered list.\n\
         2. End with: \"Ready to proceed — confirm to start.\"\n\
         3. Wait for the user's confirmation before taking any action.\n\
         If asked whether you are in plan mode, answer: yes."
    } else {
        ""
    };

    let runtime_modes = format!(
        "\n\nCurrent runtime configuration:\n- Model: {}\n- Plan mode: {}\n- Thinking budget: {}\n- Response mode: {}\n\
         If the user asks which of these modes is active, answer using this configuration.",
        model,
        if plan_mode { "active" } else { "inactive" },
        if thinking_budget == "not-available" {
            "not available"
        } else {
            thinking_budget
        },
        if fast_mode { "fast" } else { "standard" },
    );

    let skills_section = if skills.is_empty() {
        String::new()
    } else {
        let blocks: String = skills
            .iter()
            .map(|(name, content)| format!("\n\n## Skill: {name}\n\n{content}"))
            .collect();
        format!("\n\n---\nThe following skill instructions are active for this session. Follow them carefully:{blocks}")
    };

    let mcp_section = if mcp_tools.is_empty() {
        String::new()
    } else {
        let mut by_server: std::collections::BTreeMap<&str, Vec<&crate::app::mcp::McpTool>> =
            std::collections::BTreeMap::new();
        for tool in mcp_tools {
            by_server.entry(&tool.server_id).or_default().push(tool);
        }

        let server_blocks: String = by_server
            .iter()
            .map(|(server_id, tools)| {
                let tool_list = tools
                    .iter()
                    .map(|t| {
                        let desc = t.description.as_deref().unwrap_or("");
                        format!("    - `{}`: {}", t.name, desc)
                    })
                    .collect::<Vec<_>>()
                    .join("\n");
                format!("  Server: {server_id}\n{tool_list}")
            })
            .collect::<Vec<_>>()
            .join("\n\n");

        format!(
            "\n\n## MCP TOOLS — ALREADY AUTHENTICATED AND READY\n\
             The following external service tools are connected, authenticated, and available as callable tools.\
             \nDo NOT ask the user to authenticate. Do NOT generate OAuth URLs. Do NOT say authentication is needed.\
             \nThe OAuth flow is already complete. Call the tools directly when the user explicitly requests an action that requires them.\
             \nIMPORTANT: Only call these tools when the user clearly requests an action that requires them. \
             Do NOT call them proactively, speculatively, or in response to greetings/images/general questions.\
             \n\n{server_blocks}"
        )
    };

    let mcp_disconnected_section = if mcp_disconnected_servers.is_empty() {
        String::new()
    } else {
        let server_list: String = mcp_disconnected_servers
            .iter()
            .map(|s| format!("  - {} ({})", s.name, s.url))
            .collect::<Vec<_>>()
            .join("\n");
        format!(
            "\n\nThe following MCP servers are configured but NOT connected (no authentication token).\
             \nIf the user asks about tools from these services, instruct them to:\
             \n1. Click \"MCP\" in the left sidebar\
             \n2. Find the server and click \"Connect\"\
             \n3. Complete the OAuth login in the browser\
             \n4. Return here and retry their request\
             \n\nDo NOT attempt to generate OAuth URLs or perform authentication yourself.\
             \n\nDisconnected servers:\n{server_list}"
        )
    };

    format!(
        "You are an AI coding agent working on the repository '{repo_name}' (branch: {branch}).\n\
         Workspace path: {workspace_path}\n\n\
         You have tools to read and write files, run git commands, and rename the workspace. \
         ALWAYS use your tools to actually perform the requested task — never just describe what you would do. \
         When asked to modify a file, read it first, then write the changes back with write_file. \
         When asked about code, read the relevant files before answering. \
         When asked to rename the workspace, thread, or folder, use the rename_workspace tool directly — do NOT use git branch commands for this. \
         If a rename_workspace tool is not available in your environment, output a line in this exact format on its own line: RENAME_WORKSPACE:<new_name> (e.g. RENAME_WORKSPACE:graph-inspector). The name must contain only letters, digits, hyphens, and underscores.\n\n\
         For general questions, greetings, or image analysis, respond directly without calling any tools. \
         Only call tools when the user explicitly requests a file/code operation or an action that requires a specific tool.\n\n\
         Before each tool call, write one short sentence (e.g. \"Reading config file...\", \"Applying changes to src/main.rs...\") \
         so the user can follow your progress. Keep these messages brief and factual.\
         {runtime_modes}{tree_section}{skills_section}{mcp_disconnected_section}{mcp_section}{plan_section}"
    )
}

pub fn build_action_system_prompt(repo_name: &str, workspace_path: &str, branch: &str) -> String {
    let root = std::path::Path::new(workspace_path);
    let file_tree = collect_file_tree(root, 4);

    let tree_section = if file_tree.is_empty() {
        String::new()
    } else {
        format!("\n\nRepository file tree:\n```\n{file_tree}\n```")
    };

    format!(
        "You are an autonomous git automation agent operating on the repository '{repo_name}' (branch: {branch}).\n\
         Workspace path: {workspace_path}\n\n\
         CRITICAL RULES — follow these exactly:\n\
         1. Execute ALL requested shell commands immediately using your tools. Do NOT ask for permission or confirmation.\n\
         2. Do NOT explain what you are about to do. Do NOT list steps. Just run the commands.\n\
         3. You have FULL read and write access to the filesystem and shell. git, gh, and all standard tools are available.\n\
         4. Never say you 'cannot' run a command. You can run any shell command via your bash/run_command tool.\n\
         5. When done, output only the final result (e.g. the PR URL). Nothing else.\n\
         6. NEVER write intermediate helper files (e.g. PR_TITLE.txt, PR_BODY.md, COMMIT_MSG). \
            Pass all values inline as arguments to the command (e.g. gh pr create --title \"...\" --body \"...\").\
         {tree_section}"
    )
}
