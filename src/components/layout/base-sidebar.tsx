import { Layers, PanelLeft, Settings } from "lucide-react";
import type { ReactNode } from "react";

import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from "@/components/ui/sidebar";
import { useI18n } from "@/i18n/i18n";
import { useUsage } from "@/hooks/useUsage";
import { useNavigationStore } from "@/stores/navigation-store";
import { cn } from "@/lib/utils";

interface BaseSidebarProps {
  subtitleKey?: string;
  children: ReactNode;
  footerExtra?: ReactNode;
  contentClassName?: string;
}

export function BaseSidebar({
  subtitleKey = "app.workspace",
  children,
  footerExtra,
  contentClassName,
}: BaseSidebarProps) {
  const { t } = useI18n();
  const { state, toggleSidebar } = useSidebar();
  const { count, limit, isFree } = useUsage();
  const navigateTo = useNavigationStore((s) => s.navigateTo);
  const currentPage = useNavigationStore((s) => s.currentPage);

  return (
    <Sidebar
      collapsible="offcanvas"
      variant="floating"
      className="bg-transparent [&_[data-sidebar=sidebar]]:bg-white/70 [&_[data-sidebar=sidebar]]:backdrop-blur-2xl dark:[&_[data-sidebar=sidebar]]:bg-zinc-950/70"
    >
      <SidebarHeader
        data-tauri-drag-region
        className="flex flex-col gap-2 px-3 pt-2 pb-2 group-data-[collapsible=icon]:px-0 [-webkit-app-region:drag] [&_button]:[-webkit-app-region:no-drag] [&_input]:[-webkit-app-region:no-drag] [&_a]:[-webkit-app-region:no-drag]"
      >
        <div
          data-tauri-drag-region
          className="flex h-7 w-full items-center justify-end group-data-[collapsible=icon]:justify-center"
        >
          <button
            type="button"
            onClick={toggleSidebar}
            className="flex h-7 w-7 items-center justify-center rounded-lg text-zinc-500 transition-all hover:bg-zinc-200/60 hover:text-zinc-900 dark:hover:bg-zinc-800/60 dark:hover:text-white"
            title={state === "collapsed" ? t("sidebar.expandSidebar") : t("sidebar.collapseSidebar")}
          >
            <PanelLeft className="h-4 w-4" />
          </button>
        </div>
        <div
          data-tauri-drag-region
          className="flex w-full items-center gap-3 group-data-[collapsible=icon]:hidden"
        >
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-purple-600 shadow-md shadow-purple-600/30">
            <Layers className="h-5 w-5 text-white" />
          </div>
          <div className="flex flex-1 flex-col overflow-hidden">
            <span className="truncate text-sm font-bold tracking-tight text-zinc-900 dark:text-white">
              {t("app.name")}
            </span>
            <span className="truncate text-[9px] font-bold uppercase tracking-widest text-zinc-500">
              {t(subtitleKey)}
            </span>
          </div>
        </div>
      </SidebarHeader>

      <SidebarContent
        className={
          contentClassName ??
          "custom-scrollbar gap-1 pt-4 pb-2 group-data-[collapsible=icon]:gap-0 group-data-[collapsible=icon]:pt-2"
        }
      >
        {children}
      </SidebarContent>

      <SidebarFooter className="p-2">
        {isFree && limit !== null && state !== "collapsed" && (
          <div className="mb-2 px-3 py-2">
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
        {footerExtra}
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              onClick={() => navigateTo("settings")}
              isActive={currentPage === "settings"}
              tooltip={t("nav.settings")}
              className={cn(
                "h-10 rounded-xl px-3 transition-colors duration-150",
                currentPage === "settings"
                  ? "bg-white/70 text-zinc-900 shadow-sm shadow-black/5 dark:bg-zinc-800/70 dark:text-white"
                  : "text-zinc-600 hover:bg-zinc-200/40 dark:text-zinc-400 dark:hover:bg-zinc-800/40",
                "group-data-[collapsible=icon]:size-10 group-data-[collapsible=icon]:p-0",
              )}
            >
              <div className="flex shrink-0 items-center justify-center text-zinc-500 dark:text-zinc-400">
                <Settings className="h-4 w-4" />
              </div>
              <span className="ml-3 text-[13px] font-medium group-data-[collapsible=icon]:hidden">
                {t("nav.settings")}
              </span>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  );
}
