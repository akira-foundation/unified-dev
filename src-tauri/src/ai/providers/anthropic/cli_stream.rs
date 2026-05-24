use std::collections::HashMap;

use serde_json::Value;
use tauri::AppHandle;

use crate::app::chat::stream::{emit_tool_call, StreamToolCallPayload};

const MAX_LABEL_ARG: usize = 80;

pub fn emit_tool_use(app: &AppHandle, thread_id: &str, item: &Value, labels: &mut HashMap<String, String>) {
    let name = item.get("name").and_then(|n| n.as_str()).unwrap_or("tool");
    let label = tool_label(name, item.get("input").unwrap_or(&Value::Null));
    if let Some(id) = item.get("id").and_then(|i| i.as_str()) {
        labels.insert(id.to_string(), label.clone());
    }
    emit_tool_call(app, StreamToolCallPayload {
        thread_id: thread_id.to_string(),
        label,
        status: "running".to_string(),
        output: None,
    });
}

pub fn emit_tool_result(app: &AppHandle, thread_id: &str, item: &Value, labels: &mut HashMap<String, String>) {
    let id = item.get("tool_use_id").and_then(|i| i.as_str()).unwrap_or("");
    let label = labels.remove(id).unwrap_or_else(|| "tool".to_string());
    let output = item.get("content").map(tool_result_text).unwrap_or_default();
    emit_tool_call(app, StreamToolCallPayload {
        thread_id: thread_id.to_string(),
        label,
        status: "done".to_string(),
        output: Some(output),
    });
}

pub fn tool_label(name: &str, input: &Value) -> String {
    let arg = match name {
        "Bash" => input.get("command").and_then(|v| v.as_str()),
        "Read" | "Write" | "Edit" => input.get("file_path").and_then(|v| v.as_str()),
        "Grep" | "Glob" => input.get("pattern").and_then(|v| v.as_str()),
        "LS" => input.get("path").and_then(|v| v.as_str()),
        _ => None,
    };

    match arg {
        Some(a) if !a.trim().is_empty() => {
            let first_line = a.lines().next().unwrap_or(a).trim();
            let truncated: String = first_line.chars().take(MAX_LABEL_ARG).collect();
            let suffix = if first_line.chars().count() > MAX_LABEL_ARG { "…" } else { "" };
            format!("{name}: {truncated}{suffix}")
        }
        _ => name.to_string(),
    }
}

pub fn tool_result_text(content: &Value) -> String {
    if let Some(s) = content.as_str() {
        return s.to_string();
    }
    if let Some(arr) = content.as_array() {
        let mut out = String::new();
        for block in arr {
            if block.get("type").and_then(|t| t.as_str()) == Some("text") {
                if let Some(t) = block.get("text").and_then(|t| t.as_str()) {
                    out.push_str(t);
                }
            }
        }
        return out;
    }
    String::new()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn tool_label_uses_command_for_bash() {
        let input = json!({ "command": "git status" });
        assert_eq!(tool_label("Bash", &input), "Bash: git status");
    }

    #[test]
    fn tool_label_uses_file_path_for_read() {
        let input = json!({ "file_path": "src/main.rs" });
        assert_eq!(tool_label("Read", &input), "Read: src/main.rs");
    }

    #[test]
    fn tool_label_uses_pattern_for_grep() {
        let input = json!({ "pattern": "TODO" });
        assert_eq!(tool_label("Grep", &input), "Grep: TODO");
    }

    #[test]
    fn tool_label_takes_first_line_only() {
        let input = json!({ "command": "git commit -m \"a\"\nsecond line" });
        assert_eq!(tool_label("Bash", &input), "Bash: git commit -m \"a\"");
    }

    #[test]
    fn tool_label_truncates_long_arg() {
        let long = "x".repeat(120);
        let input = json!({ "command": long });
        let label = tool_label("Bash", &input);
        assert!(label.ends_with('…'));
        assert!(label.chars().count() <= MAX_LABEL_ARG + "Bash: ".len() + 1);
    }

    #[test]
    fn tool_label_falls_back_to_name_when_arg_missing() {
        assert_eq!(tool_label("Bash", &json!({})), "Bash");
        assert_eq!(tool_label("UnknownTool", &json!({ "x": 1 })), "UnknownTool");
    }

    #[test]
    fn tool_result_text_handles_plain_string() {
        assert_eq!(tool_result_text(&json!("done")), "done");
    }

    #[test]
    fn tool_result_text_concatenates_text_blocks() {
        let content = json!([
            { "type": "text", "text": "line 1\n" },
            { "type": "image", "source": {} },
            { "type": "text", "text": "line 2" }
        ]);
        assert_eq!(tool_result_text(&content), "line 1\nline 2");
    }

    #[test]
    fn tool_result_text_empty_for_other_shapes() {
        assert_eq!(tool_result_text(&json!({ "x": 1 })), "");
    }
}
