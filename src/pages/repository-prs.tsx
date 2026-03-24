import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { GitPullRequest } from "lucide-react";

import { Button } from "../components/ui/button";
import { Card, CardContent } from "../components/ui/card";
import { EmptyState } from "../components/ui/empty-state";
import { Skeleton } from "../components/ui/skeleton";
import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { PrItem } from "../components/repos/pr-item";
import { PrDetailSheet } from "../components/repos/pr-detail-sheet";
import { useI18n } from "../i18n/i18n";
import { useDateLabel } from "../hooks/use-date-label";
import { useNavigationStore } from "../stores/navigation-store";
import type { PullRequestDto } from "../types/organization";

export function RepositoryPRsPage() {
  const { t, locale } = useI18n();
  const dateLabel = useDateLabel(locale);
  const { activeRepo, goBack } = useNavigationStore();
  const [prs, setPrs] = useState<PullRequestDto[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [selectedPr, setSelectedPr] = useState<PullRequestDto | null>(null);
  const [sheetOpen, setSheetOpen] = useState(false);

  useEffect(() => {
    if (!activeRepo) return;

    let isMounted = true;
    setIsLoading(true);

    invoke<PullRequestDto[]>("list_repo_pull_requests", {
      organizationId: activeRepo.organizationId,
      repoName: activeRepo.name,
    })
      .then((data) => {
        if (isMounted) setPrs(data);
      })
      .finally(() => {
        if (isMounted) setIsLoading(false);
      });

    return () => {
      isMounted = false;
    };
  }, [activeRepo]);

  const handleOpenUrl = async (url: string) => {
    try {
      await openUrl(url);
    } catch {
      window.open(url, "_blank");
    }
  };

  const handleViewDetail = (pr: PullRequestDto) => {
    setSelectedPr(pr);
    setSheetOpen(true);
  };

  const handleMerged = (prId: string) => {
    setPrs((prev) => prev.filter((p) => p.id !== prId));
  };

  if (!activeRepo) return null;

  return (
    <PageLayout>
      <PageHeader>
        <div>
          <PageHeaderTitle>
            {activeRepo.owner}/{activeRepo.name}
          </PageHeaderTitle>
          <PageHeaderMeta>
            <span>{t("pages.repositoryPrs.title")}</span>
            <span className="mx-2 text-zinc-300 dark:text-zinc-700">•</span>
            <span>{dateLabel}</span>
          </PageHeaderMeta>
        </div>
        <PageHeaderActions>
          <Button variant="outline" onClick={goBack}>
            {t("common.back")}
          </Button>
        </PageHeaderActions>
      </PageHeader>

      <div className="flex flex-col gap-6">
        {isLoading ? (
          <div className="space-y-3">
            <Skeleton className="h-24 w-full" />
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
          </div>
        ) : prs.length === 0 ? (
          <EmptyState
            title={t("pages.repositoryPrs.empty.title")}
            description={t("pages.repositoryPrs.empty.description")}
          />
        ) : (
          <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
            <div className="flex flex-row items-center px-6 py-6 pb-6">
              <div className="flex flex-row items-center gap-4">
                <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
                  <GitPullRequest size={22} strokeWidth={2} />
                </div>
                <div className="flex flex-col gap-1">
                  <span className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">
                    {t("pages.repositoryPrs.title")}
                  </span>
                   <span className="text-[13px] font-medium text-zinc-500/80 leading-none">
                     {prs.length === 1
                       ? t("pages.repositoryPrs.openCount").replace("{count}", String(prs.length))
                       : t("pages.repositoryPrs.openCountPlural").replace("{count}", String(prs.length))}
                   </span>
                </div>
              </div>
            </div>
            <CardContent className="">
              {prs.map((pr) => (
                <PrItem
                  key={pr.id}
                  pr={pr}
                  onOpen={handleOpenUrl}
                  onViewDetail={handleViewDetail}
                />
              ))}
            </CardContent>
          </Card>
        )}
      </div>

      <PrDetailSheet
        pr={selectedPr}
        open={sheetOpen}
        organizationId={activeRepo.organizationId}
        repoName={activeRepo.name}
        onOpenChange={setSheetOpen}
        onOpenUrl={handleOpenUrl}
        onMerged={handleMerged}
      />
    </PageLayout>
  );
}
