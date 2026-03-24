import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { Check, MessageSquare, X } from "lucide-react";

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
import type { ActiveRepo } from "../../stores/navigation-store";

type ReviewMode = "comment" | "approve" | "request_changes";

export function PrReviewSheet({
  pr,
  repo,
  open,
  onOpenChange,
}: {
  pr: PullRequestDto;
  repo: ActiveRepo;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const { t } = useI18n();
  const [reviewMode, setReviewMode] = useState<ReviewMode>("comment");
  const [reviewBody, setReviewBody] = useState("");
  const [reviewSubmitting, setReviewSubmitting] = useState(false);
  const [reviewSuccess, setReviewSuccess] = useState<string | null>(null);

  const handleOpenChange = (next: boolean) => {
    if (!next) {
      setReviewBody("");
      setReviewMode("comment");
      setReviewSuccess(null);
    }
    onOpenChange(next);
  };

  const handleSubmit = async () => {
    setReviewSubmitting(true);
    try {
      await invoke("submit_pr_review", {
        organizationId: repo.organizationId,
        repoName: repo.name,
        prNumber: pr.number,
        event: reviewMode as PrReviewEvent,
        body: reviewBody.trim() || null,
      });
      const msg =
        reviewMode === "approve"
          ? t("components.prReview.approved")
          : reviewMode === "request_changes"
            ? t("components.prReview.changesRequested")
            : t("components.prReview.commentSubmitted");
      setReviewSuccess(msg);
      setReviewBody("");
      setReviewMode("comment");
    } catch (err) {
      const raw = String(err);
      const errorsMatch = raw.match(/"errors"\s*:\s*\["([^"]+)"/);
      const messageMatch = raw.match(/"message"\s*:\s*"([^"]+)"/);
      const msg = errorsMatch ? errorsMatch[1] : messageMatch ? messageMatch[1] : raw;
      toast.error(msg);
    } finally {
      setReviewSubmitting(false);
    }
  };

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
    <Sheet open={open} onOpenChange={handleOpenChange}>
      <SheetContent side="right" className="flex flex-col p-0 overflow-hidden w-full sm:max-w-md">
        <SheetHeader className="px-5 pt-5 pb-4 border-b border-zinc-100 dark:border-zinc-800 shrink-0">
          <SheetTitle className="text-base text-left">
            {t("components.prReview.title")}
          </SheetTitle>
          <SheetDescription className="text-xs flex items-center gap-1 flex-wrap">
            <span className="font-mono truncate max-w-[240px]">{pr.title}</span>
            <span>·</span>
            <span>#{pr.number}</span>
          </SheetDescription>
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
                onChange={(e) => setReviewBody(e.target.value)}
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
                      onChange={() => setReviewMode(value)}
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
                disabled={reviewSubmitting}
                onClick={handleSubmit}
              >
                {reviewSubmitting
                  ? t("components.prReview.submitting")
                  : t("components.prReview.submit")}
              </Button>
            </div>
          </>
        )}
      </SheetContent>
    </Sheet>
  );
}
