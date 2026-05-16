import { useEffect, useMemo, useState } from "react";
import { Bell, CheckCheck, Info, AlertTriangle, AlertCircle, CheckCircle2, Trash2, ChevronDown } from "lucide-react";
import { useI18n } from "@/i18n/i18n";
import { useDateLabel } from "@/hooks/use-date-label";
import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "@/components/layout/page-header";
import { PageLayout } from "@/components/layout/page-layout";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { SettingsSection } from "@/components/settings/settings-section";
import { useNotificationsStore, type NotificationItem } from "@/stores/notifications-store";
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

  function handleToggle() {
    if (!hasBody) return;
    setExpanded((v) => !v);
    if (isUnread) void markRead(item.id);
  }

  return (
    <div
      className={cn(
        "group flex items-start gap-3 px-4 py-4 transition-colors",
        hasBody && "cursor-pointer hover:bg-zinc-50 dark:hover:bg-zinc-900/40",
        isUnread && "bg-purple-50/30 dark:bg-purple-500/[0.03]",
      )}
      onClick={handleToggle}
    >
      <div className="flex items-center gap-2 mt-0.5 shrink-0">
        {isUnread && <span className="h-1.5 w-1.5 rounded-full bg-purple-500 shrink-0" />}
        <Icon className={cn("h-4 w-4", SEVERITY_COLOR[item.severity] ?? "text-zinc-400")} />
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-baseline gap-2 mb-1">
          <p className={cn(
            "text-sm font-medium",
            isUnread ? "text-zinc-900 dark:text-white" : "text-zinc-600 dark:text-zinc-300",
          )}>
            {item.title}
          </p>
          <span className="text-[10px] uppercase tracking-wider font-semibold text-zinc-400 dark:text-zinc-600 shrink-0">
            {CATEGORY_LABEL[item.category] ?? item.category}
          </span>
          <span className="text-[11px] text-zinc-500 shrink-0 ml-auto">{relativeTime(item.created_at)}</span>
          {hasBody && (
            <ChevronDown
              className={cn(
                "h-3.5 w-3.5 text-zinc-400 transition-transform",
                expanded && "rotate-180",
              )}
            />
          )}
        </div>
        {item.body && (
          <p
            className={cn(
              "text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed break-all",
              !expanded && "line-clamp-1",
            )}
          >
            {item.body}
          </p>
        )}
      </div>
      <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity shrink-0">
        {isUnread && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              void markRead(item.id);
            }}
            className="p-1.5 rounded text-zinc-500 hover:text-zinc-900 hover:bg-zinc-200 dark:hover:text-zinc-200 dark:hover:bg-zinc-800"
            title="Mark read"
          >
            <CheckCheck className="h-3.5 w-3.5" />
          </button>
        )}
        <button
          onClick={(e) => {
            e.stopPropagation();
            void remove(item.id);
          }}
          className="p-1.5 rounded text-zinc-500 hover:text-red-500 hover:bg-zinc-200 dark:hover:bg-zinc-800"
          title="Delete"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      </div>
    </div>
  );
}

export function NotificationsPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { items, unread, loading, load, markAllRead, clear } = useNotificationsStore();
  const [activeTab, setActiveTab] = useState<string>("all");

  useEffect(() => {
    void load({ limit: 200 });
  }, []);

  const filtered = useMemo(() => {
    if (activeTab === "all") return items;
    if (activeTab === "unread") return items.filter((n) => n.read_at === null);
    return items.filter((n) => n.category === activeTab);
  }, [items, activeTab]);

  const categories = useMemo(() => {
    const counts = new Map<string, number>();
    for (const n of items) counts.set(n.category, (counts.get(n.category) ?? 0) + 1);
    return Array.from(counts.entries()).sort((a, b) => a[0].localeCompare(b[0]));
  }, [items]);

  const description =
    items.length === 0
      ? "Events and updates from the app will show up here."
      : `${items.length} total · ${unread} unread`;

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>{t("nav.notifications", { defaultValue: "Notifications" } as never)}</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        <PageHeaderActions>
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
        </PageHeaderActions>
      </PageHeader>

      <Tabs value={activeTab} onValueChange={setActiveTab} className="mb-4">
        <TabsList className="h-auto gap-1 rounded-full border border-zinc-200 bg-zinc-100/50 dark:border-zinc-800/50 dark:bg-zinc-900/50">
          <TabsTrigger
            value="all"
            className="rounded-full px-4 py-1.5 text-[10px] font-bold uppercase tracking-wider text-zinc-500 transition-all data-[state=active]:bg-white data-[state=active]:text-zinc-900 data-[state=active]:shadow-sm dark:data-[state=active]:bg-zinc-800 dark:data-[state=active]:text-white border border-transparent"
          >
            All
            {items.length > 0 && (
              <span className="ml-1.5 rounded-full bg-zinc-200 dark:bg-zinc-700 px-1.5 py-0.5 text-[10px] font-bold leading-none">
                {items.length}
              </span>
            )}
          </TabsTrigger>
          <TabsTrigger
            value="unread"
            className="rounded-full px-4 py-1.5 text-[10px] font-bold uppercase tracking-wider text-zinc-500 transition-all data-[state=active]:bg-white data-[state=active]:text-zinc-900 data-[state=active]:shadow-sm dark:data-[state=active]:bg-zinc-800 dark:data-[state=active]:text-white border border-transparent"
          >
            Unread
            {unread > 0 && (
              <span className="ml-1.5 rounded-full bg-purple-500/20 text-purple-700 dark:text-purple-300 px-1.5 py-0.5 text-[10px] font-bold leading-none">
                {unread}
              </span>
            )}
          </TabsTrigger>
          {categories.map(([cat, count]) => (
            <TabsTrigger
              key={cat}
              value={cat}
              className="rounded-full px-4 py-1.5 text-[10px] font-bold uppercase tracking-wider text-zinc-500 transition-all data-[state=active]:bg-white data-[state=active]:text-zinc-900 data-[state=active]:shadow-sm dark:data-[state=active]:bg-zinc-800 dark:data-[state=active]:text-white border border-transparent"
            >
              {CATEGORY_LABEL[cat] ?? cat}
              <span className="ml-1.5 rounded-full bg-zinc-200 dark:bg-zinc-700 px-1.5 py-0.5 text-[10px] font-bold leading-none">
                {count}
              </span>
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>

      <SettingsSection title="Inbox" description={description} icon={Bell}>

        {loading ? (
          <div className="px-4 py-12 text-center text-[12px] text-zinc-500">Loading…</div>
        ) : filtered.length === 0 ? (
          <div className="px-4 py-16 text-center">
            <Bell className="h-8 w-8 text-zinc-400 dark:text-zinc-700 mx-auto mb-3" />
            <p className="text-[13px] text-zinc-700 dark:text-zinc-300 font-medium mb-1">
              {items.length === 0 ? "No notifications yet" : "No matches"}
            </p>
            <p className="text-[11px] text-zinc-500">
              {items.length === 0
                ? "Events and updates will appear here."
                : "Try adjusting the filters."}
            </p>
          </div>
        ) : (
          filtered.map((item) => <NotificationRow key={item.id} item={item} />)
        )}
      </SettingsSection>
    </PageLayout>
  );
}
