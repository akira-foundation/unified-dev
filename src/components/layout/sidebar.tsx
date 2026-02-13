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
  SidebarTrigger,
  useSidebar,
} from "@/components/ui/sidebar";
import type { NavItem } from "@/types/navigation";
import { useI18n } from "@/i18n/i18n";

interface AppSidebarProps {
  items: NavItem[];
  activeId: NavItem["id"];
  onSelect: (id: NavItem["id"]) => void;
}

export function AppSidebar({ items, activeId, onSelect }: AppSidebarProps) {
  const { t } = useI18n();
  const { state } = useSidebar();
  const dashboardItem = items.find((item) => item.id === "dashboard");
  const repositoryItem = items.find((item) => item.id === "repository");
  const organizationsItem = items.find((item) => item.id === "organizations");
  const settingsItem = items.find((item) => item.id === "settings");

  return (
    <Sidebar collapsible="icon" variant="inset">
      <SidebarHeader>
        <SidebarMenu>
          <SidebarMenuItem>
            {state === "collapsed" ? (
              <SidebarMenuButton size="lg" asChild>
                <div className="flex w-full items-center justify-center px-2 py-2">
                  <SidebarTrigger className="h-7 w-7 text-zinc-500 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100" />
                </div>
              </SidebarMenuButton>
            ) : (
              <SidebarMenuButton size="lg" asChild>
                <button
                  type="button"
                  onClick={() => onSelect("dashboard")}
                  className="flex w-full items-center justify-between gap-3 rounded-md px-2 py-2 transition-colors hover:bg-zinc-100/80 dark:hover:bg-zinc-800/70"
                >
                  <div className="flex items-center gap-3">
                    <div className="flex h-9 w-9 items-center justify-center rounded-md bg-zinc-900 text-white shadow-sm dark:bg-zinc-100 dark:text-zinc-900">
                      AM
                    </div>
                    <div className="flex flex-col text-left">
                    <span className="text-sm font-semibold text-zinc-900 dark:text-white">{t("app.name")}</span>
                    <span className="text-xs text-zinc-500 dark:text-zinc-400">{t("app.workspace")}</span>
                    </div>
                  </div>
                  <SidebarTrigger className="h-7 w-7 text-zinc-500 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100" />
                </button>
              </SidebarMenuButton>
            )}
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>

      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupLabel className="text-[10px] font-semibold tracking-[0.2em] text-zinc-500">
            {t("nav.section.primary")}
          </SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {dashboardItem && (
                <SidebarMenuItem>
                  <SidebarMenuButton
                    isActive={activeId === dashboardItem.id}
                    onClick={() => onSelect(dashboardItem.id)}
                    className={
                      activeId === dashboardItem.id
                        ? "bg-zinc-800/80 text-white shadow-sm dark:bg-zinc-800 dark:text-white"
                        : "text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
                    }
                    size="default"
                  >
                    {dashboardItem.icon}
                    <span>{t("nav.dashboard")}</span>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              )}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>

        <SidebarGroup>
          <SidebarGroupLabel className="text-[10px] font-semibold tracking-[0.2em] text-zinc-500">
            {t("nav.section.repositories")}
          </SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {repositoryItem && (
                <SidebarMenuItem>
                  <SidebarMenuButton
                    isActive={activeId === repositoryItem.id}
                    onClick={() => onSelect(repositoryItem.id)}
                    className={
                      activeId === repositoryItem.id
                        ? "bg-zinc-800/80 text-white shadow-sm dark:bg-zinc-800 dark:text-white"
                        : "text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
                    }
                    size="default"
                  >
                    {repositoryItem.icon}
                    <span>{t("nav.repositories")}</span>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              )}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>

        <SidebarGroup>
          <SidebarGroupLabel className="text-[10px] font-semibold tracking-[0.2em] text-zinc-500">
            {t("nav.section.settings")}
          </SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {settingsItem && (
                <SidebarMenuItem>
                  <SidebarMenuButton
                    isActive={activeId === settingsItem.id}
                    onClick={() => onSelect(settingsItem.id)}
                    className={
                      activeId === settingsItem.id
                        ? "bg-zinc-800/80 text-white shadow-sm dark:bg-zinc-800 dark:text-white"
                        : "text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
                    }
                    size="default"
                  >
                    {settingsItem.icon}
                    <span>{t("nav.settings")}</span>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              )}
              {organizationsItem && (
                <SidebarMenuItem>
                  <SidebarMenuButton
                    isActive={activeId === organizationsItem.id}
                    onClick={() => onSelect(organizationsItem.id)}
                    className={
                      activeId === organizationsItem.id
                        ? "bg-zinc-800/80 text-white shadow-sm dark:bg-zinc-800 dark:text-white"
                        : "text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
                    }
                    size="default"
                  >
                    {organizationsItem.icon}
                    <span>{t("nav.organizations")}</span>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              )}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter>
        <div className="px-3 py-2 text-[10px] uppercase tracking-[0.2em] text-zinc-500">v0.1.0</div>
      </SidebarFooter>
    </Sidebar>
  );
}
