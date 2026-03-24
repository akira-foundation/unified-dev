import { formatRelativeDate } from "./pr-item";
import { MarkdownBody } from "./markdown-body";
import type { PrCommentDto } from "../../types/organization";

export function PrCommentItem({ comment }: { comment: PrCommentDto }) {
  return (
    <div className="flex flex-col gap-1.5 px-4 py-3">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold text-zinc-700 dark:text-zinc-300">
          {comment.author}
        </span>
        <span className="text-[11px] text-zinc-400 dark:text-zinc-500">
          {formatRelativeDate(comment.created_at)}
        </span>
      </div>
      <MarkdownBody content={comment.body} />
    </div>
  );
}
