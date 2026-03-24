import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { MessageSquare, ExternalLink } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { openUrl } from "@tauri-apps/plugin-opener";

import { useI18n } from "../i18n/i18n";
import { Button } from "../components/ui/button";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "../components/ui/tabs";
import {
  PageHeader,
  PageHeaderActions,
  PageHeaderTitle,
  PageHeaderMeta,
} from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { PrDiffView } from "../components/repos/pr-diff-view";
import { PrChecksView } from "../components/repos/pr-checks-view";
import { PrReviewSheet } from "../components/repos/pr-review-sheet";
import { useNavigationStore } from "../stores/navigation-store";
import { queryKeys } from "../lib/query-keys";
import type { CiCheckDto, PrFileDto } from "../types/organization";

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

  const { data: checks = [], isLoading: checksLoading } = useQuery({
    queryKey: queryKeys.prChecks(
      activeRepo?.organizationId ?? "",
      activeRepo?.name ?? "",
      activePr?.head_sha ?? "",
    ),
    queryFn: () =>
      invoke<CiCheckDto[]>("get_pr_checks", {
        organizationId: activeRepo!.organizationId,
        repoName: activeRepo!.name,
        headSha: activePr!.head_sha,
      }),
    enabled: !!activePr && !!activeRepo && !!activePr.head_sha,
  });

  if (!activePr || !activeRepo) return null;

  const filesTabLabel = `${t("components.prReview.tabFiles")}${files.length > 0 ? ` (${files.length})` : ""}`;
  const checksTabLabel = `${t("components.prReview.tabChecks")}${checks.length > 0 ? ` (${checks.length})` : ""}`;

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
              onClick={() => openUrl(activePr.url)}
            >
              <ExternalLink className="h-3.5 w-3.5 shrink-0" />
              {t("components.prReview.viewPrButton")}
            </Button>
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

        <Tabs defaultValue="files" className="flex-1 overflow-hidden">
          <div className="px-4 pt-2">
            <TabsList variant="line">
              <TabsTrigger value="files">{filesTabLabel}</TabsTrigger>
              <TabsTrigger value="checks">{checksTabLabel}</TabsTrigger>
            </TabsList>
          </div>

          <TabsContent value="files" className="overflow-y-auto h-full">
            <PrDiffView files={files} loading={filesLoading} />
          </TabsContent>

          <TabsContent value="checks" className="overflow-y-auto h-full">
            <PrChecksView
              checks={checks}
              loading={checksLoading}
              orgId={activeRepo.organizationId}
              repoName={activeRepo.name}
            />
          </TabsContent>
        </Tabs>
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
