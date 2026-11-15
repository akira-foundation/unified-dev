import Foundation

public enum WorkspaceMergeTrouble: Sendable, Equatable {
    case unknownWorkspace(id: String, alias: Alias)
    case archived(workspace: String)
    case worktreeGone(workspace: String)
    case githubUnavailable(GitHubAccess)
    case githubSilent(String)
    case noPullRequest(workspace: String, branch: String)
    case blocked(workspace: String, number: Int, headline: String, reason: String)
    case localWork(workspace: String, number: Int, detail: String, needsCommit: Bool)
    case wouldQueue(workspace: String, hold: DeliveryHold)
    case appRefused(String)

    public enum Alias: Sendable, Equatable {
        case none
        case one(name: String, id: String)
        case several(name: String, count: Int)
    }

    public static let notYours = "Do not run `gh pr merge` yourself, or `bkt pr merge` on Bitbucket, to get past this, and do not "
        + "ask another agent to. Unified Dev sends a merge to the workspace's own agent so the owner "
        + "watches it happen; a merge run anywhere else is the same merge with nobody watching."

    public var sentence: String {
        (body + " " + Self.notYours)
    }

    private var body: String {
        switch self {
        case let .unknownWorkspace(id, alias):
            let opening = "Unified Dev has no workspace with the id '\(id)'."
            switch alias {
            case .none:
                return opening + " Call workspace_list and use the id it reports, not the name: "
                    + "two workspaces are allowed to share a name, so a name does not pick one out."
            case let .one(name, resolved):
                return opening + " '\(name)' is the NAME of a workspace Unified Dev has, and its id is "
                    + "'\(resolved)'. Workspaces are addressed by id here because two of them are "
                    + "allowed to share a name. Ask again with that id."
            case let .several(name, count):
                return opening + " \(count) workspaces are called '\(name)', which is exactly why "
                    + "this takes an id and not a name. Call workspace_list and pick the one you "
                    + "meant by its branch, then ask again with its id."
            }

        case .archived(let workspace):
            return """
                Unified Dev will not ask for a merge in '\(workspace)' because that workspace is \
                archived. Its worktree has been removed from disk and its agent is gone, so there \
                is no checkout to run a merge in and nobody to ask. Retrying will not help. If its \
                pull request is still open and should land, that is the owner's to decide.
                """

        case .worktreeGone(let workspace):
            return """
                Unified Dev will not ask for a merge in '\(workspace)' because its worktree is no longer \
                on disk, although Unified Dev still has it as an active workspace. Something moved or \
                deleted it outside Unified Dev. Retrying will not help. Tell the owner, and leave the \
                pull request alone until they have looked.
                """

        case .githubUnavailable(.notInstalled):
            return """
                Unified Dev cannot say what state that pull request is in, because `gh` is not installed \
                on this machine. It is what Unified Dev asks about pull requests and what the agent \
                would run to merge one, so there is nothing here that installing it around Unified Dev's \
                back would speed up. Retrying will not help. Tell the owner.
                """

        case .githubUnavailable(.signedOut), .githubUnavailable(.ready):
            return """
                Unified Dev cannot say what state that pull request is in, because `gh` is installed but \
                not signed in to GitHub. Retrying will not help until it is, and signing it in is \
                the owner's to do rather than yours: it is their account that would be merging. \
                Tell them, and say nothing about the pull request's state, because nothing was \
                read.
                """

        case .githubSilent(let message):
            let said = message.hasSuffix(".") ? message : message + "."
            return """
                Unified Dev asked GitHub what state that pull request is in and gh did not answer: \
                \(said) Nothing was sent, and nothing here says anything about the pull \
                request, because nothing was read. What gh said is the whole of what is known: if \
                it reads like a network or a rate limit, asking again in a minute is the right \
                thing, and if it does not, say so rather than working round it.
                """

        case let .noPullRequest(workspace, branch):
            return """
                Unified Dev will not ask for a merge in '\(workspace)' because GitHub has no pull \
                request for its branch '\(branch)'. There is nothing to merge yet. Do not open \
                one to make this call succeed: opening a pull request is a decision of its own, \
                with the project's own instructions behind it, and Unified Dev has a button for it that \
                the owner presses. If you think there should be one, say so and let them.
                """

        case let .blocked(workspace, number, headline, reason):
            return """
                Unified Dev will not ask for a merge of #\(number) in '\(workspace)'. GitHub reports it \
                as '\(headline)'. \(reason) Retrying will not help while that is true, and none of \
                it is something this call can change. Do not mark the pull request ready, re-run \
                or skip a check, dismiss a review, or touch a branch protection rule to get round \
                it: each of those is a change to a repository other people share, and a refusal is \
                an answer rather than an obstacle.
                """

        case let .localWork(workspace, number, detail, needsCommit):
            let next = needsCommit
                ? "commit and push it first"
                : "push it first"
            return """
                Unified Dev will not ask for a merge of #\(number) in '\(workspace)' because that \
                worktree is holding work GitHub has not got: \(detail). A merge lands what GitHub \
                has, so none of that would be part of it. Unified Dev's own Merge button does allow \
                this, and only because it puts that same sentence in a dialogue the owner has to \
                accept before anything is sent. There is nobody on this connection to accept it, \
                so the answer here is no. Tell the owner what is outstanding and let them decide \
                whether to merge over it or \(next). Retrying will not help until one of those has \
                happened.
                """

        case let .wouldQueue(workspace, hold):
            return Self.queued(workspace: workspace, hold: hold)

        case .appRefused(let sentence):
            return "Unified Dev did not send the merge request. \(sentence)"
        }
    }

    private static func queued(workspace: String, hold: DeliveryHold) -> String {
        switch hold {
        case .setup:
            return """
                Unified Dev will not ask for a merge in '\(workspace)' yet, because its setup script is \
                still running and nothing may be said to an agent in a worktree that is still \
                being built. A request sent now would sit in a queue rather than start a turn. \
                Wait, and ask again once workspace_list reports its setup_state as done.
                """
        case .question:
            return """
                Unified Dev will not ask for a merge in '\(workspace)' because its agent has stopped on \
                a permission question and is waiting for an answer. Writing into a turn that is \
                blocked on one is exactly what a backend refuses. Wait for the owner to answer it, \
                check with workspace_list that nothing is awaiting_permission, then ask again.
                """
        case .turn:
            return """
                Unified Dev will not ask for a merge in '\(workspace)' because its agent is in the \
                middle of a turn. Unified Dev will not queue a merge behind work in progress, because a \
                queued message is not a turn that has begun and this call would be answering with \
                something untrue. Wait for the turn to finish, check with workspace_list that \
                nothing is agent_running, then ask again.
                """
        case .none:
            return """
                Unified Dev will not ask for a merge in '\(workspace)' right now. Check with \
                workspace_list what it is doing and ask again.
                """
        }
    }
}
