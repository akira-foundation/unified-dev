import { useEffect, useMemo, useState } from "react";
import { Bell, CheckCheck, Info, AlertTriangle, AlertCircle, CheckCircle2, Trash2, ChevronDown } from "lucide-react";
import { useI18n } from "@/i18n/i18n";
import { useDateLabel } from "@/hooks/use-date-label";
import {
  PageHeader,
  PageHeaderMeta,
  PageHeaderTitle,
} from "@/components/layout/page-header";
import { AppbarActions } from "@/components/layout/appbar-actions";
import { PageLayout } from "@/components/layout/page-layout";
import { Button } from "@/components/ui/button";
import { useNotificationsStore, type NotificationItem } from "@/stores/notifications-store";
import { runAction, actionLabel, hasAction } from "@/lib/notification-actions";
import { cn } from "@/lib/utils";

const SEVERITY_ICON: Record<string, typeof Info> = {
  info: Info,
  success: CheckCircle2,
  warning: AlertTriangle,
  error: AlertCircle,
};

const SEVERITY_COLOR: Record<string, string> = {
  info: "text-blue-500",
  success: "text-green-500",
  warning: "text-amber-500",
  error: "text-red-500",
};

const CATEGORY_LABEL: Record<string, string> = {
  autopilot: "Autopilot",
  pull_request: "Pull request",
  issue: "Issue",
  sync: "Sync",
  workspace: "Workspace",
  update: "Update",
  license: "License",
  auth: "Auth",
  skill: "Skill",
  usage_limit: "Usage limit",
};

function relativeTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const secs = Math.floor(diff / 1000);
  if (secs < 60) return "now";
  const mins = Math.floor(secs / 60);
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  if (days < 7) return `${days}d ago`;
  return new Date(iso).toLocaleDateString();
}

function NotificationRow({ item }: { item: NotificationItem }) {
  const { markRead, remove } = useNotificationsStore();
  const [expanded, setExpanded] = useState(false);
  const Icon = SEVERITY_ICON[item.severity] ?? Info;
  const isUnread = item.read_at === null;
  const hasBody = !!item.body;
  const action = hasAction(item);
  const label = actionLabel(item.action_type);

  function handleToggle() {
    if (hasBody) setExpanded((v) => !v);
    if (isUnread) void markRead(item.id);
  }

  return (
    <div className="group rounded-md transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.03]">
      <div
        className={cn("flex h-9 items-center gap-2.5 pl-3 pr-2", hasBody && "cursor-pointer")}
        onClick={handleToggle}
      >
        {isUnread && <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-purple-500" />}
        <Icon className={cn("h-3.5 w-3.5 shrink-0", SEVERITY_COLOR[item.severity] ?? "text-zinc-400")} />
        <span
          className={cn(
            "min-w-0 flex-1 truncate text-[13px]",
            isUnread ? "font-medium text-zinc-900 dark:text-zinc-100" : "text-zinc-700 dark:text-zinc-300",
          )}
        >
          {item.title}
        </span>

        <div className="flex shrink-0 items-center gap-2">
          <span className="hidden max-w-[120px] truncate rounded border border-zinc-200 px-1.5 py-0.5 text-[10px] uppercase tracking-wider text-zinc-500 dark:border-zinc-800 dark:text-zinc-400 md:inline-block">
            {CATEGORY_LABEL[item.category] ?? item.category}
          </span>
          <span className="w-14 shrink-0 text-right text-[11px] tabular-nums text-zinc-500">
            {relativeTime(item.created_at)}
          </span>
          {hasBody && (
            <ChevronDown className={cn("h-3.5 w-3.5 text-zinc-400 transition-transform", expanded && "rotate-180")} />
          )}
          <div className="flex items-center gap-1 opacity-0 transition-opacity group-hover:opacity-100">
            {action && label && (
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  if (isUnread) void markRead(item.id);
                  runAction(item);
                }}
                className="rounded px-2 py-1 text-[11px] font-medium text-purple-600 hover:bg-purple-100 hover:text-purple-700 dark:text-purple-400 dark:hover:bg-purple-500/10 dark:hover:text-purple-300"
              >
                {label}
              </button>
            )}
            <button
              onClick={(e) => {
                e.stopPropagation();
                void remove(item.id);
              }}
              className="flex h-6 w-6 items-center justify-center rounded text-zinc-400 transition-colors hover:bg-zinc-200 hover:text-red-500 dark:hover:bg-zinc-700"
              title="Delete"
            >
              <Trash2 className="h-3.5 w-3.5" />
            </button>
          </div>
        </div>
      </div>

      {item.body && expanded && (
        <p className="break-all px-3 pb-3 pl-[2.4rem] text-xs leading-relaxed text-zinc-500 dark:text-zinc-400">
          {item.body}
        </p>
      )}
    </div>
  );
}

