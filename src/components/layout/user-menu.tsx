import { invoke } from "@tauri-apps/api/core";
import { CreditCard, LogOut, Settings, User } from "lucide-react";
import { useState } from "react";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useAvatar } from "@/hooks/useAvatar";
import { useLicense } from "@/hooks/useLicense";
import { useI18n } from "@/i18n/i18n";
import { useLicenseStore } from "@/stores/license-store";
import { useNavigationStore } from "@/stores/navigation-store";
import { useOnboardingStore } from "@/stores/onboarding-store";
import { useSidebar } from "@/components/ui/sidebar";
import { cn } from "@/lib/utils";

const PLAN_BADGE: Record<string, string> = {
  pro: "bg-purple-500/15 text-purple-400",
  ultimate: "bg-amber-500/15 text-amber-400",
};

export function UserMenu() {
  const { t } = useI18n();
  const { license, currentPlan } = useLicense();
  const avatarUrl = useAvatar(license?.email);
  const { clear } = useLicenseStore();
  const navigateTo = useNavigationStore((s) => s.navigateTo);
  const setSettingsTab = useNavigationStore((s) => s.setSettingsTab);
  const { state } = useSidebar();
  const [open, setOpen] = useState(false);

  const email = license?.email ?? "";
  const isCollapsed = state === "collapsed";

  async function handleLogout() {
    setOpen(false);
    clear();
    useOnboardingStore.getState().requireAuth();
    try {
      await invoke("oauth_logout");
    } catch {}
  }

  function handleSettings() {
    setOpen(false);
    navigateTo("settings");
    setSettingsTab("general");
  }

  function handleSubscription() {
    setOpen(false);
    navigateTo("settings");
    setSettingsTab("subscription");
  }

  const avatar = (
    <div className="flex h-7 w-7 shrink-0 items-center justify-center overflow-hidden rounded-full bg-zinc-800 text-[11px] font-semibold text-zinc-300">
      {avatarUrl ? (
        <img src={avatarUrl} alt="" className="h-full w-full object-cover" />
      ) : (
        <User className="h-3.5 w-3.5 text-zinc-400" />
      )}
    </div>
  );

  return (
    <DropdownMenu open={open} onOpenChange={setOpen}>
      <DropdownMenuTrigger asChild>
        <button
          className={cn(
            "flex w-full items-center gap-2.5 rounded-xl px-3 py-2 text-left text-zinc-600 transition-colors hover:bg-zinc-200/40 dark:text-zinc-400 dark:hover:bg-zinc-800/40",
            "group-data-[collapsible=icon]:h-10 group-data-[collapsible=icon]:w-10 group-data-[collapsible=icon]:justify-center group-data-[collapsible=icon]:p-0",
          )}
        >
          {avatar}
          {!isCollapsed && (
            <div className="flex min-w-0 flex-1 flex-col">
              <span className="truncate text-[12px] font-medium text-zinc-700 dark:text-zinc-200">
                {email}
              </span>
              {currentPlan && (
                <span
                  className={cn(
                    "w-fit rounded px-1 py-px text-[10px] font-semibold capitalize",
                    PLAN_BADGE[currentPlan] ?? "bg-zinc-500/10 text-zinc-400",
                  )}
                >
                  {currentPlan}
                </span>
              )}
            </div>
          )}
        </button>
      </DropdownMenuTrigger>

      <DropdownMenuContent
        side="top"
        align="start"
        className="w-64 p-0 bg-zinc-950 border-zinc-800"
      >
        <div className="flex items-center gap-2.5 px-3 py-3 border-b border-zinc-800">
          {avatar}
          <div className="flex min-w-0 flex-col">
            <span className="truncate text-[12px] font-medium text-zinc-200">{email}</span>
            {currentPlan && (
              <span
                className={cn(
                  "w-fit rounded px-1 py-px text-[10px] font-semibold capitalize",
                  PLAN_BADGE[currentPlan] ?? "bg-zinc-500/10 text-zinc-400",
                )}
              >
                {currentPlan}
              </span>
            )}
          </div>
        </div>

        <div className="p-1">
          <DropdownMenuItem
            onClick={handleSettings}
            className="flex items-center gap-2 rounded-lg px-2 py-1.5 text-[13px] text-zinc-300 hover:bg-zinc-800 hover:text-zinc-100 cursor-pointer"
          >
            <Settings className="h-3.5 w-3.5 text-zinc-500" />
            {t("nav.settings")}
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={handleSubscription}
            className="flex items-center gap-2 rounded-lg px-2 py-1.5 text-[13px] text-zinc-300 hover:bg-zinc-800 hover:text-zinc-100 cursor-pointer"
          >
            <CreditCard className="h-3.5 w-3.5 text-zinc-500" />
            {t("nav.subscription")}
          </DropdownMenuItem>
        </div>

        <DropdownMenuSeparator className="bg-zinc-800" />

        <div className="p-1">
          <DropdownMenuItem
            onClick={handleLogout}
            className="flex items-center gap-2 rounded-lg px-2 py-1.5 text-[13px] text-rose-400 hover:bg-zinc-800 hover:text-rose-300 cursor-pointer"
          >
            <LogOut className="h-3.5 w-3.5" />
            {t("nav.signOut")}
          </DropdownMenuItem>
        </div>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
