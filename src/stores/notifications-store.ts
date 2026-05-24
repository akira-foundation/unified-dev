import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";

export interface NotificationItem {
  id: string;
  category: string;
  severity: "info" | "success" | "warning" | "error" | string;
  title: string;
  body: string | null;
  action_type: string | null;
  action_payload: string | null;
  read_at: string | null;
  created_at: string;
  expires_at: string | null;
}

interface NotificationsState {
  items: NotificationItem[];
  unread: number;
  loading: boolean;
  load: (opts?: { limit?: number; onlyUnread?: boolean }) => Promise<void>;
  refreshUnread: () => Promise<void>;
  markRead: (id: string) => Promise<void>;
  markAllRead: () => Promise<void>;
  remove: (id: string) => Promise<void>;
  clear: () => Promise<void>;
}

export const useNotificationsStore = create<NotificationsState>()((set, get) => ({
  items: [],
  unread: 0,
  loading: false,

  load: async (opts) => {
    set({ loading: true });
    try {
      const [items, unread] = await Promise.all([
        invoke<NotificationItem[]>("list_notifications", {
          limit: opts?.limit ?? 500,
          onlyUnread: opts?.onlyUnread ?? false,
        }),
        invoke<number>("unread_notifications_count"),
      ]);
      set({ items, unread });
    } catch {
      set({ items: [], unread: 0 });
    } finally {
      set({ loading: false });
    }
  },

  refreshUnread: async () => {
    try {
      const unread = await invoke<number>("unread_notifications_count");
      set({ unread });
    } catch {
    }
  },

  markRead: async (id: string) => {
    await invoke("mark_notification_read", { id });
    const items = get().items.map((n) =>
      n.id === id && n.read_at === null ? { ...n, read_at: new Date().toISOString() } : n,
    );
    const unread = items.filter((n) => n.read_at === null).length;
    set({ items, unread });
  },

  markAllRead: async () => {
    await invoke("mark_all_notifications_read");
    const now = new Date().toISOString();
    const items = get().items.map((n) => (n.read_at === null ? { ...n, read_at: now } : n));
    set({ items, unread: 0 });
  },

  remove: async (id: string) => {
    await invoke("delete_notification", { id });
    const items = get().items.filter((n) => n.id !== id);
    const unread = items.filter((n) => n.read_at === null).length;
    set({ items, unread });
  },

  clear: async () => {
    await invoke("clear_notifications");
    set({ items: [], unread: 0 });
  },
}));
