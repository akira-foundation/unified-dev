import { Trash2 } from "lucide-react";

import { formatRelativeDate } from "./pr-item";
import { MarkdownBody } from "./markdown-body";
import type { PrCommentDto } from "../../types/organization";

export function PrCommentItem({ comment, onDelete }: { comment: PrCommentDto; onDelete?: () => void }) {
  return (
    <div className="group flex flex-col gap-1.5 px-4 py-3">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold text-zinc-700 dark:text-zinc-300">
          {comment.author}
        </span>
        <div className="flex items-center gap-2">
          <span className="text-[11px] text-zinc-400 dark:text-zinc-500">
            {formatRelativeDate(comment.created_at)}
          </span>
          {onDelete && (
            <button
              onClick={onDelete}
              className="text-zinc-400 opacity-0 transition-opacity hover:text-red-500 group-hover:opacity-100"
            >
              <Trash2 className="h-3.5 w-3.5" />
            </button>
          )}
        </div>
      </div>
      <MarkdownBody content={comment.body} />
    </div>
  );
}
