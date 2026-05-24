import { describe, expect, it } from "vitest";

import { actionLabel } from "./notification-actions";

describe("actionLabel", () => {
  it("returns null for sync.retry", () => {
    expect(actionLabel("sync.retry")).toBeNull();
  });

  it("keeps the remaining action labels", () => {
    expect(actionLabel("update.cli")).toBe("Update");
    expect(actionLabel("upgrade.pro")).toBe("Upgrade");
    expect(actionLabel("auth.reconnect")).toBe("Sign in");
  });

  it("returns null for unknown or absent actions", () => {
    expect(actionLabel(null)).toBeNull();
    expect(actionLabel("nope")).toBeNull();
  });
});
