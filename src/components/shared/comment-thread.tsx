import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ArrowUp, Paperclip } from "lucide-react";
import { toast } from "sonner";

import { queryKeys } from "@/lib/query-keys";
import { useI18n } from "@/i18n/i18n";
import { PrCommentItem } from "@/components/repos/pr-comment-item";
import type { PrCommentDto } from "@/types/organization";

interface CommentThreadProps {
  organizationId: string;
  repoName: string;
  number: number;
  heading: string;
}

export function CommentThread({ organizationId, repoName, number, heading }: CommentThreadProps) {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const [body, setBody] = useState("");
  const qk = queryKeys.prComments(organizationId, repoName, number);

  const { data: comments = [], isLoading } = useQuery({
    queryKey: qk,
    queryFn: () =>
      invoke<PrCommentDto[]>("get_pr_comments", { organizationId, repoName, prNumber: number }),
  });

  const post = useMutation({
    mutationFn: (text: string) =>
      invoke<PrCommentDto>("post_pr_comment", { organizationId, repoName, prNumber: number, body: text }),
    onMutate: async (text) => {
      await queryClient.cancelQueries({ queryKey: qk });
      const prev = queryClient.getQueryData<PrCommentDto[]>(qk);
      const optimistic: PrCommentDto = {
        id: `temp-${Date.now()}`,
        author: "You",
        body: text,
        created_at: new Date().toISOString(),
      };
      queryClient.setQueryData<PrCommentDto[]>(qk, [...(prev ?? []), optimistic]);
      return { prev };
    },
    onError: (err, _text, ctx) => {
      if (ctx?.prev) queryClient.setQueryData(qk, ctx.prev);
      toast.error(err instanceof Error ? err.message : String(err));
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: qk }),
  });

  const remove = useMutation({
    mutationFn: (commentId: string) =>
      invoke("delete_pr_comment", { organizationId, repoName, commentId }),
    onMutate: async (commentId) => {
      await queryClient.cancelQueries({ queryKey: qk });
      const prev = queryClient.getQueryData<PrCommentDto[]>(qk);
      queryClient.setQueryData<PrCommentDto[]>(qk, (cur) => (cur ?? []).filter((c) => c.id !== commentId));
      return { prev };
    },
    onError: (err, _id, ctx) => {
      if (ctx?.prev) queryClient.setQueryData(qk, ctx.prev);
      toast.error(err instanceof Error ? err.message : String(err));
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: qk }),
  });

  const submit = () => {
    const text = body.trim();
    if (!text) return;
    setBody("");
    post.mutate(text);
  };

  return (
    <div className="mt-10 border-t border-zinc-200 pt-6 dark:border-zinc-800">
      <h2 className="mb-3 text-[13px] font-semibold text-zinc-700 dark:text-zinc-200">{heading}</h2>

      {isLoading ? (
        <div className="mb-4 h-12 animate-pulse rounded-lg bg-zinc-100 dark:bg-white/[0.03]" />
      ) : (
        comments.length > 0 && (
          <div className="mb-4 divide-y divide-zinc-100 rounded-lg border border-zinc-200 dark:divide-zinc-800/60 dark:border-zinc-800/80">
            {comments.map((comment) => (
              <PrCommentItem
                key={comment.id}
                comment={comment}
                onDelete={comment.id.startsWith("temp-") ? undefined : () => remove.mutate(comment.id)}
              />
            ))}
          </div>
        )
      )}

      <div className="relative rounded-md border border-zinc-200 bg-white focus-within:border-zinc-300 dark:border-zinc-800 dark:bg-zinc-900/40 dark:focus-within:border-zinc-700">
        <textarea
          value={body}
          onChange={(e) => setBody(e.target.value)}
          onKeyDown={(e) => {
            if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
              e.preventDefault();
              submit();
            }
          }}
          placeholder={t("issues.detail.commentPlaceholder")}
          className="h-20 w-full resize-none bg-transparent px-3 py-2.5 text-sm text-zinc-700 outline-none placeholder:text-zinc-400 dark:text-zinc-200 dark:placeholder:text-zinc-600"
        />
        <div className="absolute bottom-2 right-2 flex items-center gap-1.5">
          <button className="flex h-7 w-7 items-center justify-center rounded-full text-zinc-400 transition-colors hover:bg-zinc-100 hover:text-zinc-600 dark:hover:bg-zinc-800 dark:hover:text-zinc-300">
            <Paperclip className="h-4 w-4" />
          </button>
          <button
            onClick={submit}
            disabled={!body.trim()}
            className="flex h-7 w-7 items-center justify-center rounded-full bg-purple-600 text-white transition-colors hover:bg-purple-700 disabled:opacity-40"
          >
            <ArrowUp className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}
