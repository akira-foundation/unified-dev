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
import { useProviderHierarchy } from "@/hooks/useProviderHierarchy";
import { useNavigation } from "@/hooks/useNavigation";
import { SidebarProviderSection } from "@/components/layout/sidebar-provider-section";

interface AppSidebarProps {
  items: NavItem[];
  activeId: NavItem["id"];
  onSelect: (id: NavItem["id"]) => void;
}

export function AppSidebar({ items, activeId, onSelect }: AppSidebarProps) {
  const { t } = useI18n();
  const { state, toggleSidebar } = useSidebar();
  const { providersWithOrganizations } = useProviderHierarchy();
  const { activeOrganizationId, setActiveOrganizationId, setCurrentPage } = useNavigation("dashboard");

  const dashboardItem = items.find((item) => item.id === "dashboard");
  const repositoryItem = items.find((item) => item.id === "repository");
  const providersItem = items.find((item) => item.id === "providers");
  const settingsItem = items.find((item) => item.id === "settings");

  return (
    <Sidebar collapsible="icon" className="border-r border-border/40 bg-background/50 dark:bg-zinc-950/50 backdrop-blur-xl">
      <SidebarHeader className="h-16 border-b border-border/10 flex items-center px-4 group-data-[collapsible=icon]:px-0">
        <div className="flex items-center gap-3 w-full group-data-[collapsible=icon]:justify-center">
          {state === "collapsed" ? (
            <button
              type="button"
              onClick={toggleSidebar}
              className="relative flex h-10 w-10 items-center justify-center rounded-xl bg-zinc-100 dark:bg-zinc-900 transition-all hover:bg-zinc-200 dark:hover:bg-zinc-800 active:scale-95 group/toggle overflow-hidden"
              title="Expand Sidebar"
            >
              <div className="absolute inset-0 bg-primary/10 opacity-0 group-hover/toggle:opacity-100 transition-opacity" />
              <PanelLeft className="h-5 w-5 text-muted-foreground group-hover/toggle:text-primary transition-colors" />
            </button>
          ) : (
            <>
              <div className="relative">
                <div className="absolute inset-0 bg-primary/30 blur-lg rounded-full" />
                <div className="relative flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-primary to-purple-600 text-white font-bold text-xs shadow-lg shadow-primary/20">
                  AK
                </div>
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
                className="flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground hover:bg-zinc-100 dark:hover:bg-zinc-900 hover:text-foreground dark:hover:text-white transition-all"
                title="Collapse Sidebar"
              >
                <ChevronLeft className="h-4 w-4" />
              </button>
            </>
          )}
        </div>
      </SidebarHeader>

      <SidebarContent className="py-6">
        <SidebarGroup>
          <SidebarGroupLabel className="px-5 text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground/60 mb-4 group-data-[collapsible=icon]:hidden">
            {t("nav.section.primary")}
          </SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu className="gap-1.5 px-3 group-data-[collapsible=icon]:px-0">
              {[dashboardItem, repositoryItem, providersItem].filter(Boolean).map((item) => (
                <SidebarMenuItem key={item!.id} className="group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:justify-center">
                  <SidebarMenuButton
                    isActive={activeId === item!.id}
                    onClick={() => onSelect(item!.id)}
                    tooltip={t(`nav.${item!.id}`)}
                    className={cn(
                      "transition-all duration-200 rounded-xl h-11 px-4",
                      activeId === item!.id
                        ? "bg-zinc-100 dark:bg-zinc-900 text-foreground dark:text-white font-bold shadow-sm"
                        : "text-muted-foreground hover:bg-zinc-100/50 dark:hover:bg-zinc-900/50 hover:text-foreground dark:hover:text-zinc-300",
                      "group-data-[collapsible=icon]:size-10 group-data-[collapsible=icon]:p-0 group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:items-center group-data-[collapsible=icon]:justify-center"
                    )}
                  >
                    <div className={cn(
                      "flex items-center justify-center shrink-0",
                      activeId === item!.id ? "text-primary" : "text-muted-foreground/70"
                    )}>
                      {item!.icon}
                    </div>
                    <span className="ml-3 group-data-[collapsible=icon]:hidden">{t(`nav.${item!.id}`)}</span>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>

        <SidebarGroup className="mt-8">
          <SidebarGroupLabel className="px-5 text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground/60 mb-4 group-data-[collapsible=icon]:hidden">
            Providers
          </SidebarGroupLabel>
          <SidebarGroupContent className="px-3 group-data-[collapsible=icon]:hidden">
            <div className="flex flex-col gap-3">
              {providersWithOrganizations.map((provider) => (
                <SidebarProviderSection
                  key={provider.id}
                  provider={provider}
                  organizations={provider.organizations}
                  activeOrganizationId={activeOrganizationId}
                  onSelectOrganization={(organizationId) => {
                    setActiveOrganizationId(organizationId);
                    setCurrentPage("organization");
                  }}
                />
              ))}
            </div>
          </SidebarGroupContent>
        </SidebarGroup>

        <SidebarGroup className="mt-8">
          <SidebarGroupLabel className="px-5 text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground/60 mb-4 group-data-[collapsible=icon]:hidden">
            {t("nav.section.settings")}
          </SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu className="gap-1.5 px-3 group-data-[collapsible=icon]:px-0">
              {settingsItem && (
                <SidebarMenuItem className="group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:justify-center">
                  <SidebarMenuButton
                    isActive={activeId === settingsItem.id}
                    onClick={() => onSelect(settingsItem.id)}
                    tooltip={t("nav.settings")}
                    className={cn(
                      "transition-all duration-200 rounded-xl h-11 px-4",
                      activeId === settingsItem.id
                        ? "bg-zinc-100 dark:bg-zinc-900 text-foreground dark:text-white font-bold shadow-sm"
                        : "text-muted-foreground hover:bg-zinc-100/50 dark:hover:bg-zinc-900/50 hover:text-foreground dark:hover:text-zinc-300",
                      "group-data-[collapsible=icon]:size-10 group-data-[collapsible=icon]:p-0 group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:items-center group-data-[collapsible=icon]:justify-center"
                    )}
                  >
                    <div className={cn(
                      "flex items-center justify-center shrink-0",
                      activeId === settingsItem.id ? "text-primary" : "text-muted-foreground/70"
                    )}>
                      {settingsItem.icon}
                    </div>
                    <span className="ml-3 group-data-[collapsible=icon]:hidden">{t("nav.settings")}</span>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              )}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter className="border-t border-border/10 p-5 group-data-[collapsible=icon]:p-0 group-data-[collapsible=icon]:h-16 group-data-[collapsible=icon]:flex group-data-[collapsible=icon]:items-center group-data-[collapsible=icon]:justify-center">
        <div className="flex items-center gap-4 px-1 group-data-[collapsible=icon]:px-0">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-zinc-100 dark:bg-zinc-900 text-[10px] font-bold uppercase text-muted-foreground dark:text-zinc-400">
            v0
          </div>
          <div className="flex flex-col group-data-[collapsible=icon]:hidden">
            <span className="text-[10px] font-bold uppercase tracking-widest text-muted-foreground/60">Unified Engine</span>
            <span className="text-[11px] font-medium text-muted-foreground">0.1.0-alpha</span>
          </div>
        </div>
      </SidebarFooter>
    </Sidebar>
  );
}
