import { beforeEach, describe, expect, it } from "vitest";

import { useAgentsStore } from "./useAgentsStore";
import type { AgentIssue, AgentRepository } from "@/types/agents";

function issue(id: string): AgentIssue {
  return {
    id,
    title: id,
    repoId: "",
    workspacePath: "",
    repoName: "",
    branchName: "",
    agentName: "",
    status: "Running",
    updatedAt: "",
  } as AgentIssue;
}

function repo(id: string, issueIds: string[]): AgentRepository {
  return {
    id,
    name: id,
    defaultBranch: "main",
    displayName: null,
    defaultModelId: null,
    reviewModelId: null,
    defaultMergeAction: null,
    remoteUrl: null,
    issues: issueIds.map(issue),
  } as AgentRepository;
}

describe("setSelectedIssueId", () => {
  beforeEach(() => {
    useAgentsStore.setState({
      repositoryGroups: [
        { name: "THREADS", repositories: [repo("repo-a", ["t1", "t2"]), repo("repo-b", ["t3"])] },
      ],
      expandedRepos: {},
      selectedIssueId: null,
    });
  });

  it("expands the repo that owns the selected thread", () => {
    useAgentsStore.getState().setSelectedIssueId("t3");
    const state = useAgentsStore.getState();
    expect(state.selectedIssueId).toBe("t3");
    expect(state.expandedRepos["repo-b"]).toBe(true);
    expect(state.expandedRepos["repo-a"]).toBeUndefined();
  });

  it("keeps already expanded repos when selecting a thread in another repo", () => {
    useAgentsStore.setState({ expandedRepos: { "repo-a": true } });
    useAgentsStore.getState().setSelectedIssueId("t3");
    const { expandedRepos } = useAgentsStore.getState();
    expect(expandedRepos["repo-a"]).toBe(true);
    expect(expandedRepos["repo-b"]).toBe(true);
  });

  it("does not touch expandedRepos when clearing the selection", () => {
    useAgentsStore.setState({ expandedRepos: { "repo-a": true } });
    useAgentsStore.getState().setSelectedIssueId(null);
    const { expandedRepos, selectedIssueId } = useAgentsStore.getState();
    expect(selectedIssueId).toBeNull();
    expect(expandedRepos).toEqual({ "repo-a": true });
  });
});
