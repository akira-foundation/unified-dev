import { CircleDot, ExternalLink, FileDiff, GitBranch, GitPullRequest, Plus, Settings2 } from "lucide-react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { StatCard } from "@/components/stat-card";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent } from "../ui/card";
import { Tooltip, TooltipContent, TooltipTrigger } from "../ui/tooltip";
import { PageHeader, PageHeaderMeta, PageHeaderTitle } from "../layout/page-header";
import { AppbarActions } from "../layout/appbar-actions";
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
  onOpenUrl,
  onConfigOpen,
  onCreateIssue,
  onCreateBranch,
}: RepoDetailHeaderProps) {
  const { t } = useI18n();

  return (
    <>
      <AppbarActions>
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
      </AppbarActions>
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
      </PageHeader>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label={t("pages.repositoryDetail.stats.openPrs")} value={openPrsCount} icon={GitPullRequest} color="text-purple-500" bg="bg-purple-500/10" loading={prsLoading} />
        <StatCard label={t("pages.repositoryDetail.stats.draftPrs")} value={draftPrsCount} icon={FileDiff} color="text-zinc-500" bg="bg-zinc-500/10" loading={prsLoading} />
        <StatCard label={t("pages.repositoryDetail.stats.openIssues")} value={openIssuesCount} icon={CircleDot} color="text-emerald-500" bg="bg-emerald-500/10" loading={issuesLoading} />
        <button
          onClick={() => {
            if (defaultBranch !== "—") {
              void onOpenUrl(`https://github.com/${activeRepo.owner}/${activeRepo.name}/tree/${defaultBranch}`);
            }
          }}
          className={cn("w-full rounded-xl text-left", defaultBranch !== "—" && "group cursor-pointer")}
        >
          <Card className={cn("h-full transition-colors", defaultBranch !== "—" && "group-hover:border-blue-500/40")}>
            <CardContent className="pointer-events-none flex items-center gap-3 p-3">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md border border-zinc-100 bg-blue-500/10 text-blue-500 dark:border-zinc-800">
                <GitBranch size={15} />
              </div>
              <div className="min-w-0 flex-1">
                <div className="truncate font-mono text-xl font-semibold leading-none tracking-tight text-zinc-900 dark:text-white">
                  {defaultBranch}
                </div>
                <div className="mt-1 truncate text-[10px] font-semibold uppercase tracking-widest text-zinc-400 dark:text-zinc-500">
                  {t("pages.repositoryDetail.stats.defaultBranch")}
                </div>
              </div>
            </CardContent>
          </Card>
        </button>
      </div>
    </>
  );
}
