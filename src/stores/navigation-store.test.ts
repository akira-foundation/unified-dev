import { beforeEach, describe, expect, it } from "vitest";

import { useNavigationStore } from "./navigation-store";
import type { PullRequestDto } from "@/types/organization";

const draftPr: PullRequestDto = {
  id: "pr-1",
  number: 7,
  title: "Draft work",
  state: "open",
  url: "https://github.com/acme/repo/pull/7",
  head: "feature",
  base: "main",
  head_sha: "abc123",
  created_at: "2026-01-01T00:00:00Z",
  updated_at: "2026-01-01T00:00:00Z",
  is_draft: true,
  merged_at: null,
  body: null,
  author: "octocat",
  labels: [],
  reviewers: [],
  ci_status: null,
};

describe("navigation-store markActivePrReady", () => {
  beforeEach(() => {
    useNavigationStore.setState({ activePr: null });
  });

  it("flips the active PR from draft to ready in place", () => {
    useNavigationStore.getState().setActivePr(draftPr);
    useNavigationStore.getState().markActivePrReady();

    const { activePr } = useNavigationStore.getState();
    expect(activePr?.is_draft).toBe(false);
    expect(activePr?.number).toBe(7);
  });

  it("does nothing when no PR is active", () => {
    useNavigationStore.getState().markActivePrReady();
    expect(useNavigationStore.getState().activePr).toBeNull();
  });
});
