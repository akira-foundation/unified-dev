import { beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";

import { useNotificationsStore } from "./notifications-store";

const invokeMock = vi.mocked(invoke);

describe("notifications-store load", () => {
  beforeEach(() => {
    invokeMock.mockReset();
    invokeMock.mockImplementation(((cmd: string) =>
      cmd === "unread_notifications_count" ? Promise.resolve(0) : Promise.resolve([])) as typeof invoke);
    useNotificationsStore.setState({ items: [], unread: 0, loading: false });
  });

  it("requests the full notification set by default", async () => {
    await useNotificationsStore.getState().load();
    expect(invokeMock).toHaveBeenCalledWith("list_notifications", { limit: 500, onlyUnread: false });
  });

  it("honors an explicit limit", async () => {
    await useNotificationsStore.getState().load({ limit: 10 });
    expect(invokeMock).toHaveBeenCalledWith("list_notifications", { limit: 10, onlyUnread: false });
  });
});
