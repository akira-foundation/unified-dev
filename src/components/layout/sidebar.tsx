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

interface AppSidebarProps {
  items: NavItem[];
  activeId: NavItem["id"];
  onSelect: (id: NavItem["id"]) => void;
}

export function AppSidebar({ items, activeId, onSelect }: AppSidebarProps) {
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
                      <span className="text-sm font-semibold text-zinc-900 dark:text-white">Unified Dev</span>
                      <span className="text-xs text-zinc-500 dark:text-zinc-400">Workspace</span>
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
            Principal
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
                    <span>{dashboardItem.label}</span>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              )}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>

        <SidebarGroup>
          <SidebarGroupLabel className="text-[10px] font-semibold tracking-[0.2em] text-zinc-500">
            Repositories
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
                    <span>{repositoryItem.label}</span>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              )}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>

        <SidebarGroup>
          <SidebarGroupLabel className="text-[10px] font-semibold tracking-[0.2em] text-zinc-500">
            Settings
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
                    <span>{settingsItem.label}</span>
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
                    <span>{organizationsItem.label}</span>
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
