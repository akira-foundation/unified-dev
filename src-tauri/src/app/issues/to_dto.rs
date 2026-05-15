use crate::database::records::IssueRecord;
use crate::providers::dto::IssueDto;

pub fn record_to_dto(r: IssueRecord) -> IssueDto {
    let labels: Vec<String> = serde_json::from_str(&r.labels).unwrap_or_default();
    let label_colors: Vec<String> = serde_json::from_str(&r.label_colors).unwrap_or_default();
    let assignees: Vec<String> = serde_json::from_str(&r.assignees).unwrap_or_default();
    let linked_pr_numbers: Vec<u64> =
        serde_json::from_str(&r.linked_pr_numbers).unwrap_or_default();

    IssueDto {
        id: r.id,
        external_id: r.external_id,
        provider: r.provider,
        org_id: r.org_id,
        repo_name: r.repo_name,
        number: r.number,
        title: r.title,
        body: r.body,
        status: r.status,
        state_reason: r.state_reason,
        labels,
        label_colors,
        assignees,
        author: r.author,
        url: r.url,
        linked_pr_numbers,
        created_at: r.created_at,
        updated_at: r.updated_at,
        synced_at: r.synced_at,
        sync_with_provider: r.sync_with_provider,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_record() -> IssueRecord {
        IssueRecord {
            id: "id-1".into(),
            external_id: "ext-1".into(),
            provider: "github".into(),
            org_id: "org".into(),
            repo_name: "repo".into(),
            number: 42,
            title: "Bug".into(),
            body: Some("desc".into()),
            status: "open".into(),
            state_reason: None,
            labels: "[\"bug\",\"p1\"]".into(),
            label_colors: "[\"#ff0000\",\"#00ff00\"]".into(),
            assignees: "[\"alice\",\"bob\"]".into(),
            author: Some("carol".into()),
            url: "https://example.com/1".into(),
            linked_pr_numbers: "[10,20]".into(),
            created_at: "2026-01-01T00:00:00Z".into(),
            updated_at: "2026-01-02T00:00:00Z".into(),
            synced_at: "2026-01-03T00:00:00Z".into(),
            sync_with_provider: true,
        }
    }

    #[test]
    fn parses_valid_json_columns() {
        let dto = record_to_dto(sample_record());
        assert_eq!(dto.labels, vec!["bug", "p1"]);
        assert_eq!(dto.label_colors, vec!["#ff0000", "#00ff00"]);
        assert_eq!(dto.assignees, vec!["alice", "bob"]);
        assert_eq!(dto.linked_pr_numbers, vec![10u64, 20u64]);
        assert_eq!(dto.number, 42);
        assert_eq!(dto.status, "open");
    }

    #[test]
    fn falls_back_to_empty_on_invalid_json() {
        let mut rec = sample_record();
        rec.labels = "not-json".into();
        rec.label_colors = "{".into();
        rec.assignees = "".into();
        rec.linked_pr_numbers = "garbage".into();
        let dto = record_to_dto(rec);
        assert!(dto.labels.is_empty());
        assert!(dto.label_colors.is_empty());
        assert!(dto.assignees.is_empty());
        assert!(dto.linked_pr_numbers.is_empty());
    }

    #[test]
    fn preserves_optional_fields() {
        let mut rec = sample_record();
        rec.body = None;
        rec.author = None;
        rec.state_reason = Some("completed".into());
        let dto = record_to_dto(rec);
        assert!(dto.body.is_none());
        assert!(dto.author.is_none());
        assert_eq!(dto.state_reason.as_deref(), Some("completed"));
    }
}
