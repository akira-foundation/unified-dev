import { Activity, FileText, GitPullRequest, Plus, RefreshCw, Search, Sparkles, Building2 } from "lucide-react";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useToggle } from "@uidotdev/usehooks";

import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "@/components/layout/page-header";
import { PageLayout } from "@/components/layout/page-layout";
import { Button } from "@/components/ui/button";
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { KanbanBoard, KanbanFilterPopover } from "@/components/kanban-board";
import { AgendaView } from "@/components/agenda-view";
import { AddOrganizationDialog } from "@/components/organizations/add-organization-dialog";
import { useI18n } from "@/i18n/i18n";
import { useDateLabel } from "@/hooks/use-date-label";
import { useOrganizations } from "@/hooks/useOrganizations";
import { useProviders } from "@/hooks/useProviders";
import { useNavigationStore } from "@/stores/navigation-store";
import { repositorySelectionService } from "@/services/repositorySelectionService";
import { queryKeys } from "@/lib/query-keys";
import { cache } from "@/config/cache";
import { cn } from "@/lib/utils";
import type { OrganizationRepoWithOrg } from "@/types/organization";

export function DashboardPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { organizations, createOrganization } = useOrganizations();
  const { providers } = useProviders();
  const { dashboardTab, setDashboardTab, setActiveRepo, navigateTo } = useNavigationStore();
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [kanbanCompact, toggleKanbanCompact] = useToggle(false);

  const { data: allRepos = [], isLoading: reposLoading } = useQuery({
    queryKey: queryKeys.allRepositories(),
    queryFn: () => repositorySelectionService.listAllSelectedRepositories(),
    staleTime: cache.staleTime.short,
  });

  const totalOpenPrs = allRepos.reduce((sum, r) => sum + (r.open_prs_count ?? 0), 0);
  const autoSyncCount = allRepos.filter((r) => r.auto_sync).length;

  const recentRepos = [...allRepos]
    .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
    .slice(0, 5);

  const handleRepoClick = (repo: OrganizationRepoWithOrg) => {
    setActiveRepo({ name: repo.repo_name, owner: repo.owner, organizationId: repo.organization_id });
    navigateTo("repository-prs");
  };

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
          <Button onClick={() => setIsDialogOpen(true)}>
            <Plus size={18} />
            {t("dashboard.header.newOrg") ?? "New Organization"}
          </Button>
        </PageHeaderActions>
      </PageHeader>

      <div className="flex min-h-0 flex-1 flex-col px-4 md:px-6 ">
        <Tabs value={dashboardTab} onValueChange={setDashboardTab} className="flex h-full w-full flex-col">
          <div className="flex shrink-0 mb-8 items-center justify-between">
            <TabsList className="h-auto gap-1 bg-zinc-100/50 dark:bg-zinc-900/50 border border-zinc-200 dark:border-zinc-800/50">
              {[
                { key: "overview", label: t("dashboard.tabs.overview") ?? "Overview" },
                { key: "prs",      label: t("dashboard.tabs.prs")      ?? "PRs" },
                { key: "syncs",    label: t("dashboard.tabs.syncs")    ?? "Syncs" },
              ].map((tab) => (
                <TabsTrigger key={tab.key} value={tab.key}>
                  {tab.label}
                </TabsTrigger>
              ))}
            </TabsList>

            {dashboardTab === "prs" && (
              <div className="flex items-center gap-2">
                <button
                  onClick={() => toggleKanbanCompact()}
                  className={cn(
                    "cursor-pointer flex items-center gap-1.5 rounded-md border px-2.5 py-1.5 text-[11px] font-semibold uppercase tracking-wider transition-colors",
                    kanbanCompact
                      ? "border-zinc-600 bg-zinc-800 text-zinc-200"
                      : "border-zinc-200 bg-zinc-100/50 text-zinc-500 dark:border-zinc-800 dark:bg-zinc-900/50 dark:text-zinc-500 hover:border-zinc-600 hover:text-zinc-300",
                  )}
                >
                  <FileText size={13} />
                  Compact
                </button>
                <KanbanFilterPopover />
              </div>
            )}
          </div>

          <div className="min-h-0 flex-1 overflow-auto custom-scrollbar">
            <TabsContent value="overview" className="mt-0 h-full space-y-10 pb-10">

              {/* Stat Cards */}
              <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
                <StatCard
                  label={t("dashboard.stats.organizations")}
                  value={organizations.length}
                  sub={organizations.length === 1 ? "organization" : "organizations"}
                  icon={Building2}
                  color="text-blue-500"
                  bg="bg-blue-500/10"
                  loading={false}
                  onClick={() => navigateTo("organizations")}
                />
                <StatCard
                  label={t("dashboard.stats.repos")}
                  value={allRepos.length}
                  sub={allRepos.length === 1 ? "repository" : "repositories"}
                  icon={FileText}
                  color="text-indigo-500"
                  bg="bg-indigo-500/10"
                  loading={reposLoading}
                  onClick={() => navigateTo("repository")}
                />
                <StatCard
                  label={t("dashboard.stats.syncs")}
                  value={autoSyncCount}
                  sub="auto-sync enabled"
                  icon={RefreshCw}
                  color="text-emerald-500"
                  bg="bg-emerald-500/10"
                  loading={reposLoading}
                  onClick={() => navigateTo("repository")}
                />
                <StatCard
                  label={t("dashboard.stats.issues")}
                  value={totalOpenPrs}
                  sub="open pull requests"
                  icon={GitPullRequest}
                  color="text-purple-500"
                  bg="bg-purple-500/10"
                  loading={reposLoading}
                  onClick={() => setDashboardTab("prs")}
                />
              </div>

              {/* Bottom grid */}
              <div className="grid grid-cols-1 gap-10 lg:grid-cols-3">

                {/* Repositories */}
                <div className="lg:col-span-2">
                  <Card>
                    <CardHeader className="flex flex-row items-center justify-between">
                      <div className="flex items-start gap-3">
                        <div className="mt-0.5 flex h-8 w-8 items-center justify-center rounded-md border border-zinc-100 dark:border-zinc-800 shadow-sm bg-indigo-500/10 text-indigo-500">
                          <Activity size={16} />
                        </div>
                        <div>
                          <CardTitle className="text-sm font-bold uppercase tracking-[0.15em]">
                            {locale === "pt-PT" ? "Repositórios" : "Repositories"}
                          </CardTitle>
                          <CardDescription>
                            {locale === "pt-PT" ? "Repositórios selecionados recentemente" : "Recently added repositories"}
                          </CardDescription>
                        </div>
                      </div>
                      <Button
                        variant="ghost"
                        size="sm"
                        className="text-[10px] font-bold uppercase tracking-widest h-8 px-3"
                        onClick={() => navigateTo("repository")}
                      >
                        {t("common.viewAll")}
                      </Button>
                    </CardHeader>
                    <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 p-0 border-t border-zinc-100 dark:border-zinc-800/50">
                      {reposLoading ? (
                        <div className="flex flex-col divide-y divide-zinc-100 dark:divide-zinc-800/50">
                          {[...Array(4)].map((_, i) => (
                            <div key={i} className="flex items-center gap-4 px-6 py-4">
                              <Skeleton className="h-10 w-10 rounded-md shrink-0" />
                              <div className="flex flex-col gap-1.5 flex-1">
                                <Skeleton className="h-3.5 w-40" />
                                <Skeleton className="h-3 w-24" />
                              </div>
                              <Skeleton className="h-3 w-10" />
                            </div>
                          ))}
                        </div>
                      ) : recentRepos.length === 0 ? (
                        <div className="flex items-center justify-center py-10">
                          <p className="text-sm text-zinc-400 dark:text-zinc-500 italic">
                            {locale === "pt-PT" ? "Nenhum repositório selecionado" : "No repositories selected"}
                          </p>
                        </div>
                      ) : (
                        recentRepos.map((repo) => (
                          <button
                            key={`${repo.organization_id}:${repo.repo_name}`}
                            onClick={() => handleRepoClick(repo)}
                            className="w-full flex items-center justify-between px-6 py-4 transition-colors hover:bg-zinc-50/50 dark:hover:bg-zinc-900/20 text-left cursor-pointer"
                          >
                            <div className="flex items-center gap-4">
                              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md border border-zinc-200 bg-zinc-100 dark:border-zinc-800 dark:bg-zinc-800/50">
                                <span className="text-sm font-bold text-zinc-600 dark:text-zinc-400">
                                  {repo.repo_name.charAt(0).toUpperCase()}
                                </span>
                              </div>
                              <div className="flex-1 min-w-0">
                                <p className="text-sm font-semibold text-zinc-900 dark:text-zinc-100 truncate">
                                  {repo.owner}/{repo.repo_name}
                                </p>
                                <p className="text-xs text-zinc-500 dark:text-zinc-500 mt-0.5">
                                  {repo.organization_name}
                                  {repo.auto_sync && (
                                    <span className="ml-2 inline-flex items-center gap-0.5 text-emerald-500">
                                      <RefreshCw size={10} />
                                      {locale === "pt-PT" ? "auto-sync" : "auto-sync"}
                                    </span>
                                  )}
                                </p>
                              </div>
                            </div>
                            <div className="flex items-center gap-2 shrink-0 ml-4">
                              {repo.open_prs_count > 0 && (
                                <span className="flex items-center gap-1 text-[11px] font-semibold text-purple-500">
                                  <GitPullRequest size={11} />
                                  {repo.open_prs_count}
                                </span>
                              )}
                              <span className={cn(
                                "text-[10px] font-medium px-1.5 py-0.5 rounded",
                                repo.visibility === "private"
                                  ? "bg-zinc-800 text-zinc-400"
                                  : "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400",
                              )}>
                                {repo.visibility}
                              </span>
                            </div>
                          </button>
                        ))
                      )}
                    </CardContent>
                  </Card>
                </div>

                {/* Quick Access */}
                <div>
                  <Card>
                    <CardHeader>
                      <div className="flex items-center gap-3">
                        <div className="flex h-8 w-8 items-center justify-center rounded-md border border-zinc-100 dark:border-zinc-800 shadow-sm bg-purple-500/10 text-purple-500">
                          <Sparkles size={16} />
                        </div>
                        <CardTitle className="text-sm font-bold uppercase tracking-[0.15em]">
                          {t("dashboard.quick.title")}
                        </CardTitle>
                      </div>
                    </CardHeader>
                    <CardContent className="grid p-2">
                      {[
                        { label: t("dashboard.quick.newOrg"), icon: Plus, color: "text-purple-500", bg: "bg-purple-500/10", onClick: () => setIsDialogOpen(true) },
                        { label: t("dashboard.quick.import"), icon: Search, color: "text-blue-500", bg: "bg-blue-500/10", onClick: () => navigateTo("import-repositories") },
                        { label: t("dashboard.quick.newRepo"), icon: FileText, color: "text-emerald-500", bg: "bg-emerald-500/10", onClick: () => navigateTo("repository") },
                      ].map((action) => (
                        <button
                          key={action.label}
                          onClick={action.onClick}
                          className="cursor-pointer group flex w-full items-center gap-2 rounded-md bg-zinc-50/50 dark:bg-zinc-900/40 p-3 transition-all hover:bg-zinc-100 dark:hover:bg-zinc-800/50 active:scale-[0.98]"
                        >
                          <div className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-md transition-transform group-hover:scale-110", action.bg, action.color)}>
                            <action.icon size={20} />
                          </div>
                          <span className="text-sm font-bold text-zinc-900 dark:text-zinc-200">{action.label}</span>
                        </button>
                      ))}
                    </CardContent>
                  </Card>
                </div>
              </div>
            </TabsContent>

            <TabsContent value="prs" className="mt-0 h-full">
              <KanbanBoard compact={kanbanCompact} />
            </TabsContent>

            <TabsContent value="syncs" className="mt-0 h-full">
              <AgendaView />
            </TabsContent>
          </div>
        </Tabs>
      </div>

      <AddOrganizationDialog
        open={isDialogOpen}
        onOpenChange={setIsDialogOpen}
        providers={providers}
        onSubmit={createOrganization}
      />
    </PageLayout>
  );
}

