import { Activity, FileText, Plus, Search } from "lucide-react";

import { ActionButton } from "@/components/ui/action-button";
import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "@/components/layout/page-header";
import { PageLayout } from "@/components/layout/page-layout";
import { NotificationButton } from "@/components/layout/notification-button";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { KanbanBoard } from "@/components/kanban-board";
import { AgendaView } from "@/components/agenda-view";
import { TeamView } from "@/components/team-view";
import { useI18n } from "@/i18n/i18n";
import { useDateLabel } from "@/hooks/use-date-label";

export function DashboardPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  return (
    <PageLayout scroll={false}>
      <PageHeader>
        <div>
          <PageHeaderTitle>{t("dashboard.header.title")}</PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span className="text-zinc-500">{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        <PageHeaderActions>
          <NotificationButton />
          <ActionButton>
            <Plus className="mr-2 h-4 w-4" /> {t("dashboard.header.newOrg")}
          </ActionButton>
        </PageHeaderActions>
      </PageHeader>

      <div className="flex min-h-0 flex-1 flex-col">
        <Tabs defaultValue="overview" className="flex h-full w-full flex-col">
          <div className="-mx-4 flex shrink-0 overflow-auto px-4 pb-4 md:mx-0 md:px-0">
            <TabsList className="h-auto gap-2 bg-transparent p-0">
              {[
                { key: "overview", label: t("dashboard.tabs.overview") },
                { key: "prs", label: t("dashboard.tabs.prs") },
                { key: "syncs", label: t("dashboard.tabs.syncs") },
                { key: "team", label: t("dashboard.tabs.team") },
              ].map((tab) => (
                <TabsTrigger
                  key={tab.key}
                  value={tab.key}
                  className="rounded-full border border-transparent px-5 py-2 text-sm font-medium text-muted-foreground transition-all hover:text-foreground data-[state=active]:border-zinc-200 data-[state=active]:bg-white data-[state=active]:text-foreground data-[state=active]:shadow-sm dark:data-[state=active]:border-zinc-700 dark:data-[state=active]:bg-zinc-800 dark:data-[state=active]:text-white"
                >
                  {tab.label}
                </TabsTrigger>
              ))}
            </TabsList>
          </div>

          <div className="min-h-0 flex-1 overflow-auto">
            <TabsContent value="overview" className="mt-0 h-full space-y-8 overflow-auto pr-2 pb-10">
              <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
                {[
                  { label: t("dashboard.stats.organizations"), value: "3", trend: "+1", icon: Search, color: "text-blue-500" },
                  { label: t("dashboard.stats.repos"), value: "18", trend: "+2", icon: FileText, color: "text-indigo-500" },
                  { label: t("dashboard.stats.syncs"), value: "12", trend: "2 online", icon: Activity, color: "text-emerald-500" },
                  { label: t("dashboard.stats.issues"), value: "85", trend: "+5%", icon: FileText, color: "text-purple-500" },
                ].map((stat) => (
                  <Card key={stat.label} className="flex flex-col justify-between p-6">
                    <div className="flex items-start justify-between">
                      <div>
                        <p className="text-sm font-medium text-muted-foreground">{stat.label}</p>
                        <h3 className="mt-2 text-3xl font-bold tracking-tight">{stat.value}</h3>
                      </div>
                      <div className={`rounded-full bg-zinc-50 p-2.5 dark:bg-zinc-800 ${stat.color}`}>
                        <stat.icon className="h-5 w-5" />
                      </div>
                    </div>
                    <div className="mt-4 flex items-center text-xs font-medium text-emerald-600 dark:text-emerald-400">
                      {stat.trend.includes("+") ? <Activity className="mr-1 h-3 w-3" /> : null}
                      {stat.trend}
                      <span className="ml-1 font-normal text-muted-foreground">vs semana</span>
                    </div>
                  </Card>
                ))}
              </div>

              <div className="grid grid-cols-1 gap-8 lg:grid-cols-3">
                <div className="space-y-6 lg:col-span-2">
                  <div className="flex items-center justify-between">
                    <h3 className="text-lg font-semibold text-foreground">{t("dashboard.activity.title")}</h3>
                    <Button variant="ghost" size="sm" className="text-muted-foreground hover:text-foreground">
                      Ver tudo
                    </Button>
                  </div>
                  <Card>
                    <div className="divide-y divide-zinc-100 dark:divide-zinc-800">
                      {[
                        { user: "Org akira", action: "Sync", target: "infra", time: "10:30", initial: "A" },
                        { user: "Org labs", action: "Sync", target: "web", time: "09:15", initial: "L" },
                        { user: "Security", action: "Audit", target: "tokens", time: "Ontem", initial: "S" },
                        { user: "Ops", action: "Report", target: "errors", time: "Ontem", initial: "O" },
                      ].map((item) => (
                        <div key={`${item.user}-${item.time}`} className="flex items-center gap-4 p-5 transition-colors hover:bg-zinc-50/50 dark:hover:bg-zinc-800/50">
                          <Avatar className="h-10 w-10 border border-zinc-200 bg-zinc-100 dark:border-zinc-700 dark:bg-zinc-800">
                            <AvatarFallback className="font-medium text-zinc-600 dark:text-zinc-400">{item.initial}</AvatarFallback>
                          </Avatar>
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-sm font-medium text-foreground">
                              {item.user} <span className="font-normal text-muted-foreground">realizou</span> {item.action}
                            </p>
                            <p className="mt-0.5 truncate text-xs text-muted-foreground">{item.target}</p>
                          </div>
                          <span className="text-xs whitespace-nowrap text-muted-foreground">{item.time}</span>
                        </div>
                      ))}
                    </div>
                  </Card>
                </div>

                <div className="space-y-6">
                  <h3 className="text-lg font-semibold text-foreground">{t("dashboard.quick.title")}</h3>
                  <div className="grid gap-4">
                    {[
                      { label: t("dashboard.quick.newOrg"), icon: Plus, color: "text-blue-600", bg: "bg-blue-50 dark:bg-blue-900/20" },
                      { label: t("dashboard.quick.import"), icon: Search, color: "text-emerald-600", bg: "bg-emerald-50 dark:bg-emerald-900/20" },
                      { label: t("dashboard.quick.newRepo"), icon: Plus, color: "text-purple-600", bg: "bg-purple-50 dark:bg-purple-900/20" },
                    ].map((action) => (
                      <button
                        key={action.label}
                        className="group flex w-full items-center gap-4 rounded-2xl border border-transparent bg-white p-4 text-left shadow-sm transition-all hover:scale-[1.02] hover:shadow-md dark:border-zinc-800/50 dark:bg-zinc-900"
                      >
                        <div className={`flex h-12 w-12 items-center justify-center rounded-xl ${action.bg} ${action.color} transition-transform group-hover:scale-110`}>
                          <action.icon className="h-6 w-6" />
                        </div>
                        <span className="font-medium text-foreground">{action.label}</span>
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            </TabsContent>

            <TabsContent value="prs" className="mt-0 h-full">
              <KanbanBoard />
            </TabsContent>

            <TabsContent value="syncs" className="mt-0 h-full overflow-auto pr-2 pb-10">
              <AgendaView />
            </TabsContent>

            <TabsContent value="team" className="mt-0 h-full overflow-auto pr-2 pb-10">
              <TeamView />
            </TabsContent>

          </div>
        </Tabs>
      </div>
    </PageLayout>
  );
}
