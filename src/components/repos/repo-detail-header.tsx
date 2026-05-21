import { CircleDot, ExternalLink, FileDiff, GitBranch, GitPullRequest, Plus, RotateCw, Settings2 } from "lucide-react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { StatCard } from "@/components/stat-card";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardDescription, CardHeader } from "../ui/card";
import { Tooltip, TooltipContent, TooltipTrigger } from "../ui/tooltip";
import { PageHeader, PageHeaderActions, PageHeaderMeta, PageHeaderTitle } from "../layout/page-header";
import type { ActiveRepo } from "@/stores/navigation-store";
import type { OrganizationRepoWithOrg } from "@/types/organization";

interface RepoDetailHeaderProps {
  activeRepo: ActiveRepo;
  currentRepo: OrganizationRepoWithOrg | null;
  defaultBranch: string;
  visibility: string | null;
  dateLabel: string;
  tab: "prs" | "issues" | "branches";
  openPrsCount: number;
  draftPrsCount: number;
  openIssuesCount: number;
  prsLoading: boolean;
  issuesLoading: boolean;
  syncing: boolean;
  onSync: () => void;
  onOpenUrl: (url: string) => void;
  onConfigOpen: () => void;
  onCreateIssue: () => void;
  onCreateBranch: () => void;
}

export function RepoDetailHeader({
  activeRepo,
  currentRepo,
  defaultBranch,
  visibility,
  dateLabel,
  tab,
  openPrsCount,
  draftPrsCount,
  openIssuesCount,
  prsLoading,
  issuesLoading,
  syncing,
  onSync,
  onOpenUrl,
  onConfigOpen,
  onCreateIssue,
  onCreateBranch,
}: RepoDetailHeaderProps) {
  const { t } = useI18n();

  return (
    <>
      <PageHeader>
        <div>
          <PageHeaderTitle>
            {activeRepo.owner}/{activeRepo.name}
          </PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("app.name")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
            {defaultBranch !== "—" && (
              <>
                <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
                <span className="flex items-center gap-1 text-zinc-500 dark:text-zinc-400">
                  <GitBranch className="h-3 w-3" />
                  {defaultBranch}
                </span>
              </>
            )}
            {visibility && (
              <>
                <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
                <Badge variant={visibility === "private" ? "warning" : "secondary"} className="text-[10px] px-1.5 py-0">
                  {visibility}
                </Badge>
              </>
            )}
            {currentRepo?.is_fork && (
              <>
                <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
                <Badge variant="info" className="text-[10px] px-1.5 py-0">Fork</Badge>
              </>
            )}
            <button
              type="button"
              onClick={onConfigOpen}
              className="ml-1 inline-flex h-7 w-7 items-center justify-center rounded-md text-zinc-400 transition-colors hover:bg-zinc-100 hover:text-zinc-700 dark:hover:bg-zinc-900 dark:hover:text-zinc-200"
              title={t("common.configureSync")}
            >
              <Settings2 className="h-4 w-4" />
            </button>
          </PageHeaderMeta>
        </div>
        <PageHeaderActions className="gap-2">
          <Tooltip>
            <TooltipTrigger asChild>
              <Button variant="outline" size="icon" onClick={onSync} disabled={syncing}>
                <RotateCw className={cn("h-4 w-4", syncing && "animate-spin")} />
              </Button>
            </TooltipTrigger>
            <TooltipContent>{t("common.sync")}</TooltipContent>
          </Tooltip>
          <Tooltip>
            <TooltipTrigger asChild>
              <Button
                variant="outline"
                size="icon"
                onClick={() => {
                  const ghOwner = currentRepo?.fork_owner ?? activeRepo.owner;
                  const ghRepo = currentRepo?.fork_repo ?? activeRepo.name;
                  void onOpenUrl(`https://github.com/${ghOwner}/${ghRepo}`);
                }}
              >
                <ExternalLink className="h-4 w-4" />
              </Button>
            </TooltipTrigger>
            <TooltipContent>View on GitHub</TooltipContent>
          </Tooltip>
          {tab === "issues" && (
            <Button onClick={onCreateIssue}>
              <Plus size={18} />
              {t("pages.repositoryIssues.newIssue")}
            </Button>
          )}
          {tab === "branches" && (
            <Button onClick={onCreateBranch}>
              <Plus size={18} />
              {t("pages.repositoryBranches.newBranch")}
            </Button>
          )}
        </PageHeaderActions>
      </PageHeader>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label={t("pages.repositoryDetail.stats.openPrs")} value={openPrsCount} icon={GitPullRequest} color="text-purple-500" bg="bg-purple-500/10" loading={prsLoading} />
        <StatCard label={t("pages.repositoryDetail.stats.draftPrs")} value={draftPrsCount} icon={FileDiff} color="text-zinc-500" bg="bg-zinc-500/10" loading={prsLoading} />
        <StatCard label={t("pages.repositoryDetail.stats.openIssues")} value={openIssuesCount} icon={CircleDot} color="text-emerald-500" bg="bg-emerald-500/10" loading={issuesLoading} />
        <Card
          className={defaultBranch !== "—" ? "cursor-pointer hover:border-blue-500/40 transition-colors" : ""}
          onClick={() => {
            if (defaultBranch !== "—") {
              void onOpenUrl(`https://github.com/${activeRepo.owner}/${activeRepo.name}/tree/${defaultBranch}`);
            }
          }}
        >
          <CardHeader className="flex flex-row items-center justify-between p-5 pb-3">
            <CardDescription className="text-[10px] font-bold uppercase tracking-widest">
              {t("pages.repositoryDetail.stats.defaultBranch")}
            </CardDescription>
            <div className="h-8 w-8 rounded-lg flex items-center justify-center border border-zinc-100 dark:border-zinc-800 shadow-sm bg-blue-500/10 text-blue-500">
              <GitBranch size={16} />
            </div>
          </CardHeader>
          <CardContent className="p-4 pt-4">
            <div className="text-2xl font-black tracking-tight text-zinc-900 dark:text-white leading-none font-mono">
              {defaultBranch}
            </div>
          </CardContent>
        </Card>
      </div>
    </>
  );
}
