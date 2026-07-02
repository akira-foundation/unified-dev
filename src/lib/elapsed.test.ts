import { describe, expect, it } from "vitest";

import { elapsedSecondsSince } from "./elapsed";

describe("elapsedSecondsSince", () => {
  it("derives whole seconds from a fixed start timestamp", () => {
    const start = 1_000_000;
    expect(elapsedSecondsSince(start, start)).toBe(0);
    expect(elapsedSecondsSince(start, start + 999)).toBe(0);
    expect(elapsedSecondsSince(start, start + 5_400)).toBe(5);
    expect(elapsedSecondsSince(start, start + 125_000)).toBe(125);
  });

  it("stays non-negative when the clock is behind the start", () => {
    expect(elapsedSecondsSince(2_000, 1_000)).toBe(0);
  });
});
