import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import {
  ArrowRight,
  CheckCircle2,
  Clock,
  ExternalLink,
  GitMerge,
  GitPullRequest,
  GitPullRequestDraft,
  MessageSquare,
  Users,
  XCircle,
} from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { openUrl } from "@tauri-apps/plugin-opener";
import { toast } from "sonner";

import { useI18n } from "../i18n/i18n";
import { cn } from "../lib/utils";
import { Button } from "../components/ui/button";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "../components/ui/tabs";
import { AppbarActions } from "../components/layout/appbar-actions";
import { PageLayout } from "../components/layout/page-layout";
import { PrDiffView } from "../components/repos/pr-diff-view";
import { PrChecksView } from "../components/repos/pr-checks-view";
import { PrReviewSheet } from "../components/repos/pr-review-sheet";
import { useNavigationStore } from "../stores/navigation-store";
import { queryKeys } from "../lib/query-keys";
import { cache } from "../config/cache";
import type { CiCheckDto, PrFileDto, PullRequestDto } from "../types/organization";

function prState(pr: PullRequestDto): { labelKey: string; icon: typeof GitPullRequest; cls: string } {
  if (pr.merged_at !== null) return { labelKey: "prs.filter.merged", icon: GitMerge, cls: "bg-purple-500/10 text-purple-500" };
  if (pr.is_draft) return { labelKey: "components.prItem.draft", icon: GitPullRequestDraft, cls: "bg-zinc-500/10 text-zinc-500" };
  return { labelKey: "prs.filter.open", icon: GitPullRequest, cls: "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400" };
}

function CiBadge({ status }: { status: string | null }) {
  if (!status) return null;
  const map = {
    success: { icon: CheckCircle2, cls: "text-emerald-500" },
    failure: { icon: XCircle, cls: "text-red-500" },
    pending: { icon: Clock, cls: "text-amber-500" },
  } as const;
  const meta = map[status as keyof typeof map] ?? { icon: Clock, cls: "text-zinc-400" };
  const Icon = meta.icon;
  return (
    <span className={cn("inline-flex items-center gap-1", meta.cls)}>
      <Icon className="h-3.5 w-3.5" />
      {status}
    </span>
  );
}

function PrReviewHeader({ pr }: { pr: PullRequestDto }) {
  const { t } = useI18n();
  const state = prState(pr);
  const StateIcon = state.icon;

  return (
    <div className="min-w-0 border-b border-zinc-200 pb-3 dark:border-zinc-800">
      <div className="flex items-center gap-2">
        <span className={cn("inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[11px] font-semibold", state.cls)}>
          <StateIcon className="h-3.5 w-3.5" />
          {t(state.labelKey)}
        </span>
        <h1 className="truncate text-[15px] font-semibold text-zinc-900 dark:text-zinc-100">{pr.title}</h1>
        <span className="shrink-0 text-[13px] tabular-nums text-zinc-400">#{pr.number}</span>
      </div>
      <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[12px] text-zinc-500 dark:text-zinc-400">
        <span className="inline-flex items-center gap-1.5">
          <span className="max-w-[180px] truncate rounded bg-zinc-100 px-1.5 py-0.5 font-mono text-[11px] dark:bg-zinc-800" title={pr.head}>
            {pr.head}
          </span>
          <ArrowRight className="h-3 w-3 shrink-0" />
          <span className="rounded bg-zinc-100 px-1.5 py-0.5 font-mono text-[11px] dark:bg-zinc-800">{pr.base}</span>
        </span>
        {pr.author && (
          <span className="inline-flex items-center gap-1.5">
            <span className="flex h-5 w-5 items-center justify-center rounded-full bg-zinc-200 text-[9px] font-semibold text-zinc-600 dark:bg-zinc-700 dark:text-zinc-300">
              {pr.author.slice(0, 2).toUpperCase()}
            </span>
            {pr.author}
          </span>
        )}
        <CiBadge status={pr.ci_status} />
        {pr.reviewers.length > 0 && (
          <span className="inline-flex items-center gap-1">
            <Users className="h-3.5 w-3.5" />
            {pr.reviewers.length}
          </span>
        )}
        {pr.labels.slice(0, 3).map((label) => (
          <span key={label} className="inline-flex max-w-[140px] items-center gap-1 truncate">
            <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-zinc-400 dark:bg-zinc-500" />
            {label}
          </span>
        ))}
      </div>
    </div>
  );
}

export function PrReviewPage() {
  const { t } = useI18n();
  const { activePr, activeRepo } = useNavigationStore();
  const [reviewOpen, setReviewOpen] = useState(false);

  const { data: files = [], isLoading: filesLoading, isError: filesError, error: filesErr } = useQuery({
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
    staleTime: cache.staleTime.default,
    gcTime: cache.gcTime.long,
  });

  const { data: checks = [], isLoading: checksLoading, isError: checksError, error: checksErr } = useQuery({
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
    staleTime: cache.staleTime.default,
    gcTime: cache.gcTime.long,
  });

  useEffect(() => {
    if (filesError) toast.error(String(filesErr));
  }, [filesError, filesErr]);

  useEffect(() => {
    if (checksError) toast.error(String(checksErr));
  }, [checksError, checksErr]);

  if (!activePr || !activeRepo) return null;

  const filesTabLabel = `${t("components.prReview.tabFiles")}${files.length > 0 ? ` (${files.length})` : ""}`;
  const checksTabLabel = `${t("components.prReview.tabChecks")}${checks.length > 0 ? ` (${checks.length})` : ""}`;

  return (
    <>
      <AppbarActions>
        <Button variant="outline" className="inline-flex items-center gap-2" onClick={() => openUrl(activePr.url)}>
          <ExternalLink className="h-4 w-4 shrink-0" />
          {t("components.prReview.viewPrButton")}
        </Button>
        <Button className="inline-flex items-center gap-2" onClick={() => setReviewOpen(true)}>
          <MessageSquare className="h-4 w-4 shrink-0" />
          {t("components.prReview.finishButton")}
        </Button>
      </AppbarActions>

      <PageLayout scroll={false}>
        <PrReviewHeader pr={activePr} />

        <div className="flex flex-col">
          <Tabs defaultValue="checks" className="flex w-full flex-col">
            <div className="shrink-0 mb-4">
              <TabsList variant="line">
                <TabsTrigger value="files">{filesTabLabel}</TabsTrigger>
                <TabsTrigger value="checks">{checksTabLabel}</TabsTrigger>
              </TabsList>
            </div>

            <TabsContent value="files">
              <PrDiffView files={files} loading={filesLoading} prNumber={activePr.number} />
            </TabsContent>

            <TabsContent value="checks">
              <PrChecksView
                checks={checks}
                loading={checksLoading}
                orgId={activeRepo.organizationId}
                repoName={activeRepo.name}
              />
            </TabsContent>
          </Tabs>
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
