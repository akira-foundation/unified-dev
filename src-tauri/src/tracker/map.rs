use omnitrack::{
    issue_draft, issue_filter, issue_patch, pagination, Comment, Cycle, Issue, IssueDraft,
    IssueFilter, IssuePatch, Label, Milestone, Page, PageCursor, PageRequest, Project, Team, User,
};

use super::dto::{
    TrackerComment, TrackerIssue, TrackerIssueDraft, TrackerIssueFilter, TrackerIssuePatch,
    TrackerNamed, TrackerPage, TrackerPageRequest,
};

pub fn map_issue(issue: &Issue) -> TrackerIssue {
    TrackerIssue {
        id: issue.id().as_str().to_string(),
        identifier: issue.identifier().map(str::to_string),
        title: issue.title().to_string(),
        description: issue.description().map(str::to_string),
        url: issue.url().map(str::to_string),
        status: issue.status().to_string(),
        category: issue.category(),
        project: issue.project().map(|p| p.as_str().to_string()),
        milestone: issue.milestone().map(|m| m.as_str().to_string()),
        team: issue.team().map(|t| t.as_str().to_string()),
        assignee: issue.assignee().map(|a| a.as_str().to_string()),
        author: issue.author().map(|a| a.as_str().to_string()),
        labels: issue
            .labels()
            .iter()
            .map(|l| l.as_str().to_string())
            .collect(),
        priority: issue.priority(),
        created_at: issue.created_at().map(str::to_string),
        updated_at: issue.updated_at().to_string(),
        project_name: None,
        milestone_name: None,
        team_name: None,
        assignee_name: None,
        author_name: None,
        label_names: Vec::new(),
    }
}

pub fn map_project(entity: &Project) -> TrackerNamed {
    TrackerNamed {
        id: entity.id().as_str().to_string(),
        name: entity.name().to_string(),
    }
}

pub fn map_milestone(entity: &Milestone) -> TrackerNamed {
    TrackerNamed {
        id: entity.id().as_str().to_string(),
        name: entity.name().to_string(),
    }
}

pub fn map_team(entity: &Team) -> TrackerNamed {
    TrackerNamed {
        id: entity.id().as_str().to_string(),
        name: entity.name().to_string(),
    }
}

pub fn map_user(entity: &User) -> TrackerNamed {
    TrackerNamed {
        id: entity.id().as_str().to_string(),
        name: entity.name().to_string(),
    }
}

pub fn map_label(entity: &Label) -> TrackerNamed {
    TrackerNamed {
        id: entity.id().as_str().to_string(),
        name: entity.name().to_string(),
    }
}

#[allow(dead_code)]
pub fn map_cycle(entity: &Cycle) -> TrackerNamed {
    TrackerNamed {
        id: entity.id().as_str().to_string(),
        name: entity.name().to_string(),
    }
}

#[allow(dead_code)]
pub fn map_comment(c: &Comment) -> TrackerComment {
    TrackerComment {
        id: c.id().as_str().to_string(),
        body: c.body().to_string(),
        author: c.author().map(|a| a.as_str().to_string()),
        created_at: c.created_at().map(str::to_string),
    }
}

pub fn map_page<T, U>(page: Page<T>, mapper: impl Fn(&T) -> U) -> TrackerPage<U> {
    let next = page.next().map(|cursor| cursor.as_str().to_string());
    let items = page.items().iter().map(mapper).collect();
    TrackerPage { items, next }
}

pub fn to_page_request(request: &TrackerPageRequest) -> Option<PageRequest> {
    if request.after.is_none() && request.limit.is_none() {
        return None;
    }
    let mut builder = pagination();
    if let Some(after) = &request.after {
        builder = builder.after(PageCursor::make(after.clone()));
    }
    if let Some(limit) = request.limit {
        builder = builder.limit(limit);
    }
    Some(builder.build())
}

pub fn to_filter(filter: &TrackerIssueFilter) -> IssueFilter {
    let mut builder = issue_filter();
    if let Some(team) = &filter.team {
        builder = builder.team(team.clone());
    }
    if let Some(project) = &filter.project {
        builder = builder.project(project.clone());
    }
    if let Some(assignee) = &filter.assignee {
        builder = builder.assignee(assignee.clone());
    }
    if let Some(category) = filter.category {
        builder = builder.category(category);
    }
    builder.build()
}

pub fn to_draft(draft: TrackerIssueDraft) -> IssueDraft {
    let mut builder = issue_draft().team(draft.team).title(draft.title);
    if let Some(status) = draft.status {
        builder = builder.status(status);
    }
    if let Some(category) = draft.category {
        builder = builder.category(category);
    }
    if let Some(project) = draft.project {
        builder = builder.project(project);
    }
    if let Some(milestone) = draft.milestone {
        builder = builder.milestone(milestone);
    }
    if let Some(assignee) = draft.assignee {
        builder = builder.assignee(assignee);
    }
    if let Some(priority) = draft.priority {
        builder = builder.priority(priority);
    }
    builder.build()
}

pub fn to_patch(patch: TrackerIssuePatch) -> IssuePatch {
    let mut builder = issue_patch();
    if let Some(title) = patch.title {
        builder = builder.title(title);
    }
    if let Some(category) = patch.category {
        builder = builder.category(category);
    }
    if let Some(project) = patch.project {
        builder = builder.project(project);
    }
    if let Some(milestone) = patch.milestone {
        builder = builder.milestone(milestone);
    }
    if let Some(assignee) = patch.assignee {
        builder = builder.assignee(assignee);
    }
    if let Some(priority) = patch.priority {
        builder = builder.priority(priority);
    }
    builder.build()
}

#[cfg(test)]
mod tests {
    use super::*;
    use omnitrack::{issue, StatusCategory};

    #[test]
    fn maps_enriched_issue_to_dto() {
        let built = issue()
            .id("ISS-1")
            .title("Fix")
            .status("In Progress")
            .identifier("ENG-1")
            .category(StatusCategory::Started)
            .team("TEAM-1")
            .labels(["L-1", "L-2"])
            .updated_at("t1")
            .build();

        let dto = map_issue(&built);

        assert_eq!(dto.id, "ISS-1");
        assert_eq!(dto.identifier.as_deref(), Some("ENG-1"));
        assert_eq!(dto.category, Some(StatusCategory::Started));
        assert_eq!(dto.team.as_deref(), Some("TEAM-1"));
        assert_eq!(dto.labels, vec!["L-1", "L-2"]);
        assert_eq!(dto.updated_at, "t1");
    }

    #[test]
    fn draft_dto_requires_team_and_title() {
        let draft = TrackerIssueDraft {
            team: "TEAM-1".into(),
            title: "New".into(),
            status: None,
            category: Some(StatusCategory::Unstarted),
            project: None,
            milestone: None,
            assignee: None,
            priority: Some(2),
        };

        let core = to_draft(draft);
        assert_eq!(core.team().as_str(), "TEAM-1");
        assert_eq!(core.title(), "New");
        assert_eq!(core.category(), Some(StatusCategory::Unstarted));
        assert_eq!(core.priority(), Some(2));
    }

    #[test]
    fn empty_filter_is_empty() {
        assert!(to_filter(&TrackerIssueFilter::default()).is_empty());
    }
}
