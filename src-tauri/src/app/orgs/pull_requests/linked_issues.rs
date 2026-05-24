use std::sync::OnceLock;

use regex::Regex;

fn closing_keyword_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"(?i)\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\b\s*:?\s+#(\d+)").unwrap()
    })
}

pub fn parse_closing_issue_numbers(body: Option<&str>) -> Vec<u64> {
    let Some(text) = body else {
        return Vec::new();
    };

    let mut numbers = Vec::new();
    for capture in closing_keyword_re().captures_iter(text) {
        if let Some(num) = capture.get(1).and_then(|m| m.as_str().parse::<u64>().ok()) {
            if !numbers.contains(&num) {
                numbers.push(num);
            }
        }
    }
    numbers
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn returns_empty_for_none() {
        assert!(parse_closing_issue_numbers(None).is_empty());
    }

    #[test]
    fn returns_empty_without_keyword() {
        assert!(parse_closing_issue_numbers(Some("see #12 for context")).is_empty());
    }

    #[test]
    fn parses_all_keyword_variants() {
        let body = "Closes #1\nfix #2\nFixes #3\nresolved #4\nclose #5\nfixed #6";
        assert_eq!(parse_closing_issue_numbers(Some(body)), vec![1, 2, 3, 4, 5, 6]);
    }

    #[test]
    fn is_case_insensitive_and_allows_colon() {
        assert_eq!(parse_closing_issue_numbers(Some("CLOSES: #42")), vec![42]);
    }

    #[test]
    fn dedups_repeated_numbers() {
        assert_eq!(
            parse_closing_issue_numbers(Some("Closes #7 and also fixes #7")),
            vec![7]
        );
    }

    #[test]
    fn ignores_keyword_substring() {
        assert!(parse_closing_issue_numbers(Some("disclosed #9")).is_empty());
    }
}
