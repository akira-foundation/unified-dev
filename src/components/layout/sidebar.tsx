import {
  PanelLeft,
  ChevronLeft,
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

  const dashboardItem = items.find((item) => item.id === "dashboard");
  const repositoryItem = items.find((item) => item.id === "repository");
  const organizationsItem = items.find((item) => item.id === "organizations");
  const settingsItem = items.find((item) => item.id === "settings");

  return (
    <Sidebar collapsible="icon" className="border-r border-border/40 bg-sidebar/50 backdrop-blur-xl">
      <SidebarHeader className="h-14 border-b border-border/40 flex items-center px-4 group-data-[collapsible=icon]:px-0">
        <div className="flex items-center gap-3 w-full group-data-[collapsible=icon]:justify-center">
          {state === "collapsed" ? (
            <button
              type="button"
              onClick={toggleSidebar}
              className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary/10 text-primary hover:bg-primary/20 transition-all active:scale-95"
            >
              <PanelLeft className="h-5 w-5" />
            </button>
          ) : (
            <>
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-primary text-primary-foreground font-bold text-xs shadow-lg shadow-primary/20">
                AK
              </div>
              <div className="flex flex-col flex-1 overflow-hidden">
                <span className="text-sm font-bold tracking-tight text-foreground truncate">{t("app.name")}</span>
                <span className="text-[10px] uppercase tracking-wider text-muted-foreground/70 font-medium truncate">{t("app.workspace")}</span>
              </div>
              <button
                type="button"
                onClick={toggleSidebar}
                className="flex h-8 w-8 items-center justify-center rounded-md text-muted-foreground/50 hover:bg-accent hover:text-foreground transition-colors"
                title="Collapse Sidebar"
              >
                <ChevronLeft className="h-4 w-4" />
              </button>
            </>
          )}
        </div>
      </SidebarHeader>

      <SidebarContent className="py-4">
        <SidebarGroup>
          <SidebarGroupLabel className="px-4 text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground/50 mb-2 group-data-[collapsible=icon]:hidden">
            {t("nav.section.primary")}
          </SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu className="gap-1 px-2 group-data-[collapsible=icon]:px-0">
              {[dashboardItem, repositoryItem, organizationsItem].filter(Boolean).map((item) => (
                <SidebarMenuItem key={item!.id} className="group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:justify-center">
                  <SidebarMenuButton
                    isActive={activeId === item!.id}
                    onClick={() => onSelect(item!.id)}
                    tooltip={t(`nav.${item!.id}`)}
                    className={cn(
                      "transition-all duration-200 rounded-lg",
                      activeId === item!.id
                        ? "bg-primary/10 text-primary font-medium hover:bg-primary/15"
                        : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
                      "group-data-[collapsible=icon]:size-9 group-data-[collapsible=icon]:p-0 group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:items-center group-data-[collapsible=icon]:justify-center"
                    )}
                  >
                    <div className={cn(
                      "flex items-center justify-center shrink-0",
                      activeId === item!.id ? "text-primary" : "text-muted-foreground/70"
                    )}>
                      {item!.icon}
                    </div>
                    <span className="ml-1 group-data-[collapsible=icon]:hidden">{t(`nav.${item!.id}`)}</span>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>

        <SidebarGroup className="mt-4">
          <SidebarGroupLabel className="px-4 text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground/50 mb-2 group-data-[collapsible=icon]:hidden">
            {t("nav.section.settings")}
          </SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu className="gap-1 px-2 group-data-[collapsible=icon]:px-0">
              {settingsItem && (
                <SidebarMenuItem className="group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:justify-center">
                  <SidebarMenuButton
                    isActive={activeId === settingsItem.id}
                    onClick={() => onSelect(settingsItem.id)}
                    tooltip={t("nav.settings")}
                    className={cn(
                      "transition-all duration-200 rounded-lg",
                      activeId === settingsItem.id
                        ? "bg-primary/10 text-primary font-medium hover:bg-primary/15"
                        : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
                      "group-data-[collapsible=icon]:size-9 group-data-[collapsible=icon]:p-0 group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:items-center group-data-[collapsible=icon]:justify-center"
                    )}
                  >
                    <div className={cn(
                      "flex items-center justify-center shrink-0",
                      activeId === settingsItem.id ? "text-primary" : "text-muted-foreground/70"
                    )}>
                      {settingsItem.icon}
                    </div>
                    <span className="ml-1 group-data-[collapsible=icon]:hidden">{t("nav.settings")}</span>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              )}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter className="border-t border-border/40 p-4 group-data-[collapsible=icon]:p-0 group-data-[collapsible=icon]:h-14 group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:items-center group-data-[collapsible=icon]:justify-center">
        <div className="flex items-center gap-3 px-1 group-data-[collapsible=icon]:px-0">
          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-accent text-[10px] font-bold uppercase">
            v0
          </div>
          <div className="flex flex-col group-data-[collapsible=icon]:hidden">
            <span className="text-[10px] font-bold uppercase tracking-widest text-muted-foreground/40">Version</span>
            <span className="text-[11px] font-medium text-muted-foreground">0.1.0-alpha</span>
          </div>
        </div>
      </SidebarFooter>
    </Sidebar>
  );
}

