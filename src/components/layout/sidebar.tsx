import { useMemo } from "react";

import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar";
import { BaseSidebar } from "@/components/layout/base-sidebar";
import { cache } from "@/config/cache";
import { useI18n } from "@/i18n/i18n";
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
    const groups: Record<string, NavItem[]> = { workspace: [], browse: [] };
    for (const item of items) {
      if (item.id === "settings") continue;
      const key = item.section ?? "workspace";
      groups[key]?.push(item);
    }
    return groups;
  }, [items]);

  const recentNavRepos = useNavigationStore((s) => s.recentRepos);

  const recentRepos = useMemo(() => {
    const byKey = new Map(
      allRepos.map((r) => [`${r.organization_id}:${r.repo_name}`, r]),
    );
    return recentNavRepos
      .map((r) => byKey.get(`${r.organizationId}:${r.name}`))
      .filter((r): r is OrganizationRepoWithOrg => Boolean(r))
      .slice(0, 5);
  }, [allRepos, recentNavRepos]);

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
    <BaseSidebar>
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
                            navigateTo("repository-detail");
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
    </BaseSidebar>
  );
}
