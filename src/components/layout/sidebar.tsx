import { Layers, PanelLeft } from "lucide-react";
import { useMemo } from "react";

import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from "@/components/ui/sidebar";
import { cache } from "@/config/cache";
import { useI18n } from "@/i18n/i18n";
import { useUsage } from "@/hooks/useUsage";
import { cn } from "@/lib/utils";
import { queryKeys } from "@/lib/query-keys";
import { repositorySelectionService } from "@/services/repositorySelectionService";
import { useNavigationStore } from "@/stores/navigation-store";
import { useOrganizations } from "@/hooks/useOrganizations";
import type { NavBadge, NavBadgeTone, NavItem } from "@/types/navigation";
import { useQuery } from "@tanstack/react-query";
import { invoke } from "@tauri-apps/api/core";
import type { IssueDto } from "@/types/issue";
import type { OrganizationRepoWithOrg } from "@/types/organization";

interface AppSidebarProps {
  items: NavItem[];
  activeId: NavItem["id"];
  onSelect: (id: NavItem["id"]) => void;
}

const TONE_CLASSES: Record<NavBadgeTone, { dot: string; pill: string }> = {
  red: { dot: "bg-rose-500", pill: "bg-rose-500/15 text-rose-500" },
  green: { dot: "bg-emerald-500", pill: "bg-emerald-500/15 text-emerald-500" },
  amber: { dot: "bg-amber-500", pill: "bg-amber-500/15 text-amber-500" },
  blue: { dot: "bg-blue-500", pill: "bg-blue-500/15 text-blue-500" },
  muted: { dot: "bg-zinc-500", pill: "bg-zinc-500/10 text-zinc-500" },
};

function BadgePill({ badge }: { badge: NavBadge }) {
  const tone = TONE_CLASSES[badge.tone ?? "muted"];
  return (
    <span
      className={cn(
        "ml-auto inline-flex h-5 min-w-5 items-center justify-center rounded-full px-1.5 text-[10px] font-semibold tabular-nums",
        tone.pill,
      )}
    >
      {badge.text}
    </span>
  );
}

function ToneDot({ tone }: { tone: NavBadgeTone }) {
  return <span className={cn("h-1.5 w-1.5 shrink-0 rounded-full", TONE_CLASSES[tone].dot)} />;
}

