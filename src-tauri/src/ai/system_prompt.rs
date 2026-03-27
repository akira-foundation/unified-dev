/// Walks `root` up to `max_depth` levels, collecting relative paths of all
/// files (skipping common noise dirs). Returns a sorted, newline-separated
/// tree string suitable for embedding in a system prompt.
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

    format!(
        "You are an AI coding agent working on the repository '{repo_name}' (branch: {branch}).\n\
         Workspace path: {workspace_path}\n\n\
         You have tools to read and write files, run git commands, and rename the workspace. \
         ALWAYS use your tools to actually perform the requested task — never just describe what you would do. \
         When asked to modify a file, read it first, then write the changes back with write_file. \
         When asked about code, read the relevant files before answering. \
         When asked to rename the workspace, thread, or folder, use the rename_workspace tool directly — do NOT use git branch commands for this. \
         If a rename_workspace tool is not available in your environment, output a line in this exact format on its own line: RENAME_WORKSPACE:<new_name> (e.g. RENAME_WORKSPACE:graph-inspector). The name must contain only letters, digits, hyphens, and underscores.\n\n\
         Before each tool call, write one short sentence (e.g. \"Reading config file...\", \"Applying changes to src/main.rs...\") \
         so the user can follow your progress. Keep these messages brief and factual.\
         {runtime_modes}{tree_section}{plan_section}"
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
