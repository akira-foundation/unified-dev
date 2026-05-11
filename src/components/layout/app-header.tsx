import { Bell, ChevronLeft, Download, PanelLeft } from "lucide-react";
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
    const { goBack, canGoBack } = useNavigation("dashboard");
    const { t } = useI18n();
    const { update, installing, install } = useUpdater();
    const { activeTab, setActiveTab, previousTab } = useAgentsStore();
    const { state: sidebarState, toggleSidebar } = useSidebar();

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
                className={`flex h-9 items-center justify-between pr-4 [-webkit-app-region:drag] [&_button]:[-webkit-app-region:no-drag] [&_input]:[-webkit-app-region:no-drag] [&_a]:[-webkit-app-region:no-drag] ${sidebarState === "collapsed" ? "pl-24" : "pl-3 md:pl-4"}`}
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
                        <span className="text-[12px] font-semibold tracking-tight text-foreground/80 leading-none">{t("app.name")}</span>
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
                    </div>
                </div>

                <div className="flex items-center gap-1">
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
                    <button className="inline-flex h-7 w-7 items-center justify-center rounded-md text-muted-foreground hover:bg-accent hover:text-accent-foreground">
                        <Bell className="h-3.5 w-3.5" />
                    </button>
                </div>
            </div>
        </header>
    );
}
