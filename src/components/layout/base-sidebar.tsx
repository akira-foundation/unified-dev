import { Layers, PanelLeft } from "lucide-react";
import type { ReactNode } from "react";

import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  useSidebar,
} from "@/components/ui/sidebar";
import { UserMenu } from "@/components/layout/user-menu";
import { useI18n } from "@/i18n/i18n";

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

  return (
    <Sidebar
      collapsible="offcanvas"
      variant="floating"
      className="bg-transparent [&_[data-sidebar=sidebar]]:bg-white/70 [&_[data-sidebar=sidebar]]:backdrop-blur-2xl dark:[&_[data-sidebar=sidebar]]:bg-[#262626]"
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
        {footerExtra}
        <UserMenu />
      </SidebarFooter>
    </Sidebar>
  );
}
