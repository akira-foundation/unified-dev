import { EditorContent } from "@tiptap/react";

import { useI18n } from "@/i18n/i18n";
import type { useIssueBodyEditor } from "@/hooks/useIssueBodyEditor";

const EDITOR_CLASS =
  "issue-editor text-[15px] text-zinc-700 dark:text-zinc-300 [&_.ProseMirror]:outline-none [&_.ProseMirror]:min-h-[6rem] [&_.ProseMirror_h1]:mt-4 [&_.ProseMirror_h1]:mb-1 [&_.ProseMirror_h1]:text-lg [&_.ProseMirror_h1]:font-semibold [&_.ProseMirror_h2]:mt-3 [&_.ProseMirror_h2]:mb-1 [&_.ProseMirror_h2]:text-base [&_.ProseMirror_h2]:font-semibold [&_.ProseMirror_h3]:mt-2 [&_.ProseMirror_h3]:mb-1 [&_.ProseMirror_h3]:text-sm [&_.ProseMirror_h3]:font-medium [&_.ProseMirror_p]:my-0 [&_.ProseMirror_p]:leading-7 [&_.ProseMirror_ul]:my-1 [&_.ProseMirror_ul]:list-disc [&_.ProseMirror_ul]:pl-5 [&_.ProseMirror_ol]:my-1 [&_.ProseMirror_ol]:list-decimal [&_.ProseMirror_ol]:pl-5 [&_.ProseMirror_li]:my-0.5 [&_.ProseMirror_code]:rounded [&_.ProseMirror_code]:bg-zinc-100 [&_.ProseMirror_code]:dark:bg-zinc-800 [&_.ProseMirror_code]:px-1 [&_.ProseMirror_code]:py-0.5 [&_.ProseMirror_code]:text-xs [&_.ProseMirror_pre]:rounded-md [&_.ProseMirror_pre]:bg-zinc-100 [&_.ProseMirror_pre]:dark:bg-zinc-800 [&_.ProseMirror_pre]:p-3 [&_.ProseMirror_pre]:text-xs [&_.ProseMirror_pre]:overflow-x-auto [&_.ProseMirror_blockquote]:border-l-2 [&_.ProseMirror_blockquote]:border-zinc-300 [&_.ProseMirror_blockquote]:dark:border-zinc-600 [&_.ProseMirror_blockquote]:pl-3 [&_.ProseMirror_blockquote]:text-zinc-500 [&_.ProseMirror_hr]:border-zinc-200 [&_.ProseMirror_hr]:dark:border-zinc-700 [&_.ProseMirror_p.is-editor-empty:first-child::before]:pointer-events-none [&_.ProseMirror_p.is-editor-empty:first-child::before]:float-left [&_.ProseMirror_p.is-editor-empty:first-child::before]:h-0 [&_.ProseMirror_p.is-editor-empty:first-child::before]:text-zinc-400 [&_.ProseMirror_p.is-editor-empty:first-child::before]:dark:text-zinc-600 [&_.ProseMirror_p.is-editor-empty:first-child::before]:content-[attr(data-placeholder)]";

interface IssueDescriptionProps {
  editor: ReturnType<typeof useIssueBodyEditor>;
}

export function IssueDescription({ editor }: IssueDescriptionProps) {
  const { t } = useI18n();
  const { editor: bodyEditor, isDirty, cancel, saveMutation } = editor;

  return (
    <div>
      <div className="cursor-text" onClick={() => bodyEditor?.commands.focus()}>
        <EditorContent editor={bodyEditor} className={EDITOR_CLASS} />
      </div>

      {isDirty && (
        <div className="mt-3 flex justify-end gap-2">
          <button
            onMouseDown={(e) => { e.preventDefault(); cancel(); }}
            className="rounded-md border border-zinc-300 px-3 py-1 text-xs text-zinc-600 transition-colors hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-400 dark:hover:bg-zinc-800"
          >
            {t("common.cancel")}
          </button>
          <button
            onMouseDown={(e) => { e.preventDefault(); saveMutation.mutate(); }}
            disabled={saveMutation.isPending}
            className="rounded-md bg-purple-600 px-3 py-1 text-xs text-white transition-colors hover:bg-purple-700 disabled:opacity-50"
          >
            {saveMutation.isPending ? t("common.saving") : t("common.save")}
          </button>
        </div>
      )}
    </div>
  );
}
