import { Bell, ChevronLeft, Download } from "lucide-react";
import { useNavigation } from "@/hooks/useNavigation";
import { useI18n } from "@/i18n/i18n";
import { useUpdater } from "@/hooks/useUpdater";
import { Button } from "@/components/ui/button";
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

    return (
        <header className="sticky top-0 z-50 w-full border-b border-border/40 bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
            <div className="flex h-14 items-center justify-between px-4 md:px-6">
                <div className="flex items-center gap-3">
                    <Button
                        variant="ghost"
                        size="icon"
                        onClick={goBack}
                        disabled={!canGoBack}
                        className="shrink-0"
                    >
                        <ChevronLeft className="h-4 w-4" />
                    </Button>
                    <div className="flex flex-col">
                        <span className="text-sm font-bold tracking-tight text-foreground leading-none">{t("app.name")}</span>
                        <div className="flex items-center gap-1 mt-0.5">
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
                    <button className="inline-flex h-9 w-9 items-center justify-center rounded-md text-muted-foreground hover:bg-accent hover:text-accent-foreground">
                        <Bell className="h-4 w-4" />
                    </button>
                </div>
            </div>
        </header>
    );
}
