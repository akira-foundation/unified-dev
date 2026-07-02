import { describe, expect, it } from "vitest";

import { shouldOfferPushPr } from "./push-pr";

describe("shouldOfferPushPr", () => {
  it("offers when idle, no PR, and the branch is ahead", () => {
    expect(shouldOfferPushPr({ isStreaming: false, hasPr: false, branchAhead: true })).toBe(true);
  });

  it("hides while streaming", () => {
    expect(shouldOfferPushPr({ isStreaming: true, hasPr: false, branchAhead: true })).toBe(false);
  });

  it("hides when a PR already exists", () => {
    expect(shouldOfferPushPr({ isStreaming: false, hasPr: true, branchAhead: true })).toBe(false);
  });

  it("hides when the branch is not ahead of the remote", () => {
    expect(shouldOfferPushPr({ isStreaming: false, hasPr: false, branchAhead: false })).toBe(false);
  });
});
