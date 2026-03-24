import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { ArrowRight, ExternalLink, GitPullRequest, Tag, User, Users } from "lucide-react";

import { Badge } from "../components/ui/badge";
import { Button } from "../components/ui/button";
import { Card, CardContent } from "../components/ui/card";
import { EmptyState } from "../components/ui/empty-state";
import { Skeleton } from "../components/ui/skeleton";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "../components/ui/sheet";
import {
  PageHeader,
  PageHeaderActions,
  PageHeaderMeta,
  PageHeaderTitle,
} from "../components/layout/page-header";
import { PageLayout } from "../components/layout/page-layout";
import { useI18n } from "../i18n/i18n";
import { useDateLabel } from "../hooks/use-date-label";
import { useNavigationStore } from "../stores/navigation-store";
import type { PullRequestDto } from "../types/organization";

function formatRelativeDate(dateStr: string): string {
  const date = new Date(dateStr);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

  if (diffDays === 0) return "today";
  if (diffDays === 1) return "yesterday";
  if (diffDays < 30) return `${diffDays}d ago`;
  if (diffDays < 365) return `${Math.floor(diffDays / 30)}mo ago`;
  return `${Math.floor(diffDays / 365)}y ago`;
}

function PrItem({
  pr,
  onOpen,
  onViewDetail,
}: {
  pr: PullRequestDto;
  onOpen: (url: string) => void;
  onViewDetail: (pr: PullRequestDto) => void;
}) {
  return (
    <div className="flex items-start justify-between px-4 py-3 transition-colors hover:bg-zinc-50/50 dark:hover:bg-zinc-900/20">
      <div className="flex items-start gap-3 min-w-0 flex-1">
        <div className="mt-1.5 shrink-0">
          {pr.is_draft ? (
            <div className="h-2.5 w-2.5 rounded-full bg-zinc-400 dark:bg-zinc-500" />
          ) : (
            <div className="h-2.5 w-2.5 rounded-full bg-green-500" />
          )}
        </div>
        <div className="flex flex-col gap-1 min-w-0">
          <button
            className="text-sm font-semibold text-gray-900 dark:text-white leading-snug text-left hover:text-purple-600 dark:hover:text-purple-400 transition-colors cursor-pointer"
            onClick={() => onViewDetail(pr)}
          >
            {pr.title}
          </button>
          <div className="flex items-center gap-1.5 flex-wrap text-xs text-gray-500 dark:text-gray-400">
            <span className="font-medium">#{pr.number}</span>
            <span className="text-zinc-300 dark:text-zinc-600">·</span>
            <span className="font-mono max-w-[140px] truncate" title={pr.head}>{pr.head}</span>
            <ArrowRight className="h-3 w-3 shrink-0" />
            <span className="font-mono">{pr.base}</span>
            <span className="text-zinc-300 dark:text-zinc-600">·</span>
            <span>{formatRelativeDate(pr.updated_at)}</span>
            {pr.author && (
              <>
                <span className="text-zinc-300 dark:text-zinc-600">·</span>
                <span>{pr.author}</span>
              </>
            )}
          </div>
        </div>
      </div>
      <div className="flex items-center gap-2 shrink-0 ml-4">
        {pr.is_draft && (
          <Badge variant="secondary" className="text-[10px] uppercase">Draft</Badge>
        )}
        {pr.labels.map((label) => (
          <Badge key={label} variant="outline" className="text-[10px]">{label}</Badge>
        ))}
        <Button
          variant="ghost"
          size="icon"
          className="text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200"
          onClick={() => onOpen(pr.url)}
        >
          <ExternalLink className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
}

function PrDetailSheet({
  pr,
  open,
  onOpenChange,
  onOpenUrl,
}: {
  pr: PullRequestDto | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onOpenUrl: (url: string) => void;
}) {
  if (!pr) return null;

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="w-full sm:max-w-lg overflow-y-auto">
        <SheetHeader className="pb-4 border-b border-zinc-100 dark:border-zinc-800">
          <div className="flex items-start gap-3 pr-8">
            <div className="mt-1 shrink-0">
              {pr.is_draft ? (
                <div className="h-2.5 w-2.5 rounded-full bg-zinc-400 dark:bg-zinc-500" />
              ) : (
                <div className="h-2.5 w-2.5 rounded-full bg-green-500" />
              )}
            </div>
            <div className="flex flex-col gap-1 min-w-0">
              <SheetTitle className="text-base leading-snug text-left">
                {pr.title}
              </SheetTitle>
              <SheetDescription className="text-xs">
                #{pr.number} · {pr.head} <ArrowRight className="inline h-3 w-3" /> {pr.base} · {formatRelativeDate(pr.updated_at)}
              </SheetDescription>
            </div>
          </div>
        </SheetHeader>

        <div className="flex flex-col gap-5 p-4">
          {/* Badges row */}
          <div className="flex flex-wrap gap-2">
            {pr.is_draft && (
              <Badge variant="secondary" className="text-[10px] uppercase">Draft</Badge>
            )}
            {pr.labels.map((label) => (
              <Badge key={label} variant="outline" className="text-[10px] flex items-center gap-1">
                <Tag className="h-2.5 w-2.5" />
                {label}
              </Badge>
            ))}
          </div>

          {/* Author */}
          {pr.author && (
            <div className="flex flex-col gap-1">
              <span className="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wide flex items-center gap-1.5">
                <User className="h-3 w-3" /> Author
              </span>
              <span className="text-sm text-zinc-900 dark:text-white">{pr.author}</span>
            </div>
          )}

          {/* Reviewers */}
          {pr.reviewers.length > 0 && (
            <div className="flex flex-col gap-1.5">
              <span className="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wide flex items-center gap-1.5">
                <Users className="h-3 w-3" /> Reviewers
              </span>
              <div className="flex flex-wrap gap-1.5">
                {pr.reviewers.map((reviewer) => (
                  <Badge key={reviewer} variant="secondary" className="text-xs font-normal">
                    {reviewer}
                  </Badge>
                ))}
              </div>
            </div>
          )}

          {/* Body / Description */}
          {pr.body && pr.body.trim() !== "" ? (
            <div className="flex flex-col gap-1.5">
              <span className="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wide">
                Description
              </span>
              <div className="rounded-lg bg-zinc-50 dark:bg-zinc-900 border border-zinc-100 dark:border-zinc-800 p-3">
                <p className="text-sm text-zinc-700 dark:text-zinc-300 whitespace-pre-wrap leading-relaxed">
                  {pr.body}
                </p>
              </div>
            </div>
          ) : (
            <div className="flex flex-col gap-1.5">
              <span className="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wide">
                Description
              </span>
              <p className="text-sm text-zinc-400 dark:text-zinc-600 italic">No description provided.</p>
            </div>
          )}
        </div>

        <div className="mt-auto p-4 border-t border-zinc-100 dark:border-zinc-800">
          <Button
            variant="outline"
            className="w-full"
            onClick={() => onOpenUrl(pr.url)}
          >
            <ExternalLink className="h-4 w-4 mr-2" />
            Open in browser
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}

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
            <div className="flex flex-row items-center justify-between px-6 py-6 pb-6">
              <div className="flex flex-row items-center gap-4">
                <div className="h-11 w-11 flex items-center justify-center rounded-xl bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
                  <GitPullRequest size={22} strokeWidth={2} />
                </div>
                <div className="flex flex-col gap-1">
                  <span className="text-xl font-bold tracking-tight text-zinc-900 dark:text-white/95 leading-none">
                    {t("pages.repositoryPrs.title")}
                  </span>
                  <span className="text-[13px] font-medium text-zinc-500/80 leading-none">
                    {prs.length} open pull {prs.length === 1 ? "request" : "requests"}
                  </span>
                </div>
              </div>
            </div>
            <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
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
        onOpenChange={setSheetOpen}
        onOpenUrl={handleOpenUrl}
      />
    </PageLayout>
  );
}
