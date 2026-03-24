import { Check, ChevronLeft, MessageSquare, X } from "lucide-react";

import { useI18n } from "../../i18n/i18n";
import { Button } from "../ui/button";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "../ui/sheet";
import type { PrReviewEvent, PullRequestDto } from "../../types/organization";

type ReviewMode = "comment" | "approve" | "request_changes" | null;

export function PrReviewSheet({
  pr,
  open,
  reviewMode,
  reviewBody,
  reviewSubmitting,
  reviewSuccess,
  onOpenChange,
  onReviewModeChange,
  onReviewBodyChange,
  onSubmit,
}: {
  pr: PullRequestDto;
  open: boolean;
  reviewMode: ReviewMode;
  reviewBody: string;
  reviewSubmitting: boolean;
  reviewSuccess: string | null;
  onOpenChange: (open: boolean) => void;
  onReviewModeChange: (mode: ReviewMode) => void;
  onReviewBodyChange: (body: string) => void;
  onSubmit: () => void;
}) {
  const { t } = useI18n();

  const reviewOptions = [
    {
      value: "comment" as const,
      label: t("components.prReview.commentOptionLabel"),
      description: t("components.prReview.commentOptionDesc"),
      icon: <MessageSquare className="h-4 w-4 mt-0.5 shrink-0 text-zinc-400" />,
    },
    {
      value: "approve" as const,
      label: t("components.prReview.approveOptionLabel"),
      description: t("components.prReview.approveOptionDesc"),
      icon: <Check className="h-4 w-4 mt-0.5 shrink-0 text-emerald-500" />,
    },
    {
      value: "request_changes" as const,
      label: t("components.prReview.requestChangesOptionLabel"),
      description: t("components.prReview.requestChangesOptionDesc"),
      icon: <X className="h-4 w-4 mt-0.5 shrink-0 text-red-400" />,
    },
  ];
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side="right"
        className="w-full sm:max-w-lg flex flex-col p-0 overflow-hidden"
      >
        <SheetHeader className="px-5 pt-5 pb-4 shrink-0">
          <div className="flex items-center gap-3 pr-6">
            <button
              onClick={() => onOpenChange(false)}
              className="text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 transition-colors"
            >
              <ChevronLeft className="h-4 w-4" />
            </button>
            <div>
              <SheetTitle className="text-sm">{t("components.prReview.title")}</SheetTitle>
              <SheetDescription className="text-xs">
                {pr.title}{" "}
                <span className="text-zinc-400">#{pr.number}</span>
              </SheetDescription>
            </div>
          </div>
        </SheetHeader>

        {reviewSuccess ? (
          <div className="flex-1 flex items-start px-5 py-4">
            <div className="flex items-center gap-2 rounded-lg bg-emerald-50 dark:bg-emerald-500/10 border border-emerald-200 dark:border-emerald-500/20 px-3 py-2 text-sm text-emerald-700 dark:text-emerald-400 w-full">
              <Check className="h-4 w-4 shrink-0" />
              {reviewSuccess}
            </div>
          </div>
        ) : (
          <>
            <div className="flex-1 overflow-y-auto flex flex-col">
              <textarea
                value={reviewBody}
                onChange={(e) => onReviewBodyChange(e.target.value)}
                placeholder={t("components.prReview.placeholder")}
                className="flex-1 min-h-[160px] w-full bg-white dark:bg-zinc-900 px-5 py-4 text-sm text-zinc-900 dark:text-white placeholder:text-zinc-400 dark:placeholder:text-zinc-600 resize-none focus:outline-none"
              />

              <div className="divide-y divide-zinc-100 dark:divide-zinc-800">
                {reviewOptions.map(({ value, label, description, icon }) => (
                  <label
                    key={value}
                    className="flex items-start gap-3 px-5 py-3 cursor-pointer hover:bg-zinc-50 dark:hover:bg-zinc-800/40 transition-colors"
                  >
                    <input
                      type="radio"
                      name="review-type"
                      value={value}
                      checked={reviewMode === value}
                      onChange={() => onReviewModeChange(value)}
                      className="mt-1 accent-purple-600"
                    />
                    {icon}
                    <div className="flex flex-col gap-0.5 min-w-0">
                      <span className="text-sm font-medium text-zinc-900 dark:text-white leading-none">
                        {label}
                      </span>
                      <span className="text-xs text-zinc-500 dark:text-zinc-400 leading-snug">
                        {description}
                      </span>
                    </div>
                  </label>
                ))}
              </div>
            </div>

            <div className="px-5 py-3 border-t border-zinc-100 dark:border-zinc-800 shrink-0">
              <Button
                className="w-full"
                disabled={reviewSubmitting || reviewMode === null}
                onClick={onSubmit}
              >
                {reviewSubmitting ? t("components.prReview.submitting") : t("components.prReview.submit")}
              </Button>
            </div>
          </>
        )}
      </SheetContent>
    </Sheet>
  );
}

export type { ReviewMode };
export type { PrReviewEvent };
