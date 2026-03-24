import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { MessageSquare } from "lucide-react";
import { useQuery } from "@tanstack/react-query";

import { useI18n } from "../i18n/i18n";
import { Button } from "../components/ui/button";
import {
  PageHeader,
  PageHeaderActions,
  PageHeaderTitle,
  PageHeaderMeta,
} from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { PrDiffView } from "../components/repos/pr-diff-view";
import { PrReviewSheet } from "../components/repos/pr-review-sheet";
import { useNavigationStore } from "../stores/navigation-store";
import { queryKeys } from "../lib/query-keys";
import type { PrFileDto } from "../types/organization";

export function PrReviewPage() {
  const { t } = useI18n();
  const { activePr, activeRepo } = useNavigationStore();
  const [reviewOpen, setReviewOpen] = useState(false);

  const { data: files = [], isLoading: filesLoading } = useQuery({
    queryKey: queryKeys.prFiles(
      activeRepo?.organizationId ?? "",
      activeRepo?.name ?? "",
      activePr?.number ?? 0,
    ),
    queryFn: () =>
      invoke<PrFileDto[]>("get_pr_files", {
        organizationId: activeRepo!.organizationId,
        repoName: activeRepo!.name,
        prNumber: activePr!.number,
      }),
    enabled: !!activePr && !!activeRepo,
  });

  if (!activePr || !activeRepo) return null;

  return (
    <>
      <PageLayout className="p-0 h-full space-y-0">
        <PageHeader className="px-6 py-3 border-b border-zinc-100 dark:border-zinc-800 gap-3">
          <div>
            <PageHeaderTitle className="text-xl">{t("components.prDiff.title")}</PageHeaderTitle>
            <PageHeaderMeta>
              <span className="font-mono">{activePr.title}</span>
              <span className="mx-2 text-zinc-300 dark:text-zinc-700">·</span>
              <span className="text-zinc-400">#{activePr.number}</span>
            </PageHeaderMeta>
          </div>
          <PageHeaderActions>
            <Button
              variant="outline"
              size="sm"
              className="inline-flex items-center gap-1.5"
              onClick={() => setReviewOpen(true)}
            >
              <MessageSquare className="h-3.5 w-3.5 shrink-0" />
              {t("components.prReview.finishButton")}
            </Button>
          </PageHeaderActions>
        </PageHeader>

        <div className="flex-1 overflow-y-auto">
          <PrDiffView files={files} loading={filesLoading} />
        </div>
      </PageLayout>

      <PrReviewSheet
        pr={activePr}
        repo={activeRepo}
        open={reviewOpen}
        onOpenChange={setReviewOpen}
      />
    </>
  );
}
