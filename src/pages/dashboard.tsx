import { Activity, FileText, Plus, Search, TrendingUp, MessageSquare } from "lucide-react";

import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "@/components/layout/page-header";
import { PageLayout } from "@/components/layout/page-layout";
import { Button } from "@/components/ui/button";
import { Card, CardHeader, CardDescription, CardContent } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { KanbanBoard } from "@/components/kanban-board";
import { AgendaView } from "@/components/agenda-view";
import { TeamView } from "@/components/team-view";
import { useI18n } from "@/i18n/i18n";
import { useDateLabel } from "@/hooks/use-date-label";
import { cn } from "@/lib/utils";

export function DashboardPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);

  return (
    <PageLayout scroll={false}>
      <PageHeader>
        <div>
          <PageHeaderTitle>
            {t("dashboard.header.title") ?? "Overview"}
          </PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        <PageHeaderActions>
          <Button>
            <Plus size={18} />
            {t("dashboard.header.newOrg") ?? "New Organization"}
          </Button>
        </PageHeaderActions>
      </PageHeader>

      <div className="flex min-h-0 flex-1 flex-col px-4 md:px-6 ">
        <Tabs defaultValue="overview" className="flex h-full w-full flex-col">
          <div className="flex shrink-0 mb-8">
            <TabsList className="h-auto gap-1 bg-zinc-100/50 dark:bg-zinc-900/50  rounded-full border border-zinc-200 dark:border-zinc-800/50">
              {[
                { key: "overview", label: t("dashboard.tabs.overview") ?? "Overview" },
                { key: "prs", label: t("dashboard.tabs.prs") ?? "PRs" },
                { key: "syncs", label: t("dashboard.tabs.syncs") ?? "Syncs" },
                { key: "team", label: t("dashboard.tabs.team") ?? "Team" },
              ].map((tab) => (
                <TabsTrigger
                  key={tab.key}
                  value={tab.key}
                  className="rounded-full px-6 py-2 text-xs font-bold uppercase tracking-wider text-zinc-500 transition-all data-[state=active]:bg-white dark:data-[state=active]:bg-zinc-800 data-[state=active]:text-zinc-900 dark:data-[state=active]:text-white data-[state=active]:shadow-sm data-[state=active]:border-zinc-200 dark:data-[state=active]:border-transparent border border-transparent"
                >
                  {tab.label}
                </TabsTrigger>
              ))}
            </TabsList>
          </div>

          <div className="min-h-0 flex-1 overflow-auto custom-scrollbar">
            <TabsContent value="overview" className="mt-0 h-full space-y-10 pb-10">
              {/* Stat Cards Row */}
              <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
                {[
                  { label: t("dashboard.stats.organizations"), value: "3", trend: "+1", icon: Search, color: "text-blue-500", bg: "bg-blue-500/10" },
                  { label: t("dashboard.stats.repos"), value: "18", trend: "+2", icon: FileText, color: "text-indigo-500", bg: "bg-indigo-500/10" },
                  { label: t("dashboard.stats.syncs"), value: "12", trend: "2 online", icon: Activity, color: "text-emerald-500", bg: "bg-emerald-500/10" },
                  { label: t("dashboard.stats.issues"), value: "85", trend: "+5%", icon: MessageSquare, color: "text-purple-500", bg: "bg-purple-500/10" },
                ].map((stat) => (
                  <Card key={stat.label}>
                    <CardHeader className="flex flex-row items-center justify-between p-5 pb-3 pointer-events-none">
                      <CardDescription className="text-[10px] font-bold uppercase tracking-widest ">
                        {stat.label}
                      </CardDescription>
                      <div className={cn("h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm", stat.bg, stat.color)}>
                        <stat.icon size={16} />
                      </div>
                    </CardHeader>
                    <CardContent className=" flex justify-between intems-center p-4 pt-4 gap-1.5 border-zinc-100 dark:border-zinc-800/80 bg-zinc-50/30 dark:bg-white/[0.02]">
                      <div className="text-3xl font-black tracking-tight text-zinc-900 dark:text-white leading-none">
                        {stat.value}
                      </div>
                      <div className="flex items-center gap-1 text-[10px] font-bold text-emerald-500 uppercase tracking-widest">
                        <TrendingUp size={12} />
                        <span>{stat.trend} vs week</span>
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>

              {/* Main Content Sections */}
              <div className="grid grid-cols-1 gap-10 lg:grid-cols-3">
                {/* Recent Activity */}
                <div className="lg:col-span-2 space-y-5">
                  <div className="flex items-center justify-between">
                    <h3 className="text-sm font-bold uppercase tracking-[0.2em] text-zinc-900 dark:text-zinc-100">
                      {t("dashboard.activity.title")}
                    </h3>
                    <Button variant="link" size="sm" className="text-[10px] font-bold uppercase tracking-widest text-zinc-500 hover:text-zinc-900 dark:hover:text-white">
                      {t("common.viewAll") ?? "View All"}
                    </Button>
                  </div>
                  <Card className="p-0 overflow-hidden">
                    <div className="divide-y divide-zinc-100 dark:divide-zinc-800/50">
                      {[
                        { user: "Org akira", action: locale === "pt-PT" ? "realizou Sync" : "performed Sync", target: "infra", time: "10:30", initial: "A" },
                        { user: "Org labs", action: locale === "pt-PT" ? "realizou Sync" : "performed Sync", target: "web", time: "09:15", initial: "L" },
                        { user: "Security", action: locale === "pt-PT" ? "realizou Audit" : "performed Audit", target: "tokens", time: "Ontem", initial: "S" },
                        { user: "Ops", action: locale === "pt-PT" ? "realizou Report" : "performed Report", target: "errors", time: "Ontem", initial: "O" },
                      ].map((item, idx) => (
                        <div key={idx} className="flex items-center gap-4 p-5 transition-colors hover:bg-zinc-50/50 dark:hover:bg-zinc-900/30">
                          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-zinc-200 bg-zinc-100 dark:border-zinc-800 dark:bg-zinc-800/50">
                            <span className="text-sm font-bold text-zinc-600 dark:text-zinc-400">{item.initial}</span>
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">
                              {item.user} <span className="text-zinc-500 dark:text-zinc-400 font-normal">{item.action}</span>
                            </p>
                            <p className="text-xs text-zinc-500 dark:text-zinc-500 mt-1">{item.target}</p>
                          </div>
                          <span className="text-[11px] font-medium text-zinc-400 dark:text-zinc-600 whitespace-nowrap">
                            {item.time}
                          </span>
                        </div>
                      ))}
                    </div>
                  </Card>
                </div>

                {/* Quick Access */}
                <div className="space-y-5">
                  <h3 className="text-sm font-bold uppercase tracking-[0.2em] text-zinc-900 dark:text-zinc-100">
                    {t("dashboard.quick.title")}
                  </h3>
                  <div className="grid gap-4">
                    {[
                      { label: t("dashboard.quick.newOrg"), icon: Plus, color: "text-purple-500", bg: "bg-purple-500/10" },
                      { label: t("dashboard.quick.import"), icon: Search, color: "text-blue-500", bg: "bg-blue-500/10" },
                      { label: t("dashboard.quick.newRepo"), icon: FileText, color: "text-emerald-500", bg: "bg-emerald-500/10" },
                    ].map((action) => (
                      <button
                        key={action.label}
                        className="group flex w-full items-center gap-4 rounded-xl border border-zinc-100 dark:border-zinc-800/40 bg-white dark:bg-zinc-900/40 p-4 transition-all hover:bg-zinc-50 dark:hover:bg-zinc-800/50 active:scale-[0.98]"
                      >
                        <div className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-xl transition-transform group-hover:scale-110", action.bg, action.color)}>
                          <action.icon size={20} />
                        </div>
                        <span className="text-sm font-bold text-zinc-900 dark:text-zinc-200">{action.label}</span>
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            </TabsContent>

            <TabsContent value="prs" className="mt-0 h-full">
              <KanbanBoard />
            </TabsContent>

            <TabsContent value="syncs" className="mt-0 h-full">
              <AgendaView />
            </TabsContent>

            <TabsContent value="team" className="mt-0 h-full">
              <TeamView />
            </TabsContent>
          </div>
        </Tabs>
      </div>
    </PageLayout>
  );
}
