import { useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useI18n } from "../../i18n/i18n";
import {
  ArrowRight,
  Check,
  ChevronDown,
  ExternalLink,
  FileText,
  GitBranch,
  GitMerge,
  Loader2,
  Maximize2,
  MessageSquare,
  Minimize2,
} from "lucide-react";
import { useNavigationStore } from "../../stores/navigation-store";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "../ui/collapsible";
import { Badge } from "../ui/badge";
import { Button } from "../ui/button";
import { Card, CardContent, CardTitle } from "../ui/card";
import { Skeleton } from "../ui/skeleton";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "../ui/sheet";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "../ui/dropdown-menu";
import { MarkdownBody } from "./markdown-body";
import { PrCommentItem } from "./pr-comment-item";
import { formatRelativeDate } from "./pr-item";
import { queryKeys } from "../../lib/query-keys";
import type {
  PrCommentDto,
  PrMergeStrategy,
  PullRequestDto,
} from "../../types/organization";

export function PrDetailSheet({
  pr,
  open,
  organizationId,
  repoName,
  owner,
  onOpenChange,
  onOpenUrl,
  onMerged,
}: {
  pr: PullRequestDto | null;
  open: boolean;
  organizationId: string;
  repoName: string;
  owner: string;
  onOpenChange: (open: boolean) => void;
  onOpenUrl: (url: string) => void;
  onMerged: () => void;
}) {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const { navigateTo, setActivePr, setActiveRepo } = useNavigationStore();
  const strategyLabels: Record<PrMergeStrategy, string> = {
    merge: t("components.prDetail.mergeCommit"),
    squash: t("components.prDetail.mergeSquash"),
    rebase: t("components.prDetail.mergeRebase"),
  };
  const [commentBody, setCommentBody] = useState("");
  const [mergeStrategy, setMergeStrategy] = useState<PrMergeStrategy>("merge");
  const [mergeError, setMergeError] = useState<string | null>(null);
  const [isMerging, setIsMerging] = useState(false);
  const [fullscreen, setFullscreen] = useState(false);
  const commentRef = useRef<HTMLTextAreaElement>(null);

  const { data: comments = [], isLoading: commentsLoading } = useQuery({
    queryKey: queryKeys.prComments(organizationId, repoName, pr?.number ?? 0),
    queryFn: () =>
      invoke<PrCommentDto[]>("get_pr_comments", {
        organizationId,
        repoName,
        prNumber: pr!.number,
      }),
    enabled: open && !!pr,
  });

  const postComment = useMutation({
    mutationFn: () =>
      invoke<PrCommentDto>("post_pr_comment", {
        organizationId,
        repoName,
        prNumber: pr!.number,
        body: commentBody.trim(),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: queryKeys.prComments(organizationId, repoName, pr!.number),
      });
      setCommentBody("");
    },
  });

  const handlePostComment = async () => {
    if (!commentBody.trim()) return;
    await postComment.mutateAsync();
  };

  const handleMerge = async () => {
    if (!pr || isMerging) return;
    setMergeError(null);
    setIsMerging(true);
    const toastId = toast.loading(`Merging #${pr.number}…`);
    try {
      await invoke("merge_pr", {
        organizationId,
        repoName,
        prNumber: pr.number,
        strategy: mergeStrategy,
      });
      toast.success(`PR #${pr.number} merged successfully`, { id: toastId });
      onMerged();
      onOpenChange(false);
    } catch (err) {
      toast.dismiss(toastId);
      setMergeError(String(err));
    } finally {
      setIsMerging(false);
    }
  };

  if (!pr) return null;

  return (
    <Sheet open={open} onOpenChange={(o) => { if (!o) { setMergeError(null); setFullscreen(false); } onOpenChange(o); }}>
      <SheetContent
        side="right"
        className={`flex flex-col p-0 overflow-hidden transition-all duration-200 ${fullscreen ? "w-full sm:max-w-full" : "w-full sm:max-w-lg"}`}
      >
        {/* Header */}
        <SheetHeader className="px-5 pt-5 pb-4 border-b border-zinc-100 dark:border-zinc-800 shrink-0">
          <div className="flex items-start gap-3 pr-6">
            <div className="mt-1 shrink-0">
              {pr.is_draft ? (
                <div className="h-2.5 w-2.5 rounded-full bg-zinc-400 dark:bg-zinc-500" />
              ) : (
                <div className="h-2.5 w-2.5 rounded-full bg-green-500" />
              )}
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex items-center justify-between gap-2">
                <SheetTitle className="text-base leading-snug text-left">
                  {pr.title}
                </SheetTitle>
                <div className="flex items-center gap-1 shrink-0">
                  <Button
                    variant="outline"
                    size="sm"
                    className="h-7 px-2.5 text-xs text-zinc-600 dark:text-zinc-300 cursor-pointer inline-flex items-center gap-1.5"
                    onClick={() => { setActiveRepo({ name: repoName, owner, organizationId }); setActivePr(pr); navigateTo("pr-review"); }}
                  >
                    <MessageSquare className="h-3.5 w-3.5 shrink-0" />
                    <span>{t("components.prDetail.review")}</span>
                  </Button>
                  <button
                    onClick={() => onOpenUrl(pr.url)}
                    className="text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 transition-colors p-1 cursor-pointer"
                    title={t("components.prDetail.openInBrowser")}
                  >
                    <ExternalLink className="h-3.5 w-3.5" />
                  </button>
                  <button
                    onClick={() => setFullscreen((f) => !f)}
                    className="text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 transition-colors p-1 cursor-pointer"
                    title={fullscreen ? t("components.prDetail.exitFullscreen") : t("components.prDetail.fullscreen")}
                  >
                    {fullscreen ? (
                      <Minimize2 className="h-3.5 w-3.5" />
                    ) : (
                      <Maximize2 className="h-3.5 w-3.5" />
                    )}
                  </button>
                </div>
              </div>
              <SheetDescription className="text-xs mt-0.5 flex items-center gap-1 flex-wrap">
                <span>#{pr.number}</span>
                <span>·</span>
                <span className="font-mono">{pr.head}</span>
                <ArrowRight className="inline h-3 w-3" />
                <span className="font-mono">{pr.base}</span>
                <span>·</span>
                <span>{formatRelativeDate(pr.updated_at)}</span>
              </SheetDescription>
            </div>
          </div>
        </SheetHeader>

        {/* Scrollable body */}
        <div className="flex-1 overflow-y-auto">
          <div className="flex flex-col gap-3 p-2">
            {/* Meta card */}
            <Collapsible defaultOpen>
              <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
                <CollapsibleTrigger className="w-full cursor-pointer">
                  <div className="flex flex-row items-center gap-3 px-4 py-3">
                    <div className="h-7 w-7 flex items-center justify-center rounded-lg bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
                      <GitBranch size={14} strokeWidth={2} />
                    </div>
                    <CardTitle className="text-sm font-semibold text-zinc-900 dark:text-white/95 leading-none flex-1 text-left">
                      {t("components.prDetail.cardDetails")}
                    </CardTitle>
                    <ChevronDown className="h-3.5 w-3.5 text-zinc-400 transition-transform duration-200 [[data-state=open]_&]:rotate-180" />
                  </div>
                </CollapsibleTrigger>
                <CollapsibleContent>
                  <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
                    <div className="flex items-center justify-between px-4 py-3">
                       <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-400 dark:text-zinc-500">
                         {t("components.prDetail.labelBranches")}
                       </span>
                      <span className="text-xs text-zinc-700 dark:text-zinc-300 font-mono flex items-center gap-1">
                        {pr.head}{" "}
                        <ArrowRight className="h-3 w-3 text-zinc-400" />{" "}
                        {pr.base}
                      </span>
                    </div>

                    {pr.author && (
                      <div className="flex items-center justify-between px-4 py-3">
                         <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-400 dark:text-zinc-500">
                           {t("components.prDetail.labelAuthor")}
                         </span>
                        <span className="text-xs text-zinc-700 dark:text-zinc-300">
                          {pr.author}
                        </span>
                      </div>
                    )}

                    {pr.labels.length > 0 && (
                      <div className="flex items-center justify-between px-4 py-3 gap-4">
                         <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-400 dark:text-zinc-500 shrink-0">
                           {t("components.prDetail.labelLabels")}
                         </span>
                        <div className="flex flex-wrap gap-1 justify-end">
                          {pr.labels.map((label) => (
                            <Badge
                              key={label}
                              variant="outline"
                              className="text-[10px]"
                            >
                              {label}
                            </Badge>
                          ))}
                        </div>
                      </div>
                    )}

                    {pr.reviewers.length > 0 && (
                      <div className="flex items-center justify-between px-4 py-3 gap-4">
                         <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-400 dark:text-zinc-500 shrink-0">
                           {t("components.prDetail.labelReviewers")}
                         </span>
                        <div className="flex flex-wrap gap-1 justify-end">
                          {pr.reviewers.map((r) => (
                            <Badge
                              key={r}
                              variant="secondary"
                              className="text-xs font-normal"
                            >
                              {r}
                            </Badge>
                          ))}
                        </div>
                      </div>
                    )}
                  </CardContent>
                </CollapsibleContent>
              </Card>
            </Collapsible>

            {/* Description card */}
            <Collapsible defaultOpen>
              <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
                <CollapsibleTrigger className="w-full cursor-pointer">
                  <div className="flex flex-row items-center gap-3 px-4 py-3">
                    <div className="h-7 w-7 flex items-center justify-center rounded-lg bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
                      <FileText size={14} strokeWidth={2} />
                    </div>
                    <CardTitle className="text-sm font-semibold text-zinc-900 dark:text-white/95 leading-none flex-1 text-left">
                      {t("components.prDetail.cardDescription")}
                    </CardTitle>
                    <ChevronDown className="h-3.5 w-3.5 text-zinc-400 transition-transform duration-200 [[data-state=open]_&]:rotate-180" />
                  </div>
                </CollapsibleTrigger>
                <CollapsibleContent>
                  <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
                    <div className="px-4 py-3">
                      {pr.body && pr.body.trim() !== "" ? (
                        <MarkdownBody content={pr.body} />
                      ) : (
                        <p className="text-sm text-zinc-400 dark:text-zinc-600 italic">
                          {t("components.prDetail.noDescription")}
                        </p>
                      )}
                    </div>
                  </CardContent>
                </CollapsibleContent>
              </Card>
            </Collapsible>

            {/* Comments card */}
            <Collapsible defaultOpen={comments.length > 0}>
              <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
                <CollapsibleTrigger className="w-full cursor-pointer">
                  <div className="flex flex-row items-center gap-3 px-4 py-3">
                    <div className="h-7 w-7 flex items-center justify-center rounded-lg bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
                      <MessageSquare size={14} strokeWidth={2} />
                    </div>
                    <CardTitle className="text-sm font-semibold text-zinc-900 dark:text-white/95 leading-none flex-1 text-left">
                      {t("components.prDetail.cardComments")}
                    </CardTitle>
                    <ChevronDown className="h-3.5 w-3.5 text-zinc-400 transition-transform duration-200 [[data-state=open]_&]:rotate-180" />
                  </div>
                </CollapsibleTrigger>
                <CollapsibleContent>
                  <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
                    {commentsLoading ? (
                      <div className="flex flex-col gap-2 px-4 py-3">
                        <Skeleton className="h-14 w-full" />
                        <Skeleton className="h-14 w-full" />
                      </div>
                    ) : comments.length === 0 ? (
                      <p className="px-4 py-3 text-sm text-zinc-400 dark:text-zinc-500 italic">
                        {t("components.prDetail.noComments")}
                      </p>
                    ) : (
                      <div className="divide-y divide-zinc-100 dark:divide-zinc-800/50">
                        {comments.map((c) => (
                          <PrCommentItem key={c.id} comment={c} />
                        ))}
                      </div>
                    )}
                  </CardContent>
                </CollapsibleContent>
                <div className="pt-3">
                  <textarea
                    ref={commentRef}
                    value={commentBody}
                    onChange={(e) => setCommentBody(e.target.value)}
                    placeholder={t("components.prDetail.commentPlaceholder")}
                    rows={3}
                    className="w-full bg-transparent px-4 text-sm text-zinc-900 dark:text-white placeholder:text-zinc-400 dark:placeholder:text-zinc-500 resize-none focus:outline-none"
                  />
                  <div className="flex justify-end px-4 pb-3">
                    <Button
                      size="sm"
                      disabled={!commentBody.trim() || postComment.isPending}
                      onClick={handlePostComment}
                    >
                      {postComment.isPending ? t("components.prDetail.commentPosting") : t("components.prDetail.commentSubmit")}
                    </Button>
                  </div>
                </div>
              </Card>
            </Collapsible>
          </div>
        </div>

        {/* Footer — merge button */}
        <div className="px-5 py-3 border-t border-zinc-100 dark:border-zinc-800 shrink-0 flex flex-col gap-2">
          {mergeError && (
            <div className="rounded-lg bg-red-50 dark:bg-red-500/10 border border-red-200 dark:border-red-500/20 px-3 py-2 text-sm text-red-700 dark:text-red-400">
              {mergeError}
            </div>
          )}
          <div className="flex gap-2">
            <Button
              className="flex-1 bg-purple-600 hover:bg-purple-700 text-white"
              onClick={handleMerge}
              disabled={isMerging}
            >
              {isMerging
                ? <Loader2 className="h-4 w-4 mr-1.5 animate-spin" />
                : <GitMerge className="h-4 w-4 mr-1.5" />
              }
              {isMerging ? "Merging…" : strategyLabels[mergeStrategy]}
            </Button>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="outline"
                  size="icon"
                  className="shrink-0 border-purple-200 dark:border-purple-500/30"
                  disabled={isMerging}
                >
                  <ChevronDown className="h-4 w-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-52">
                {(["merge", "squash", "rebase"] as PrMergeStrategy[]).map(
                  (s) => (
                    <DropdownMenuItem
                      key={s}
                      onClick={() => setMergeStrategy(s)}
                      className="flex items-center justify-between"
                    >
                      {strategyLabels[s]}
                      {mergeStrategy === s && (
                        <Check className="h-3.5 w-3.5 text-purple-500" />
                      )}
                    </DropdownMenuItem>
                  ),
                )}
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}