export function NotificationsPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { items, unread, loading, load, markAllRead, clear } = useNotificationsStore();
  const [activeTab, setActiveTab] = useState<string>("all");
  const [unreadView, setUnreadView] = useState<Set<string>>(new Set());

  useEffect(() => {
    void load();
  }, []);

  const unreadCount = useMemo(() => items.filter((n) => n.read_at === null).length, [items]);

  function selectTab(id: string) {
    if (id === "unread") {
      setUnreadView(new Set(items.filter((n) => n.read_at === null).map((n) => n.id)));
    }
    setActiveTab(id);
  }

  const filtered = useMemo(() => {
    if (activeTab === "all") return items;
    if (activeTab === "unread") return items.filter((n) => n.read_at === null || unreadView.has(n.id));
    return items.filter((n) => n.category === activeTab);
  }, [items, activeTab, unreadView]);

  const categories = useMemo(() => {
    const counts = new Map<string, number>();
    for (const n of items) counts.set(n.category, (counts.get(n.category) ?? 0) + 1);
    return Array.from(counts.entries()).sort((a, b) => a[0].localeCompare(b[0]));
  }, [items]);

  const tabs: Array<{ id: string; label: string; count: number }> = [
    { id: "all", label: "All", count: items.length },
    { id: "unread", label: "Unread", count: unreadCount },
    ...categories.map(([cat, count]) => ({ id: cat, label: CATEGORY_LABEL[cat] ?? cat, count })),
  ];

  return (
    <PageLayout>
      <AppbarActions>
        {unread > 0 && (
          <Button variant="outline" size="sm" onClick={() => void markAllRead()}>
            <CheckCheck className="h-3.5 w-3.5" />
            Mark all read
          </Button>
        )}
        {items.length > 0 && (
          <Button
            variant="outline"
            size="sm"
            onClick={() => {
              if (confirm("Clear all notifications? This cannot be undone.")) void clear();
            }}
          >
            <Trash2 className="h-3.5 w-3.5" />
            Clear all
          </Button>
        )}
      </AppbarActions>
      <PageHeader>
        <div>
          <PageHeaderTitle>{t("nav.notifications", { defaultValue: "Notifications" } as never)}</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
      </PageHeader>

      <div className="mb-1 flex items-center gap-5 border-b border-zinc-200 px-1 dark:border-white/[0.06]">
        {tabs.map(({ id, label, count }) => {
          const active = activeTab === id;
          return (
            <button
              key={id}
              onClick={() => selectTab(id)}
              className={cn(
                "relative flex h-10 items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wider transition-colors",
                active
                  ? "text-purple-600 dark:text-purple-400"
                  : "text-zinc-400 hover:text-zinc-600 dark:text-zinc-500 dark:hover:text-zinc-300",
              )}
            >
              <span>{label}</span>
              {count > 0 && <span className="text-[10px] tabular-nums text-zinc-400 dark:text-zinc-600">{count}</span>}
              {active && <span className="absolute inset-x-0 bottom-0 h-[1.5px] bg-purple-500" />}
            </button>
          );
        })}
      </div>

      <div className="flex flex-col gap-0.5 py-2">
        {loading ? (
          <div className="px-3 py-12 text-center text-[12px] text-zinc-500">Loading…</div>
        ) : filtered.length === 0 ? (
          <div className="px-3 py-16 text-center">
            <Bell className="mx-auto mb-3 h-8 w-8 text-zinc-400 dark:text-zinc-700" />
            <p className="mb-1 text-[13px] font-medium text-zinc-700 dark:text-zinc-300">
              {items.length === 0 ? "No notifications yet" : "No matches"}
            </p>
            <p className="text-[11px] text-zinc-500">
              {items.length === 0 ? "Events and updates will appear here." : "Try adjusting the filters."}
            </p>
          </div>
        ) : (
          filtered.map((item) => <NotificationRow key={item.id} item={item} />)
        )}
      </div>
    </PageLayout>
  );
}