export function AppSidebar({ items, activeId, onSelect }: AppSidebarProps) {
  const { t } = useI18n();
  const { state, toggleSidebar } = useSidebar();
  const { count, limit, isFree } = useUsage();
  const setActiveRepo = useNavigationStore((s) => s.setActiveRepo);
  const navigateTo = useNavigationStore((s) => s.navigateTo);
  const { organizations } = useOrganizations();

  const { data: allRepos = [] } = useQuery({
    queryKey: queryKeys.allRepositories(),
    queryFn: () => repositorySelectionService.listAllSelectedRepositories(),
    staleTime: cache.staleTime.short,
  });

  const { data: openIssues = 0 } = useQuery({
    queryKey: ["sidebar-open-issues", allRepos.map((r) => `${r.organization_id}:${r.repo_name}`).join(",")],
    queryFn: async () => {
      const results = await Promise.allSettled(
        allRepos.map((r: OrganizationRepoWithOrg) =>
          invoke<IssueDto[]>("list_issues", {
            orgId: r.organization_id,
            repoName: r.repo_name,
            scope: "all_open",
          }),
        ),
      );
      return results.reduce(
        (sum, r) => sum + (r.status === "fulfilled" ? r.value.length : 0),
        0,
      );
    },
    enabled: allRepos.length > 0,
    staleTime: cache.staleTime.short,
  });

  const itemsBySection = useMemo(() => {
    const groups: Record<string, NavItem[]> = { workspace: [], browse: [], footer: [] };
    for (const item of items) {
      if (item.id === "settings") {
        groups.footer.push(item);
      } else {
        const key = item.section ?? "workspace";
        groups[key]?.push(item);
      }
    }
    return groups;
  }, [items]);

  const recentRepos = useMemo(
    () =>
      [...allRepos]
        .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
        .slice(0, 5),
    [allRepos],
  );

  function badgeFor(item: NavItem): NavBadge | undefined {
    if (item.badge) return item.badge;
    if (item.id === "issues" && openIssues > 0) {
      return { text: openIssues, tone: "amber" };
    }
    if (item.id === "repository" && allRepos.length > 0) {
      return { text: allRepos.length, tone: "muted" };
    }
    if (item.id === "organizations" && organizations.length > 0) {
      return { text: organizations.length, tone: "muted" };
    }
    return undefined;
  }

  function renderItem(item: NavItem) {
    const badge = badgeFor(item);
    const isActive = activeId === item.id;
    return (
      <SidebarMenuItem
        key={item.id}
        className="group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:justify-center"
      >
        <SidebarMenuButton
          isActive={isActive}
          onClick={() => onSelect(item.id)}
          tooltip={t(`nav.${item.id}`)}
          className={cn(
            "h-10 rounded-xl px-3 transition-colors duration-150",
            isActive
              ? "bg-white/70 text-zinc-900 shadow-sm shadow-black/5 dark:bg-zinc-800/70 dark:text-white"
              : "text-zinc-600 hover:bg-zinc-200/40 dark:text-zinc-400 dark:hover:bg-zinc-800/40",
            "group-data-[collapsible=icon]:size-10 group-data-[collapsible=icon]:p-0",
          )}
        >
          <div
            className={cn(
              "flex shrink-0 items-center justify-center",
              isActive ? "text-purple-500" : "text-zinc-500 dark:text-zinc-400",
            )}
          >
            {item.icon}
          </div>
          <span className="ml-3 text-[13px] font-medium group-data-[collapsible=icon]:hidden">
            {t(`nav.${item.id}`)}
          </span>
          {badge ? (
            <span className="group-data-[collapsible=icon]:hidden">
              <BadgePill badge={badge} />
            </span>
          ) : null}
        </SidebarMenuButton>
      </SidebarMenuItem>
    );
  }

  return (
    <Sidebar
      collapsible="icon"
      variant="floating"
      className="bg-transparent [&_[data-sidebar=sidebar]]:bg-white/70 [&_[data-sidebar=sidebar]]:backdrop-blur-2xl dark:[&_[data-sidebar=sidebar]]:bg-zinc-950/70"
    >
        <SidebarHeader
          data-tauri-drag-region
          className="flex h-20 items-end px-3 pt-12 pb-2 group-data-[collapsible=icon]:px-0 [-webkit-app-region:drag] [&_button]:[-webkit-app-region:no-drag] [&_input]:[-webkit-app-region:no-drag] [&_a]:[-webkit-app-region:no-drag]"
        >
          <div
            data-tauri-drag-region
            className="flex w-full items-center gap-3 group-data-[collapsible=icon]:justify-center"
          >
            {state === "collapsed" ? (
              <button
                type="button"
                onClick={toggleSidebar}
                className="relative flex h-10 w-10 items-center justify-center rounded-xl bg-zinc-100 transition-all hover:bg-zinc-200 active:scale-95 dark:bg-zinc-900 dark:hover:bg-zinc-800"
                title={t("sidebar.expandSidebar")}
              >
                <PanelLeft className="h-5 w-5 text-zinc-500" />
              </button>
            ) : (
              <>
                <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-purple-600 shadow-md shadow-purple-600/30">
                  <Layers className="h-5 w-5 text-white" />
                </div>
                <div className="flex flex-1 flex-col overflow-hidden">
                  <span className="truncate text-sm font-bold tracking-tight text-zinc-900 dark:text-white">
                    {t("app.name")}
                  </span>
                  <span className="truncate text-[9px] font-bold uppercase tracking-widest text-zinc-500">
                    {t("app.workspace")}
                  </span>
                </div>
                <button
                  type="button"
                  onClick={toggleSidebar}
                  className="flex h-8 w-8 items-center justify-center rounded-lg text-zinc-500 transition-all hover:bg-zinc-200/60 hover:text-zinc-900 dark:hover:bg-zinc-800/60 dark:hover:text-white"
                  title={t("sidebar.collapseSidebar")}
                >
                  <PanelLeft className="h-4 w-4" />
                </button>
              </>
            )}
          </div>
        </SidebarHeader>

        <SidebarContent className="custom-scrollbar gap-1 pt-4 pb-2">
          {itemsBySection.workspace.length > 0 ? (
            <SidebarGroup>
              <SidebarGroupLabel className="px-4 pt-2 text-[10px] font-bold uppercase tracking-widest text-zinc-500 group-data-[collapsible=icon]:hidden">
                {t("nav.section.workspace")}
              </SidebarGroupLabel>
              <SidebarGroupContent>
                <SidebarMenu className="gap-1 px-2 group-data-[collapsible=icon]:px-0">
                  {itemsBySection.workspace.map(renderItem)}
                </SidebarMenu>
              </SidebarGroupContent>
            </SidebarGroup>
          ) : null}

          {itemsBySection.browse.length > 0 ? (
            <SidebarGroup>
              <SidebarGroupLabel className="px-4 pt-2 text-[10px] font-bold uppercase tracking-widest text-zinc-500 group-data-[collapsible=icon]:hidden">
                {t("nav.section.browse")}
              </SidebarGroupLabel>
              <SidebarGroupContent>
                <SidebarMenu className="gap-1 px-2 group-data-[collapsible=icon]:px-0">
                  {itemsBySection.browse.map(renderItem)}
                </SidebarMenu>
              </SidebarGroupContent>
            </SidebarGroup>
          ) : null}

          {recentRepos.length > 0 ? (
            <SidebarGroup className="group-data-[collapsible=icon]:hidden">
              <SidebarGroupLabel className="px-4 pt-2 text-[10px] font-bold uppercase tracking-widest text-zinc-500">
                {t("nav.section.recent")}
              </SidebarGroupLabel>
              <SidebarGroupContent>
                <SidebarMenu className="gap-1 px-2">
                  {recentRepos.map((repo) => {
                    const tone: NavBadgeTone = repo.open_prs_count > 0 ? "amber" : repo.auto_sync ? "green" : "muted";
                    return (
                      <SidebarMenuItem key={`${repo.organization_id}:${repo.repo_name}`}>
                        <SidebarMenuButton
                          onClick={() => {
                            setActiveRepo({
                              name: repo.repo_name,
                              owner: repo.owner,
                              organizationId: repo.organization_id,
                            });
                            navigateTo("repository-prs");
                          }}
                          tooltip={repo.repo_name}
                          className="h-9 rounded-xl px-3 text-zinc-600 transition-colors hover:bg-zinc-200/40 dark:text-zinc-400 dark:hover:bg-zinc-800/40"
                        >
                          <ToneDot tone={tone} />
                          <span className="truncate text-[13px] font-medium">{repo.repo_name}</span>
                          {repo.open_prs_count > 0 ? (
                            <span className="ml-auto text-[10px] font-semibold tabular-nums text-zinc-500">
                              {repo.open_prs_count}
                            </span>
                          ) : null}
                        </SidebarMenuButton>
                      </SidebarMenuItem>
                    );
                  })}
                </SidebarMenu>
              </SidebarGroupContent>
            </SidebarGroup>
          ) : null}
        </SidebarContent>

        <SidebarFooter className="p-2">
          {isFree && limit !== null && state !== "collapsed" && (
            <div className="mb-2 rounded-xl bg-zinc-100/80 px-3 py-2 dark:bg-zinc-900/60">
              <p className="text-[11px] font-medium text-zinc-500 dark:text-zinc-400">
                {count}/{limit} {t("sidebar.runsToday")}
              </p>
              <div className="mt-1 h-1 overflow-hidden rounded-full bg-zinc-200 dark:bg-zinc-800">
                <div
                  className={cn(
                    "h-1 rounded-full transition-all",
                    count >= limit ? "bg-rose-500" : "bg-purple-500",
                  )}
                  style={{ width: `${Math.min((count / limit) * 100, 100)}%` }}
                />
              </div>
            </div>
          )}
          <SidebarMenu>{itemsBySection.footer.map(renderItem)}</SidebarMenu>
        </SidebarFooter>
    </Sidebar>
  );
}
