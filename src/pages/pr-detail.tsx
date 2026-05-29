import { useEffect, useState } from "react";

import { cn } from "@/lib/utils";
import { useNavigationStore } from "@/stores/navigation-store";
import { useI18n } from "@/i18n/i18n";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { IssueDescription } from "@/components/issues/issue-description";
import { usePrBodyEditor } from "@/hooks/usePrBodyEditor";
import { CommentThread } from "@/components/shared/comment-thread";
import { PrProperties } from "@/components/repos/pr-properties";
import { PrDetailActions } from "@/components/repos/pr-detail-actions";
import { PrMergePanel } from "@/components/repos/pr-merge-panel";
import { PrDiffView } from "@/components/repos/pr-diff-view";
import { PrChecksView } from "@/components/repos/pr-checks-view";
import { PrReviewSheet } from "@/components/repos/pr-review-sheet";
import { usePrReviewData } from "@/hooks/usePrReviewData";

function TabCount({ children }: { children: number }) {
  return (
    <span className="ml-1.5 rounded-full bg-zinc-200 px-1.5 py-0.5 text-[10px] font-bold leading-none dark:bg-zinc-700">
      {children}
    </span>
  );
}

export function PrDetailPage() {
  const { t } = useI18n();
  const pr = useNavigationStore((s) => s.activePr);
  const repo = useNavigationStore((s) => s.activeRepo);
  const targetCheckName = useNavigationStore((s) => s.targetCheckName);
  const navigateTo = useNavigationStore((s) => s.navigateTo);
  const goBack = useNavigationStore((s) => s.goBack);
  const tab = useNavigationStore((s) => s.prDetailTab);
  const setTab = useNavigationStore((s) => s.setPrDetailTab);

  const { files, filesLoading, checks, checksLoading } = usePrReviewData(repo, pr);
  const prBody = usePrBodyEditor(
    pr && repo
      ? { organizationId: repo.organizationId, repoName: repo.name, prNumber: pr.number, body: pr.body }
      : null,
  );
  const [reviewOpen, setReviewOpen] = useState(false);

  useEffect(() => {
    if (targetCheckName || pr?.ci_status === "failure") setTab("checks");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (!pr || !repo) {
    navigateTo("prs");
    return null;
  }

  const dotCls = pr.merged_at !== null ? "bg-purple-500" : pr.is_draft ? "bg-zinc-400" : "bg-green-500";

  return (
    <div className="flex h-[calc(100vh-4rem)]">
      <PrDetailActions pr={pr} onFinishReview={() => setReviewOpen(true)} />

      <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <div className="shrink-0 px-6 pt-6 md:px-8">
          <div className="flex items-start gap-3">
            <span className={cn("mt-2 h-2.5 w-2.5 shrink-0 rounded-full", dotCls)} />
            <h1 className="text-xl font-bold leading-snug text-zinc-900 dark:text-white">{pr.title}</h1>
          </div>
          <div className="ml-[22px] mt-1 flex flex-wrap items-center gap-1.5 text-xs text-zinc-500">
            <span>{repo.name}</span>
            <span>·</span>
            <span>#{pr.number}</span>
            <span>·</span>
            <span className="font-mono">{pr.head} &rarr; {pr.base}</span>
          </div>
        </div>

        <Tabs value={tab} onValueChange={setTab} className="flex min-h-0 flex-1 flex-col">
          <div className="shrink-0 px-6 pt-3 md:px-8">
            <TabsList>
              <TabsTrigger value="overview">{t("components.prDetail.cardDescription")}</TabsTrigger>
              <TabsTrigger value="files">
                {t("components.prReview.tabFiles")}
                {files.length > 0 && <TabCount>{files.length}</TabCount>}
              </TabsTrigger>
              <TabsTrigger value="checks">
                {t("components.prReview.tabChecks")}
                {checks.length > 0 && <TabCount>{checks.length}</TabCount>}
              </TabsTrigger>
            </TabsList>
          </div>

          <div className="min-h-0 flex-1 overflow-y-auto custom-scrollbar px-6 py-4 md:px-8">
            <TabsContent value="overview">
              <IssueDescription editor={prBody} />
              <CommentThread
                organizationId={repo.organizationId}
                repoName={repo.name}
                number={pr.number}
                heading={t("issues.detail.activity")}
              />
            </TabsContent>

            <TabsContent value="files">
              <PrDiffView files={files} loading={filesLoading} prNumber={pr.number} />
            </TabsContent>

            <TabsContent value="checks">
              <PrChecksView checks={checks} loading={checksLoading} orgId={repo.organizationId} repoName={repo.name} />
            </TabsContent>
          </div>
        </Tabs>
      </div>

      <aside className="flex w-80 shrink-0 flex-col gap-3 overflow-y-auto border-l border-zinc-200 p-4 dark:border-zinc-800">
        <PrProperties pr={pr} organizationId={repo.organizationId} repoName={repo.name} />
        <PrMergePanel
          pr={pr}
          organizationId={repo.organizationId}
          repoName={repo.name}
          owner={repo.owner}
          onMerged={() => goBack()}
        />
      </aside>

      <PrReviewSheet pr={pr} repo={repo} open={reviewOpen} onOpenChange={setReviewOpen} />
    </div>
  );
}
