import { ChevronLeft, Download, PanelLeft, Search } from "lucide-react";
import { NotificationsDropdown } from "@/components/notifications-dropdown";
import { useSearchStore } from "@/stores/search-store";
import { useNavigationStore } from "@/stores/navigation-store";
import { useNavigation } from "@/hooks/useNavigation";
import { useI18n } from "@/i18n/i18n";
import { useUpdater } from "@/hooks/useUpdater";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { Button } from "@/components/ui/button";
import { useSidebar } from "@/components/ui/sidebar";
import { appVersion } from "@/lib/app-meta";
import {
    Tooltip,
    TooltipContent,
    TooltipTrigger,
} from "@/components/ui/tooltip";

export function AppHeader() {
    const { goBack, canGoBack, currentPage, navigateTo } = useNavigation("dashboard");
    const { t } = useI18n();
    const { update, installing, install } = useUpdater();
    const { activeTab, setActiveTab, previousTab } = useAgentsStore();
    const { state: sidebarState, toggleSidebar } = useSidebar();
    const searchProvider = useSearchStore((s) => s.provider);
    const openSearch = useSearchStore((s) => s.setOpen);
    const activePr = useNavigationStore((s) => s.activePr);
    const activeIssue = useNavigationStore((s) => s.activeIssue);
    const activeRepo = useNavigationStore((s) => s.activeRepo);

    const handleBack = () => {
        if (activeTab === "skill-source") {
            setActiveTab("skills");
        } else if (activeTab === "manage-skill") {
            setActiveTab(previousTab ?? "skills");
        } else {
            goBack();
        }
    };

    const isBackEnabled = activeTab === "skill-source" || activeTab === "manage-skill" || canGoBack;

    return (
        <header
            data-tauri-drag-region
            className="sticky top-0 z-50 w-full pt-2 [-webkit-app-region:drag]"
        >
            <div
                data-tauri-drag-region
                className={`flex h-11 items-center justify-between pr-4 [-webkit-app-region:drag] [&_button]:[-webkit-app-region:no-drag] [&_input]:[-webkit-app-region:no-drag] [&_a]:[-webkit-app-region:no-drag] ${sidebarState === "collapsed" ? "pl-24" : "pl-3 md:pl-4"}`}
            >
                <div className="flex items-center gap-2">
                    {sidebarState === "collapsed" ? (
                        <Button
                            variant="ghost"
                            size="icon"
                            onClick={toggleSidebar}
                            className="shrink-0 h-7 w-7"
                            title={t("sidebar.expandSidebar")}
                        >
                            <PanelLeft className="h-3.5 w-3.5" />
                        </Button>
                    ) : null}
                    <Button
                        variant="ghost"
                        size="icon"
                        onClick={handleBack}
                        disabled={!isBackEnabled}
                        className="shrink-0 h-7 w-7"
                    >
                        <ChevronLeft className="h-3.5 w-3.5" />
                    </Button>
                    <div className="flex items-baseline gap-1.5">
                        <button
                            onClick={() => navigateTo("dashboard")}
                            className="text-[12px] font-semibold tracking-tight text-foreground/80 leading-none transition-colors hover:text-foreground"
                        >
                            {t("app.name")}
                        </button>
                        <div className="flex items-center gap-1">
                            <span className="text-[10px] text-muted-foreground leading-none">v{appVersion}</span>
                            {update && (
                                <Tooltip>
                                    <TooltipTrigger asChild>
                                        <button
                                            onClick={install}
                                            disabled={installing}
                                            className="text-[10px] text-primary leading-none hover:underline disabled:opacity-50"
                                        >
                                            v{update.version} available
                                        </button>
                                    </TooltipTrigger>
                                    <TooltipContent side="bottom" className="max-w-64">
                                        <p className="font-medium mb-1">Update available</p>
                                        {update.body && <p className="text-xs text-muted-foreground">{update.body}</p>}
                                        <p className="text-xs mt-1">{installing ? "Installing..." : "Click to install and restart"}</p>
                                    </TooltipContent>
                                </Tooltip>
                            )}
                        </div>
                        {currentPage !== "dashboard" && (() => {
                            const detail =
                                currentPage === "pr-review"
                                    ? { labelKey: "nav.prs", page: "prs" as const, title: activePr?.title }
                                    : currentPage === "issue-detail"
                                        ? { labelKey: "nav.issues", page: "issues" as const, title: activeIssue?.title }
                                        : currentPage === "repository-detail"
                                            ? { labelKey: "nav.repositories", page: "repository" as const, title: activeRepo ? `${activeRepo.owner}/${activeRepo.name}` : undefined }
                                            : null;
                            return (
                                <>
                                    <span className="text-[12px] leading-none text-muted-foreground/40">/</span>
                                    {detail ? (
                                        <button
                                            onClick={() => navigateTo(detail.page)}
                                            className="text-[12px] font-medium leading-none text-foreground/70 transition-colors hover:text-foreground hover:underline"
                                        >
                                            {t(detail.labelKey)}
                                        </button>
                                    ) : (
                                        <span className="text-[12px] font-medium leading-none text-foreground/70">{t(`nav.${currentPage}`)}</span>
                                    )}
                                    {detail?.title && (
                                        <>
                                            <span className="text-[12px] leading-none text-muted-foreground/40">/</span>
                                            <span
                                                title={detail.title}
                                                className="max-w-[280px] truncate text-[12px] font-medium leading-none text-foreground/70"
                                            >
                                                {detail.title}
                                            </span>
                                        </>
                                    )}
                                </>
                            );
                        })()}
                    </div>
                </div>

                <div className="flex flex-1 justify-center px-4">
                    {searchProvider && (
                        <button
                            onClick={() => openSearch(true)}
                            className="flex h-8 w-full max-w-md items-center gap-2 rounded-md border border-zinc-200 bg-zinc-100/60 px-3 text-sm text-muted-foreground transition-colors hover:bg-zinc-100 dark:border-zinc-800 dark:bg-zinc-900/50 dark:hover:bg-zinc-800/50"
                        >
                            <Search className="h-3.5 w-3.5 shrink-0" />
                            <span className="flex-1 truncate text-left">{searchProvider.placeholder}</span>
                            <kbd className="rounded border border-zinc-300 px-1.5 py-0.5 text-[10px] font-medium dark:border-zinc-700">/</kbd>
                        </button>
                    )}
                </div>

                <div className="flex items-center gap-2">
                    <div id="appbar-actions" className="flex items-center gap-2 empty:hidden" />
                    {update && (
                        <Tooltip>
                            <TooltipTrigger asChild>
                                <Button
                                    variant="ghost"
                                    size="icon"
                                    onClick={install}
                                    disabled={installing}
                                    className="relative text-primary"
                                >
                                    <Download className="h-4 w-4" />
                                    <span className="absolute top-1.5 right-1.5 h-1.5 w-1.5 rounded-full bg-primary" />
                                </Button>
                            </TooltipTrigger>
                            <TooltipContent side="bottom">
                                {installing ? "Installing update..." : `Install v${update.version}`}
                            </TooltipContent>
                        </Tooltip>
                    )}
                    <NotificationsDropdown />
                </div>
            </div>
        </header>
    );
}
