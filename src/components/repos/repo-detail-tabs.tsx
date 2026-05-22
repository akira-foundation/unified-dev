import { CircleDot, GitBranch, GitPullRequest } from "lucide-react";

import { useI18n } from "@/i18n/i18n";
import { issueScopeLabelKey, prScopeLabelKey } from "@/lib/work-visibility";
import { Skeleton } from "../ui/skeleton";
import { EmptyState } from "../ui/empty-state";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../ui/tabs";
import { PrListCard } from "./pr-list-card";
import { RepoBranchesTab } from "./repo-branches-tab";
import { IssueTable } from "../issues/issue-table";
import type { ActiveRepo } from "@/stores/navigation-store";
import type { useRepositoryDetail } from "@/hooks/useRepositoryDetail";
import type { IssueDto } from "@/types/issue";
import type { PullRequestDto } from "@/types/organization";
import type { IssueScope, PullRequestScope } from "@/types/work-visibility";

type RepoTab = "prs" | "issues" | "branches";

interface RepoDetailTabsProps {
  tab: RepoTab;
  onTabChange: (tab: RepoTab) => void;
  activeRepo: ActiveRepo;
  prScope: PullRequestScope;
  issueScope: IssueScope;
  setRepositoryPrScope: (orgId: string, repoName: string, scope: PullRequestScope) => void;
  setRepositoryIssueScope: (orgId: string, repoName: string, scope: IssueScope) => void;
  data: ReturnType<typeof useRepositoryDetail>;
  onNewTask: (pr: PullRequestDto) => void;
  onSelectIssue: (issue: IssueDto) => void;
  onNavigateToPrs: (prNumber?: number) => void;
  onDeleteBranch: (name: string) => void;
}

export function RepoDetailTabs({
  tab,
  onTabChange,
  activeRepo,
  prScope,
  issueScope,
  setRepositoryPrScope,
  setRepositoryIssueScope,
  data,
  onNewTask,
  onSelectIssue,
  onNavigateToPrs,
  onDeleteBranch,
}: RepoDetailTabsProps) {
  const { t } = useI18n();
  const { prs, prsLoading, issues, issuesLoading, branches, branchesLoading } = data;
  const openPrsCount = prs.length;
  const openIssuesCount = issues.filter((i) => i.status === "open").length;

  return (
    <Tabs value={tab} onValueChange={(v) => onTabChange(v as RepoTab)}>
      <TabsList>
        <TabsTrigger value="prs">
          <GitPullRequest className="h-4 w-4" />
          {t("pages.repositoryPrs.title")}
          {openPrsCount > 0 && (
            <span className="ml-1.5 rounded-full bg-zinc-200 dark:bg-zinc-700 px-1.5 py-0.5 text-[10px] font-bold leading-none">{openPrsCount}</span>
          )}
        </TabsTrigger>
        <TabsTrigger value="issues">
          <CircleDot className="h-4 w-4" />
          {t("pages.repositoryIssues.title")}
          {openIssuesCount > 0 && (
            <span className="ml-1.5 rounded-full bg-zinc-200 dark:bg-zinc-700 px-1.5 py-0.5 text-[10px] font-bold leading-none">{openIssuesCount}</span>
          )}
        </TabsTrigger>
        <TabsTrigger value="branches">
          <GitBranch className="h-4 w-4" />
          {t("pages.repositoryBranches.title")}
          {branches.length > 0 && (
            <span className="ml-1.5 rounded-full bg-zinc-200 dark:bg-zinc-700 px-1.5 py-0.5 text-[10px] font-bold leading-none">{branches.length}</span>
          )}
        </TabsTrigger>
      </TabsList>

      <TabsContent value="prs">
        {prsLoading ? (
          <div className="space-y-3">
            {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-16 w-full" />)}
          </div>
        ) : prs.length === 0 ? (
          <EmptyState title={t("pages.repositoryPrs.empty.title")} description={t("pages.repositoryPrs.empty.description")} />
        ) : (
          <PrListCard
            prs={prs}
            actionsInAppbar
            filterNamespace="repo-prs"
            organizationId={activeRepo.organizationId}
            repoName={activeRepo.name}
            owner={activeRepo.owner}
            isSyncing={data.syncPrsMutation.isPending}
            onSync={() => data.syncPrsMutation.mutate(prScope)}
            syncOptions={(["mine_or_review_requested", "all_open"] as PullRequestScope[]).map((scope) => ({
              label: t(prScopeLabelKey(scope)),
              onSelect: () => {
                setRepositoryPrScope(activeRepo.organizationId, activeRepo.name, scope);
                data.syncPrsMutation.mutate(scope);
              },
            }))}
            onMerged={data.handleMerged}
            onNewTask={onNewTask}
          />
        )}
      </TabsContent>

      <TabsContent value="issues">
        {issuesLoading ? (
          <div className="space-y-3">
            {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-16 w-full" />)}
          </div>
        ) : issues.length === 0 ? (
          <EmptyState title={t("pages.repositoryIssues.empty.title")} description={t("pages.repositoryIssues.empty.description")} />
        ) : (
          <IssueTable
            issues={issues}
            actionsInAppbar
            filterNamespace="repo-issues"
            onSelect={onSelectIssue}
            onNavigateToPrs={(_, __, prNumber) => onNavigateToPrs(prNumber)}
            onSync={() => data.syncIssuesMutation.mutate(issueScope)}
            syncOptions={(["my_queue", "all_open", "all"] as IssueScope[]).map((scope) => ({
              label: t(issueScopeLabelKey(scope)),
              onSelect: () => {
                setRepositoryIssueScope(activeRepo.organizationId, activeRepo.name, scope);
                data.syncIssuesMutation.mutate(scope);
              },
            }))}
            isSyncing={data.syncIssuesMutation.isPending}
            onOpenUrl={data.handleOpenUrl}
            onDelete={async (issue) => {
              data.removeIssueFromCaches(issue);
              await data.deleteIssueMutation.mutateAsync(issue);
            }}
            onAssignToMe={(issue) => data.assignToMeMutation.mutateAsync(issue).then(() => undefined)}
          />
        )}
      </TabsContent>

      <TabsContent value="branches">
        <RepoBranchesTab
          branches={branches}
          actionsInAppbar
          loading={branchesLoading}
          syncing={data.syncBranchesMutation.isPending}
          deleting={data.deleteBranchMutation.isPending}
          owner={activeRepo.owner}
          repoName={activeRepo.name}
          onSync={() => data.syncBranchesMutation.mutate()}
          onDelete={onDeleteBranch}
          onOpenUrl={data.handleOpenUrl}
        />
      </TabsContent>
    </Tabs>
  );
}
