import Foundation

enum WorkSuggestionColumns {
    static let createTable = """
        CREATE TABLE IF NOT EXISTS work_suggestions (
            id TEXT PRIMARY KEY,
            workspace_id TEXT REFERENCES workspaces(id) ON DELETE CASCADE,
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            anchor_seq INTEGER,
            title TEXT NOT NULL,
            why TEXT NOT NULL,
            prompt TEXT NOT NULL,
            target_kind TEXT NOT NULL,
            target_value TEXT NOT NULL DEFAULT '',
            state TEXT NOT NULL,
            started_id TEXT,
            started_name TEXT,
            failure TEXT,
            created_at REAL NOT NULL,
            decided_at REAL
        );
        CREATE INDEX IF NOT EXISTS work_suggestions_workspace ON work_suggestions(workspace_id);
        CREATE INDEX IF NOT EXISTS work_suggestions_undecided ON work_suggestions(workspace_id, session_id)
            WHERE state IN ('pending', 'starting');
        CREATE INDEX IF NOT EXISTS work_suggestions_session ON work_suggestions(session_id);
        """

    static let insert = """
        INSERT INTO work_suggestions
            (id, workspace_id, session_id, anchor_seq, title, why, prompt, target_kind, target_value,
             state, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)
        """

    private static let undecided = "work_suggestions.state IN ('pending', 'starting')"

    static let deleteAnchored = "DELETE FROM work_suggestions WHERE session_id = ? AND anchor_seq >= ?"

    private static let liveChat = """
        JOIN sessions ON sessions.id = work_suggestions.session_id AND sessions.archived_at IS NULL
        """

    static let undecidedInWorkspace = """
        SELECT COUNT(*) AS c FROM work_suggestions \(liveChat)
        WHERE work_suggestions.workspace_id = ? AND \(undecided)
        """

    static let undecidedInChat = """
        SELECT COUNT(*) AS c FROM work_suggestions \(liveChat)
        WHERE work_suggestions.workspace_id IS NULL AND work_suggestions.session_id = ? AND \(undecided)
        """

    static let undecidedByWorkspace = """
        SELECT work_suggestions.workspace_id AS w, COUNT(*) AS c FROM work_suggestions \(liveChat)
        WHERE work_suggestions.workspace_id IS NOT NULL AND \(undecided)
        GROUP BY work_suggestions.workspace_id
        """

    static func values(_ suggestion: WorkSuggestion) -> [SQLValue] {
        let target = encode(suggestion.target)
        return [
            .text(suggestion.id),
            .text(suggestion.workspaceID),
            .text(suggestion.sessionID),
            suggestion.anchorSeq.map { .int(Int64($0)) } ?? .null,
            .text(suggestion.title),
            .text(suggestion.why),
            .text(suggestion.prompt),
            .text(target.kind),
            .text(target.value),
            .double(suggestion.createdAt.timeIntervalSince1970),
        ]
    }

    static func encode(_ target: WorkSuggestion.Target) -> (kind: String, value: String) {
        switch target {
        case .sameProject: ("same_project", "")
        case .project(let id): ("project", id.rawValue)
        case .folder(let path): ("folder", path)
        case .remote(let slug): ("remote", slug)
        case .orchestrator(let id): ("orchestrator", id.rawValue)
        }
    }

    static func encode(_ state: WorkSuggestion.State) -> (kind: String, id: SQLValue, name: SQLValue) {
        switch state {
        case .pending: ("pending", .null, .null)
        case .starting: ("starting", .null, .null)
        case .startedWorkspace(let id, let name): ("started_workspace", .text(id), .text(name))
        case .startedHere(let id, let name): ("started_here", .text(id), .text(name))
        case .dismissed: ("dismissed", .null, .null)
        case .withdrawn: ("withdrawn", .null, .null)
        }
    }

    static func suggestion(from row: Row) -> WorkSuggestion {
        WorkSuggestion(
            stored: WorkSuggestionID(row.string("id") ?? newID()),
            workspaceID: row.string("workspace_id").map(WorkspaceID.init),
            sessionID: SessionID(row.string("session_id") ?? ""),
            anchorSeq: row.int("anchor_seq").map(Int.init),
            title: row.string("title") ?? "",
            why: row.string("why") ?? "",
            prompt: row.string("prompt") ?? "",
            target: target(kind: row.string("target_kind"), value: row.string("target_value") ?? ""),
            state: state(
                kind: row.string("state"), id: row.string("started_id"), name: row.string("started_name")
            ),
            failure: row.string("failure"),
            createdAt: row.date("created_at") ?? Date(),
            decidedAt: row.date("decided_at")
        )
    }

    private static func target(kind: String?, value: String) -> WorkSuggestion.Target {
        switch kind {
        case "project": .project(RepoID(value))
        case "folder": .folder(value)
        case "remote": .remote(value)
        case "orchestrator": .orchestrator(RepoID(value))
        default: .sameProject
        }
    }

    private static func state(kind: String?, id: String?, name: String?) -> WorkSuggestion.State {
        switch kind {
        case "starting": .starting
        case "started_workspace": .startedWorkspace(WorkspaceID(id ?? ""), name: name ?? "")
        case "started_here": .startedHere(SessionID(id ?? ""), name: name ?? "")
        case "dismissed": .dismissed
        case "withdrawn": .withdrawn
        default: .pending
        }
    }
}
