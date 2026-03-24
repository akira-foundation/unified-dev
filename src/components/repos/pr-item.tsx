import { ArrowRight, CheckCircle2, Clock, ExternalLink, FileCode, XCircle } from "lucide-react";

import { useI18n } from "../../i18n/i18n";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "../ui/tooltip";
import type { PullRequestDto } from "../../types/organization";

export function formatRelativeDate(dateStr: string): string {
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

function CiStatusIcon({ status }: { status: string | null }) {
  if (status === "success")
    return <CheckCircle2 className="h-3.5 w-3.5 text-green-500 shrink-0" />;
  if (status === "failure")
    return <XCircle className="h-3.5 w-3.5 text-red-500 shrink-0" />;
  if (status === "pending")
    return <Clock className="h-3.5 w-3.5 text-amber-500 shrink-0" />;
  return null;
}

export function PrItem({
  pr,
  onOpen,
  onViewDetail,
  onReview,
}: {
  pr: PullRequestDto;
  onOpen: (url: string) => void;
  onViewDetail: (pr: PullRequestDto) => void;
  onReview: (pr: PullRequestDto) => void;
}) {
  const { t } = useI18n();
  return (
    <div className="flex items-start justify-between px-4 py-3 transition-colors hover:bg-zinc-50/50 dark:hover:bg-zinc-900/20 border-b border-zinc-100 dark:border-zinc-800/60 last:border-b-0">
      <div className="flex items-start gap-3 min-w-0 flex-1">
        <div className="mt-1.5 shrink-0">
          {pr.is_draft ? (
            <div className="h-2.5 w-2.5 rounded-full bg-zinc-400 dark:bg-zinc-500" />
          ) : (
            <div className="h-2.5 w-2.5 rounded-full bg-green-500" />
          )}
        </div>
        <div className="flex flex-col gap-1 min-w-0">
          <div className="flex items-center gap-1.5">
            <button
              className="text-sm font-semibold text-gray-900 dark:text-white leading-snug text-left hover:text-purple-600 dark:hover:text-purple-400 transition-colors cursor-pointer"
              onClick={() => onViewDetail(pr)}
            >
              {pr.title}
            </button>
            <CiStatusIcon status={pr.ci_status} />
          </div>
          <div className="flex items-center gap-1.5 flex-wrap text-xs text-gray-500 dark:text-gray-400">
            <span className="font-medium">#{pr.number}</span>
            <span className="text-zinc-300 dark:text-zinc-600">·</span>
            <span className="font-mono max-w-[140px] truncate" title={pr.head}>
              {pr.head}
            </span>
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
      <div className="flex items-center gap-1 shrink-0 ml-4">
        {pr.is_draft && (
          <Badge variant="secondary" className="text-[10px] uppercase">
            {t("components.prItem.draft")}
          </Badge>
        )}
        {pr.labels.slice(0, 2).map((label) => (
          <Badge key={label} variant="outline" className="text-[10px]">
            {label}
          </Badge>
        ))}
        <Tooltip>
          <TooltipTrigger asChild>
            <Button
              variant="ghost"
              size="icon"
              className="text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200 cursor-pointer"
              onClick={() => onReview(pr)}
            >
              <FileCode className="h-4 w-4" />
            </Button>
          </TooltipTrigger>
          <TooltipContent>{t("components.prDetail.review")}</TooltipContent>
        </Tooltip>
        <Tooltip>
          <TooltipTrigger asChild>
            <Button
              variant="ghost"
              size="icon"
              className="text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200 cursor-pointer"
              onClick={() => onOpen(pr.url)}
            >
              <ExternalLink className="h-4 w-4" />
            </Button>
          </TooltipTrigger>
          <TooltipContent>{t("components.prReview.viewPrButton")}</TooltipContent>
        </Tooltip>
      </div>
    </div>
  );
}
