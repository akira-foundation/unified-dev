import { useEffect, useState } from "react";
import { Bell, CheckCheck, Info, AlertTriangle, AlertCircle, CheckCircle2, X } from "lucide-react";
import { listen } from "@tauri-apps/api/event";
import { useNotificationsStore, type NotificationItem } from "@/stores/notifications-store";
import { useNavigationStore } from "@/stores/navigation-store";
import { runAction, actionLabel, hasAction } from "@/lib/notification-actions";
import { cn } from "@/lib/utils";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

const SEVERITY_ICON: Record<string, typeof Info> = {
  info: Info,
  success: CheckCircle2,
  warning: AlertTriangle,
  error: AlertCircle,
};

const SEVERITY_COLOR: Record<string, string> = {
  info: "text-blue-400",
  success: "text-green-400",
  warning: "text-amber-400",
  error: "text-red-400",
};

function relativeTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const secs = Math.floor(diff / 1000);
  if (secs < 60) return "now";
  const mins = Math.floor(secs / 60);
  if (mins < 60) return `${mins}m`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h`;
  const days = Math.floor(hrs / 24);
  if (days < 7) return `${days}d`;
  return new Date(iso).toLocaleDateString();
}

function NotificationRow({ item, onAction }: { item: NotificationItem; onAction?: () => void }) {
  const { markRead, remove } = useNotificationsStore();
  const Icon = SEVERITY_ICON[item.severity] ?? Info;
  const isUnread = item.read_at === null;
  const action = hasAction(item);
  const label = actionLabel(item.action_type);

  function handleClick() {
    if (isUnread) void markRead(item.id);
    if (action) {
      runAction(item);
      onAction?.();
    }
  }

  return (
    <div
      className={cn(
        "group flex items-start gap-2.5 px-3 py-2.5 border-b border-zinc-200/60 last:border-0 dark:border-zinc-800/50",
        action ? "cursor-pointer hover:bg-zinc-100 dark:hover:bg-zinc-800/50" : "cursor-default",
        isUnread && "bg-zinc-100/60 dark:bg-zinc-800/20",
      )}
      onClick={handleClick}
    >
      <Icon className={cn("h-3.5 w-3.5 mt-0.5 shrink-0", SEVERITY_COLOR[item.severity] ?? "text-zinc-400")} />
      <div className="flex-1 min-w-0">
        <div className="flex items-baseline gap-2">
          <p className="text-[12px] font-medium text-zinc-900 dark:text-zinc-100 truncate">{item.title}</p>
          <span className="text-[10px] text-zinc-500 shrink-0">{relativeTime(item.created_at)}</span>
        </div>
        {item.body && (
          <p className="text-[11px] text-zinc-500 dark:text-zinc-400 mt-0.5 line-clamp-2">{item.body}</p>
        )}
        {label && (
          <p className="text-[10px] text-purple-400 mt-1 font-medium">{label} →</p>
        )}
      </div>
      <button
        onClick={(e) => {
          e.stopPropagation();
          void remove(item.id);
        }}
        className="opacity-0 group-hover:opacity-100 transition-opacity text-zinc-500 hover:text-zinc-300"
      >
        <X className="h-3 w-3" />
      </button>
    </div>
  );
}

export function NotificationsDropdown() {
  const { items, unread, load, markAllRead, clear } = useNotificationsStore();
  const navigateTo = useNavigationStore((s) => s.navigateTo);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    void load({ limit: 10 });
  }, []);

  useEffect(() => {
    const unlisten = listen("notification:new", () => {
      void load({ limit: 10 });
    });
    return () => {
      void unlisten.then((fn) => fn());
    };
  }, []);

  useEffect(() => {
    if (open) void load({ limit: 10 });
  }, [open]);

  return (
    <DropdownMenu open={open} onOpenChange={setOpen}>
      <DropdownMenuTrigger asChild>
        <button className="relative inline-flex size-8 items-center justify-center rounded-md border bg-background text-muted-foreground shadow-xs transition-colors hover:bg-accent hover:text-accent-foreground dark:border-input dark:bg-input/30 dark:hover:bg-input/50">
          <Bell className="h-4 w-4" />
          {unread > 0 && (
            <span className="absolute -top-0.5 -right-0.5 min-w-[14px] h-[14px] px-1 rounded-full bg-red-500 text-white text-[9px] font-bold flex items-center justify-center">
              {unread > 99 ? "99+" : unread}
            </span>
          )}
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-80 p-0 bg-white border-zinc-200 dark:bg-zinc-950 dark:border-zinc-800">
        <div className="flex items-center justify-between px-3 py-2 border-b border-zinc-200 dark:border-zinc-800">
          <span className="text-[12px] font-semibold text-zinc-800 dark:text-zinc-200">Notifications</span>
          {items.length > 0 && (
            <div className="flex items-center gap-2">
              {unread > 0 && (
                <button
                  onClick={() => void markAllRead()}
                  className="text-[10px] text-zinc-500 hover:text-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-200 flex items-center gap-1"
                >
                  <CheckCheck className="h-3 w-3" /> Mark all read
                </button>
              )}
              <button
                onClick={() => void clear()}
                className="text-[10px] text-zinc-500 hover:text-red-400"
              >
                Clear
              </button>
            </div>
          )}
        </div>
        <div className="max-h-96 overflow-y-auto">
          {items.length === 0 ? (
            <div className="px-3 py-8 text-center">
              <Bell className="h-5 w-5 text-zinc-700 mx-auto mb-2" />
              <p className="text-[11px] text-zinc-500">No notifications</p>
            </div>
          ) : (
            items.map((item) => (
              <NotificationRow key={item.id} item={item} onAction={() => setOpen(false)} />
            ))
          )}
        </div>
        {items.length > 0 && (
          <button
            onClick={() => {
              setOpen(false);
              navigateTo("notifications");
            }}
            className="w-full text-center text-[11px] text-zinc-500 hover:text-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-200 py-2 border-t border-zinc-200 dark:border-zinc-800 hover:bg-zinc-100 dark:hover:bg-zinc-900/50 transition-colors"
          >
            View all
          </button>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
