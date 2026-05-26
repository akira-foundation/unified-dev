import { ChevronLeft, Download, GitBranch, PanelLeft, Search } from "lucide-react";
import { NotificationsDropdown } from "@/components/notifications-dropdown";
import { useSearchStore } from "@/stores/search-store";
import { useNavigationStore } from "@/stores/navigation-store";
import { useImportViewStore } from "@/stores/import-view-store";
import { useOrganizations } from "@/hooks/useOrganizations";
import { useQuery } from "@tanstack/react-query";
import { projectService } from "@/services/projectService";
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
    const activeOrganizationId = useNavigationStore((s) => s.activeOrganizationId);
    const activeProjectId = useNavigationStore((s) => s.activeProjectId);
    const importSelectedOrg = useImportViewStore((s) => s.selectedOrg);
    const setImportSelectedOrg = useImportViewStore((s) => s.setSelectedOrg);
    const { organizations } = useOrganizations();
    const activeOrgName = organizations.find((o) => o.id === activeOrganizationId)?.name;
    const { data: projects = [] } = useQuery({ queryKey: ["projects"], queryFn: () => projectService.list() });
    const activeProjectName = projects.find((p) => p.id === activeProjectId)?.name;
    const isAgentMode = useNavigationStore((s) => s.isAgentMode);
    const selectedIssueId = useAgentsStore((s) => s.selectedIssueId);
    const selectedSkill = useAgentsStore((s) => s.selectedSkill);
    const selectedSkillSource = useAgentsStore((s) => s.selectedSkillSource);
    const agentRepositoryGroups = useAgentsStore((s) => s.repositoryGroups);
    const activeThread = isAgentMode
        ? agentRepositoryGroups.flatMap((g) => g.repositories).flatMap((r) => r.issues).find((i) => i.id === selectedIssueId) ?? null
        : null;

    const inImportDetail = currentPage === "import-repositories" && !!importSelectedOrg;

    const handleBack = () => {
        if (inImportDetail) {
            setImportSelectedOrg(null);
        } else if (activeTab === "skill-source") {
            setActiveTab("skills");
        } else if (activeTab === "manage-skill") {
            setActiveTab(previousTab ?? "skills");
        } else {
            goBack();
        }
    };

    const isBackEnabled = inImportDetail || activeTab === "skill-source" || activeTab === "manage-skill" || canGoBack;

    return (
        <header
            data-tauri-drag-region
            className="sticky top-0 z-50 w-full pt-2 [-webkit-app-region:drag]"
        >
            <div
                data-tauri-drag-region
                className={`flex h-11 items-center justify-between pr-4 [-webkit-app-region:drag] [&_button]:[-webkit-app-region:no-drag] [&_input]:[-webkit-app-region:no-drag] [&_a]:[-webkit-app-region:no-drag] ${sidebarState === "collapsed" ? "pl-24" : "pl-3 md:pl-4"}`}
            >
                <div className="flex min-w-0 items-center gap-2">
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
                    <div className="flex min-w-0 items-baseline gap-1.5">
                        <button
                            onClick={() => navigateTo("dashboard")}
                            className="shrink-0 text-[12px] font-semibold tracking-tight text-foreground/80 leading-none transition-colors hover:text-foreground"
                        >
                            {t("app.name")}
                        </button>
                        <div className="hidden items-center gap-1 xl:flex">
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
                                currentPage === "pr-review" || currentPage === "pr-detail"
                                    ? { labelKey: "nav.prs", page: "prs" as const, title: activePr?.title }
                                    : currentPage === "issue-detail"
                                        ? { labelKey: "nav.issues", page: "issues" as const, title: activeIssue?.title }
                                        : currentPage === "repository-detail"
                                            ? { labelKey: "nav.repositories", page: "repository" as const, title: activeRepo ? `${activeRepo.owner}/${activeRepo.name}` : undefined }
                                            : currentPage === "project-detail"
                                                ? { labelKey: "nav.projects", page: "projects" as const, title: activeProjectName }
                                            : currentPage === "organization"
                                                ? { labelKey: "nav.organizations", page: "organizations" as const, title: activeOrgName }
                                                : currentPage === "import-repositories"
                                                    ? { labelKey: "nav.organizations", page: "organizations" as const, title: t("pages.importRepos.title") }
                                                    : null;
                            return (
                                <>
                                    <span className={`text-[12px] leading-none text-muted-foreground/40 ${detail?.title ? "hidden lg:inline" : ""}`}>/</span>
                                    {detail ? (
                                        <button
                                            onClick={() => navigateTo(detail.page)}
                                            className="hidden shrink-0 text-[12px] font-medium lowercase leading-none text-foreground/70 transition-colors hover:text-foreground hover:underline lg:inline"
                                        >
                                            {t(detail.labelKey)}
                                        </button>
                                    ) : (
                                        <span className="shrink-0 text-[12px] font-medium lowercase leading-none text-foreground/70">{t(`nav.${currentPage}`)}</span>
                                    )}
                                    {detail?.title && (
                                        <>
                                            <span className="text-[12px] leading-none text-muted-foreground/40">/</span>
                                            <span
                                                title={detail.title}
                                                className="max-w-[140px] truncate text-[12px] font-medium lowercase leading-none text-foreground/70 sm:max-w-[200px] md:max-w-[280px]"
                                            >
                                                {detail.title}
                                            </span>
                                        </>
                                    )}
                                    {isAgentMode && activeTab === "workspace" && activeThread && (
                                        <>
                                            <span className="text-[12px] leading-none text-muted-foreground/40">/</span>
                                            <span
                                                title={activeThread.title}
                                                className="max-w-[140px] truncate text-[12px] font-medium lowercase leading-none text-foreground/70 sm:max-w-[200px] md:max-w-[280px]"
                                            >
                                                {activeThread.title}
                                            </span>
                                            <span className="hidden items-center gap-1.5 text-[11px] leading-none text-muted-foreground/50 lg:inline-flex">
                                                <span className="text-muted-foreground/30">·</span>
                                                <span className="max-w-[120px] truncate">{activeThread.repoName}</span>
                                                <GitBranch className="h-3 w-3" />
                                                <span className="max-w-[160px] truncate font-mono">{activeThread.branchName}</span>
                                            </span>
                                        </>
                                    )}
                                    {isAgentMode && activeTab !== "workspace" && (() => {
                                        const isSkillTab = activeTab === "skills" || activeTab === "manage-skill" || activeTab === "skill-source";
                                        const isAutomationTab = activeTab === "automations" || activeTab === "create-automation";
                                        const sectionLabel = isSkillTab
                                            ? t("pages.skills.title")
                                            : isAutomationTab
                                                ? t("pages.automations.title")
                                                : activeTab === "mcp"
                                                    ? "MCP"
                                                    : null;
                                        if (!sectionLabel) return null;
                                        const leaf =
                                            activeTab === "manage-skill"
                                                ? (selectedSkill?.name ?? selectedSkill?.id ?? null)
                                                : activeTab === "skill-source"
                                                    ? (selectedSkillSource?.name ?? null)
                                                    : null;
                                        return (
                                            <>
                                                <span className="text-[12px] leading-none text-muted-foreground/40">/</span>
                                                {leaf ? (
                                                    <button
                                                        onClick={() => setActiveTab(isSkillTab ? "skills" : "automations")}
                                                        className="hidden shrink-0 text-[12px] font-medium leading-none text-foreground/70 transition-colors hover:text-foreground hover:underline lg:inline"
                                                    >
                                                        {sectionLabel}
                                                    </button>
                                                ) : (
                                                    <span className="shrink-0 text-[12px] font-medium leading-none text-foreground/70">{sectionLabel}</span>
                                                )}
                                                {leaf && (
                                                    <>
                                                        <span className="text-[12px] leading-none text-muted-foreground/40">/</span>
                                                        <span
                                                            title={leaf}
                                                            className="max-w-[160px] truncate text-[12px] font-medium leading-none text-foreground/70 sm:max-w-[220px] md:max-w-[280px]"
                                                        >
                                                            {leaf}
                                                        </span>
                                                    </>
                                                )}
                                            </>
                                        );
                                    })()}
                                </>
                            );
                        })()}
                    </div>
                </div>

                <div className="flex min-w-0 flex-1 justify-center px-2 md:px-4">
                    {searchProvider && (
                        <button
                            onClick={() => openSearch(true)}
                            className="flex h-8 w-full max-w-md min-w-0 items-center gap-2 rounded-md border border-zinc-200 bg-zinc-100/60 px-3 text-sm text-muted-foreground transition-colors hover:bg-zinc-100 dark:border-zinc-800 dark:bg-zinc-900/50 dark:hover:bg-zinc-800/50"
                        >
                            <Search className="h-3.5 w-3.5 shrink-0" />
                            <span className="flex-1 truncate text-left">{searchProvider.placeholder}</span>
                            <kbd className="hidden rounded border border-zinc-300 px-1.5 py-0.5 text-[10px] font-medium dark:border-zinc-700 sm:inline">/</kbd>
                        </button>
                    )}
                </div>

                <div className="flex shrink-0 items-center gap-2">
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