function StatCard({
  label,
  value,
  sub,
  icon: Icon,
  color,
  bg,
  loading,
  onClick,
}: {
  label: string;
  value: number;
  sub: string;
  icon: React.ElementType;
  color: string;
  bg: string;
  loading: boolean;
  onClick?: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={cn("text-left w-full rounded-xl", onClick && "cursor-pointer group")}
    >
      <Card className={cn("h-full transition-colors", onClick && "group-hover:border-zinc-600 group-hover:bg-zinc-900/60")}>
        <CardHeader className="flex flex-row items-center justify-between p-5 pb-3 pointer-events-none">
          <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
            {label}
          </CardDescription>
          <div className={cn("h-8 w-8 rounded-md flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm", bg, color)}>
            <Icon size={16} />
          </div>
        </CardHeader>
        <CardContent className="flex justify-between items-end p-4 pt-4 gap-1.5 border-zinc-100 dark:border-zinc-800/80 bg-zinc-50/30 dark:bg-white/[0.02]">
          {loading ? (
            <Skeleton className="h-8 w-12" />
          ) : (
            <div className="text-3xl font-black tracking-tight text-zinc-900 dark:text-white leading-none">
              {value}
            </div>
          )}
          <div className="text-[10px] font-semibold text-zinc-400 dark:text-zinc-500 uppercase tracking-widest pb-0.5">
            {sub}
          </div>
        </CardContent>
      </Card>
    </button>
  );
}
