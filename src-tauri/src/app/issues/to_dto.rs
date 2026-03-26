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
    }
}
