import {
  Layers,
  PanelLeft,
} from "lucide-react";
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
import type { NavItem } from "@/types/navigation";
import { useI18n } from "@/i18n/i18n";
import { cn } from "@/lib/utils";

interface AppSidebarProps {
  items: NavItem[];
  activeId: NavItem["id"];
  onSelect: (id: NavItem["id"]) => void;
}

export function AppSidebar({ items, activeId, onSelect }: AppSidebarProps) {
  const { t } = useI18n();
  const { state, toggleSidebar } = useSidebar();

  return (
    <Sidebar collapsible="icon" className="border-r border-border/40 bg-background/50 dark:bg-zinc-950/50 backdrop-blur-xl">
      <SidebarHeader className="h-16 border-b border-border/10 flex items-center px-4 group-data-[collapsible=icon]:px-0">
        <div className="flex items-center gap-3 w-full group-data-[collapsible=icon]:justify-center">
          {state === "collapsed" ? (
            <button
              type="button"
              onClick={toggleSidebar}
              className="relative flex h-10 w-10 items-center justify-center rounded-md bg-zinc-100 dark:bg-zinc-900 transition-all hover:bg-zinc-200 dark:hover:bg-zinc-800 active:scale-95 group/toggle overflow-hidden"
              title={t("sidebar.expandSidebar")}
            >
              <div className="absolute inset-0 bg-primary/10 opacity-0 group-hover/toggle:opacity-100 transition-opacity" />
              <PanelLeft className="h-5 w-5 text-muted-foreground group-hover/toggle:text-primary transition-colors" />
            </button>
          ) : (
            <>
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-gradient-to-br from-blue-500 to-purple-600 shadow-lg shadow-primary/20">
                <Layers className="h-5 w-5 text-white" />
              </div>
              <div className="flex flex-col flex-1 overflow-hidden">
                <span className="text-sm font-bold tracking-tight text-foreground dark:text-white truncate">{t("app.name")}</span>
                <span className="text-[9px] uppercase tracking-widest text-muted-foreground font-bold truncate">
                  {t("app.workspace")}
                </span>
              </div>
              <button
                type="button"
                onClick={toggleSidebar}
                className="flex h-8 w-8 items-center justify-center rounded-md text-muted-foreground hover:bg-zinc-100 dark:hover:bg-zinc-900 hover:text-foreground dark:hover:text-white transition-all"
                title={t("sidebar.collapseSidebar")}
              >
                <PanelLeft className="h-4 w-4" />
              </button>
            </>
          )}
        </div>
      </SidebarHeader>

      <SidebarContent className="py-2">
        <SidebarGroup>
          <SidebarGroupLabel className="px-6 text-[11px] font-black uppercase tracking-[0.2em] text-zinc-500 mb-4 group-data-[collapsible=icon]:hidden">
            {t("nav.section.primary")}
          </SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu className="gap-1 px-3 group-data-[collapsible=icon]:px-0">
              {items.filter(item => item.id !== "settings").map((item) => (
                <SidebarMenuItem key={item.id} className="group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:justify-center">
                  <SidebarMenuButton
                    isActive={activeId === item.id}
                    onClick={() => onSelect(item.id)}
                    tooltip={t(`nav.${item.id}`)}
                    className={cn(
                      "transition-all duration-200 rounded-md h-10 px-3",
                      activeId === item.id
                        ? "bg-zinc-100/10 dark:bg-zinc-900 text-foreground dark:text-white font-bold"
                        : "text-zinc-500 hover:bg-zinc-100/50 dark:hover:bg-zinc-900/50 hover:text-foreground dark:hover:text-zinc-300",
                      "group-data-[collapsible=icon]:size-10 group-data-[collapsible=icon]:p-0"
                    )}
                  >
                    <div className={cn(
                      "flex items-center justify-center shrink-0",
                      activeId === item.id ? "text-primary" : "text-zinc-500"
                    )}>
                      {item.icon}
                    </div>
                    <span className="ml-3 text-[13px] font-medium group-data-[collapsible=icon]:hidden">
                      {t(`nav.${item.id}`)}
                    </span>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter className="p-3 border-t border-border/10">
        <SidebarMenu>
          {items.filter(item => item.id === "settings").map((item) => (
            <SidebarMenuItem key={item.id}>
              <SidebarMenuButton
                isActive={activeId === item.id}
                onClick={() => onSelect(item.id)}
                tooltip={t(`nav.${item.id}`)}
                className={cn(
                  "transition-all duration-200 rounded-md h-10 px-3",
                  activeId === item.id
                    ? "bg-zinc-100/10 dark:bg-zinc-900 text-foreground dark:text-white font-bold"
                    : "text-zinc-500 hover:bg-zinc-100/50 dark:hover:bg-zinc-900/50 hover:text-foreground dark:hover:text-zinc-300"
                )}
              >
                <div className={cn(
                  "flex items-center justify-center shrink-0",
                  activeId === item.id ? "text-primary" : "text-zinc-500"
                )}>
                  {item.icon}
                </div>
                <span className="ml-3 text-[13px] font-medium group-data-[collapsible=icon]:hidden">
                  {t(`nav.${item.id}`)}
                </span>
              </SidebarMenuButton>
            </SidebarMenuItem>
          ))}
        </SidebarMenu>

      </SidebarFooter>
    </Sidebar>
  );
}
