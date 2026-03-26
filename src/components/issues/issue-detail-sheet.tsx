import { useState, useEffect, useRef, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useEditor, EditorContent, ReactRenderer } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import TaskList from "@tiptap/extension-task-list";
import TaskItem from "@tiptap/extension-task-item";
import { Markdown } from "tiptap-markdown";
import tippy, { type Instance as TippyInstance } from "tippy.js";
import { SlashCommandExtension, SLASH_COMMANDS } from "@/components/issues/slash-command-extension";
import { SlashCommandMenu, type SlashCommandMenuRef } from "@/components/issues/slash-command-menu";
import {
  Bot,
  ChevronDown,
  CircleDot,
  ExternalLink,
  FileText,
  GitPullRequest,
  Maximize2,
  Minimize2,
  X,
} from "lucide-react";

import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardTitle } from "@/components/ui/card";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { useI18n } from "@/i18n/i18n";
import { queryKeys } from "@/lib/query-keys";
import { LabelBadge } from "@/components/issues/label-badge";
import { useDelegateIssue } from "@/hooks/useDelegateIssue";
import type { IssueDto } from "@/types/issue";

interface IssueDetailSheetProps {
  issue: IssueDto | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

async function handleOpenUrl(url: string) {
  try {
    await openUrl(url);
  } catch {
    window.open(url, "_blank");
  }
}

export function IssueDetailSheet({ issue, open, onOpenChange }: IssueDetailSheetProps) {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const [closeError, setCloseError] = useState<string | null>(null);
  const [fullscreen, setFullscreen] = useState(false);
  const [delegating, setDelegating] = useState(false);
  const [isEditingBody, setIsEditingBody] = useState(false);
  const { delegateIssue } = useDelegateIssue();
  const editorWrapperRef = useRef<HTMLDivElement>(null);

  const slashRender = useCallback(() => {
    let renderer: ReactRenderer<SlashCommandMenuRef>;
    let popup: TippyInstance | null = null;
    return {
      onStart(props: any) {
        renderer = new ReactRenderer(SlashCommandMenu, { props, editor: props.editor });
        if (!props.clientRect) return;
        popup = tippy(document.body, {
          getReferenceClientRect: () => props.clientRect?.() ?? new DOMRect(),
          appendTo: () => document.body,
          content: renderer.element,
          showOnCreate: true,
          interactive: true,
          trigger: "manual",
          placement: "bottom-start",
          offset: [0, 8],
          maxWidth: 280,
        });
      },
      onUpdate(props: any) {
        renderer.updateProps(props);
        if (!props.clientRect) return;
        popup?.setProps({ getReferenceClientRect: () => props.clientRect?.() ?? new DOMRect() });
      },
      onKeyDown(props: { event: KeyboardEvent }) {
        if (props.event.key === "Escape") { popup?.hide(); return true; }
        return (renderer.ref as SlashCommandMenuRef | null)?.onKeyDown(props.event) ?? false;
      },
      onExit() { popup?.destroy(); popup = null; renderer.destroy(); },
    };
  }, []);

  const bodyEditor = useEditor({
    extensions: [
      StarterKit,
      TaskList.configure({ HTMLAttributes: { class: "issue-task-list" } }),
      TaskItem.configure({ nested: true, HTMLAttributes: { class: "issue-task-item" } }),
      Markdown.configure({ transformPastedText: true }),
      SlashCommandExtension.configure({
        suggestion: {
          items: ({ query }: { query: string }) =>
            SLASH_COMMANDS.filter((item) => item.title.toLowerCase().includes(query.toLowerCase())),
          render: slashRender,
        },
      }),
    ],
    editable: true,
    editorProps: { attributes: { class: "outline-none" } },
    content: "",
  });

  useEffect(() => {
    if (!bodyEditor) return;
    if (issue?.body) {
      bodyEditor.commands.setContent(issue.body);
    } else {
      bodyEditor.commands.clearContent();
    }
  }, [issue?.body, bodyEditor]);

  const enterEditMode = useCallback(() => {
    if (!bodyEditor) return;
    setIsEditingBody(true);
    setTimeout(() => bodyEditor.commands.focus("end"), 0);
  }, [bodyEditor]);

  const cancelEdit = useCallback(() => {
    if (!bodyEditor) return;
    setIsEditingBody(false);
    if (issue?.body) {
      bodyEditor.commands.setContent(issue.body);
    } else {
      bodyEditor.commands.clearContent();
    }
    bodyEditor.commands.blur();
  }, [bodyEditor, issue?.body]);

  useEffect(() => {
    if (!isEditingBody) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") cancelEdit();
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isEditingBody, cancelEdit]);

  useEffect(() => {
    if (!isEditingBody) return;
    const handlePointerDown = (e: PointerEvent) => {
      if (editorWrapperRef.current && !editorWrapperRef.current.contains(e.target as Node)) {
        cancelEdit();
      }
    };
    document.addEventListener("pointerdown", handlePointerDown);
    return () => document.removeEventListener("pointerdown", handlePointerDown);
  }, [isEditingBody, cancelEdit]);

  const saveMutation = useMutation({
    mutationFn: async () => {
      if (!issue || !bodyEditor) return;
      // @ts-expect-error - tiptap-markdown adds getMarkdown to editor storage
      const body: string = bodyEditor.storage.markdown?.getMarkdown?.() ?? bodyEditor.getText();
      await invoke("update_issue", {
        orgId: issue.orgId,
        repoName: issue.repoName,
        number: issue.number,
        input: { body },
      });
    },
    onSuccess: () => {
      if (!issue) return;
      queryClient.invalidateQueries({ queryKey: queryKeys.issues(issue.orgId, issue.repoName) });
      setIsEditingBody(false);
      bodyEditor?.commands.blur();
    },
    onError: (err: unknown) => {
      setCloseError(err instanceof Error ? err.message : String(err));
    },
  });

  const closeMutation = useMutation({
    mutationFn: async () => {
      if (!issue) return;
      await invoke("close_issue", {
        orgId: issue.orgId,
        repoName: issue.repoName,
        number: issue.number,
        reason: "completed",
      });
    },
    onSuccess: () => {
      if (!issue) return;
      queryClient.invalidateQueries({ queryKey: queryKeys.issues(issue.orgId, issue.repoName) });
      onOpenChange(false);
    },
    onError: (err: unknown) => {
      setCloseError(err instanceof Error ? err.message : String(err));
    },
  });

  if (!issue) return null;

  const isOpen = issue.status === "open";

  return (
    <Sheet
      open={open}
      onOpenChange={(o) => {
        if (!o) { setCloseError(null); setFullscreen(false); }
        onOpenChange(o);
      }}
    >
      <SheetContent
        side="right"
        className={`flex flex-col p-0 overflow-hidden transition-all duration-200 ${fullscreen ? "w-full sm:max-w-full" : "w-full sm:max-w-lg"}`}
      >
        {/* Header */}
        <SheetHeader className="px-5 pt-5 pb-4 border-b border-zinc-100 dark:border-zinc-800 shrink-0">
          <div className="flex items-start gap-3 pr-6">
            <div className="mt-1 shrink-0">
              {isOpen ? (
                <div className="h-2.5 w-2.5 rounded-full bg-green-500" />
              ) : (
                <div className="h-2.5 w-2.5 rounded-full bg-zinc-500" />
              )}
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex items-center justify-between gap-2">
                <div className="min-w-0 flex items-center gap-2">
                  <SheetTitle className="text-base leading-snug text-left">
                    {issue.title}
                  </SheetTitle>
                  <span
                    className={`shrink-0 rounded-[6px] px-1.5 py-0.5 text-[10px] font-medium ${
                      issue.syncWithProvider
                        ? "bg-emerald-500/10 text-emerald-400"
                        : "bg-zinc-500/10 text-zinc-400"
                    }`}
                  >
                    {issue.syncWithProvider ? "sync" : "local"}
                  </span>
                </div>
                <div className="flex items-center gap-1 shrink-0">
                  {issue.url && (
                    <button
                      onClick={() => handleOpenUrl(issue.url)}
                      className="text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 transition-colors p-1 cursor-pointer"
                      title={t("issues.detail.openUrl")}
                    >
                      <ExternalLink className="h-3.5 w-3.5" />
                    </button>
                  )}
                  <button
                    onClick={() => setFullscreen((f) => !f)}
                    className="text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 transition-colors p-1 cursor-pointer"
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
                <span>{issue.repoName}</span>
                <span>·</span>
                <span>#{issue.number}</span>
              </SheetDescription>
            </div>
          </div>
        </SheetHeader>

        {/* Scrollable body */}
        <div className="flex-1 overflow-y-auto">
          <div className="flex flex-col gap-3 p-2">

            {/* Details card */}
            <Collapsible defaultOpen>
              <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
                <CollapsibleTrigger className="w-full cursor-pointer">
                  <div className="flex flex-row items-center gap-3 px-4 py-3">
                    <div className="h-7 w-7 flex items-center justify-center rounded-lg bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
                      <CircleDot size={14} strokeWidth={2} />
                    </div>
                    <CardTitle className="text-sm font-semibold text-zinc-900 dark:text-white/95 leading-none flex-1 text-left">
                      {t("issues.detail.cardDetails")}
                    </CardTitle>
                    <ChevronDown className="h-3.5 w-3.5 text-zinc-400 transition-transform duration-200 [[data-state=open]_&]:rotate-180" />
                  </div>
                </CollapsibleTrigger>
                <CollapsibleContent>
                  <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
                    <div className="flex items-center justify-between px-4 py-3">
                      <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-400 dark:text-zinc-500">
                        {t("issues.detail.labelStatus")}
                      </span>
                      <Badge variant={isOpen ? "secondary" : "outline"}>
                        {issue.status}
                      </Badge>
                    </div>

                    <div className="flex items-center justify-between px-4 py-3">
                      <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-400 dark:text-zinc-500">
                        Source
                      </span>
                      <Badge variant="outline">
                        {issue.syncWithProvider ? "Synced" : "Local"}
                      </Badge>
                    </div>

                    {issue.author && (
                      <div className="flex items-center justify-between px-4 py-3">
                        <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-400 dark:text-zinc-500">
                          {t("issues.detail.labelAuthor")}
                        </span>
                        <span className="text-xs text-zinc-700 dark:text-zinc-300">
                          {issue.author}
                        </span>
                      </div>
                    )}

                    {issue.assignees.length > 0 && (
                      <div className="flex items-center justify-between px-4 py-3 gap-4">
                        <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-400 dark:text-zinc-500 shrink-0">
                          {t("issues.detail.labelAssignees")}
                        </span>
                        <div className="flex flex-wrap gap-1 justify-end">
                          {issue.assignees.map((a) => (
                            <Badge key={a} variant="secondary" className="text-xs font-normal">
                              {a}
                            </Badge>
                          ))}
                        </div>
                      </div>
                    )}

                    {issue.labels.length > 0 && (
                      <div className="flex items-center justify-between px-4 py-3 gap-4">
                        <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-400 dark:text-zinc-500 shrink-0">
                          {t("issues.detail.labelLabels")}
                        </span>
                        <div className="flex flex-wrap gap-1 justify-end">
                          {issue.labels.map((label) => (
                            <LabelBadge
                              key={label}
                              name={label}
                            />
                          ))}
                        </div>
                      </div>
                    )}

                    <div className="flex items-center justify-between px-4 py-3">
                      <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-400 dark:text-zinc-500">
                        {t("issues.detail.labelCreated")}
                      </span>
                      <span className="text-xs text-zinc-700 dark:text-zinc-300">
                        {new Date(issue.createdAt).toLocaleDateString()}
                      </span>
                    </div>

                    <div className="flex items-center justify-between px-4 py-3">
                      <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-400 dark:text-zinc-500">
                        {t("issues.detail.labelUpdated")}
                      </span>
                      <span className="text-xs text-zinc-700 dark:text-zinc-300">
                        {new Date(issue.updatedAt).toLocaleDateString()}
                      </span>
                    </div>
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
                      {t("issues.detail.cardDescription")}
                    </CardTitle>
                    <ChevronDown className="h-3.5 w-3.5 text-zinc-400 transition-transform duration-200 [[data-state=open]_&]:rotate-180" />
                  </div>
                </CollapsibleTrigger>
                 <CollapsibleContent>
                   <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
                     <div className="px-4 py-3">
                       <div
                         ref={editorWrapperRef}
                         onDoubleClick={enterEditMode}
                         className={isEditingBody ? "rounded-md border border-purple-500/40 bg-zinc-50 dark:bg-zinc-900/50 p-2 -mx-2" : ""}
                       >
                         {issue.body || isEditingBody ? (
                            <EditorContent
                              editor={bodyEditor}
                              className={`issue-editor text-sm text-zinc-700 dark:text-zinc-300 [&_.ProseMirror]:outline-none [&_.ProseMirror]:min-h-[2rem] [&_.ProseMirror_h1]:mt-4 [&_.ProseMirror_h1]:mb-1 [&_.ProseMirror_h1]:text-base [&_.ProseMirror_h1]:font-semibold [&_.ProseMirror_h2]:mt-3 [&_.ProseMirror_h2]:mb-1 [&_.ProseMirror_h2]:text-sm [&_.ProseMirror_h2]:font-semibold [&_.ProseMirror_h3]:mt-2 [&_.ProseMirror_h3]:mb-1 [&_.ProseMirror_h3]:text-sm [&_.ProseMirror_h3]:font-medium [&_.ProseMirror_p]:my-0 [&_.ProseMirror_p]:leading-6 [&_.ProseMirror_ul]:my-1 [&_.ProseMirror_ul]:list-disc [&_.ProseMirror_ul]:pl-5 [&_.ProseMirror_ol]:my-1 [&_.ProseMirror_ol]:list-decimal [&_.ProseMirror_ol]:pl-5 [&_.ProseMirror_li]:my-0.5 [&_.ProseMirror_code]:rounded [&_.ProseMirror_code]:bg-zinc-100 [&_.ProseMirror_code]:dark:bg-zinc-800 [&_.ProseMirror_code]:px-1 [&_.ProseMirror_code]:py-0.5 [&_.ProseMirror_code]:text-xs [&_.ProseMirror_pre]:rounded-md [&_.ProseMirror_pre]:bg-zinc-100 [&_.ProseMirror_pre]:dark:bg-zinc-800 [&_.ProseMirror_pre]:p-3 [&_.ProseMirror_pre]:text-xs [&_.ProseMirror_pre]:overflow-x-auto [&_.ProseMirror_blockquote]:border-l-2 [&_.ProseMirror_blockquote]:border-zinc-300 [&_.ProseMirror_blockquote]:dark:border-zinc-600 [&_.ProseMirror_blockquote]:pl-3 [&_.ProseMirror_blockquote]:text-zinc-500 [&_.ProseMirror_hr]:border-zinc-200 [&_.ProseMirror_hr]:dark:border-zinc-700${!isEditingBody ? " pointer-events-none select-none" : ""}`}
                            />
                         ) : (
                           <p className="text-sm text-zinc-400 dark:text-zinc-600 italic cursor-text" onDoubleClick={enterEditMode}>
                             {t("issues.detail.noDescription")}
                           </p>
                         )}
                         {isEditingBody && (
                           <div className="flex gap-2 mt-3 justify-end">
                             <button
                               onMouseDown={(e) => { e.preventDefault(); cancelEdit(); }}
                               className="px-3 py-1 text-xs rounded-md border border-zinc-300 dark:border-zinc-700 text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors"
                             >
                               {t("common.cancel")}
                             </button>
                             <button
                               onMouseDown={(e) => { e.preventDefault(); saveMutation.mutate(); }}
                               disabled={saveMutation.isPending}
                               className="px-3 py-1 text-xs rounded-md bg-purple-600 text-white hover:bg-purple-700 disabled:opacity-50 transition-colors"
                             >
                               {saveMutation.isPending ? t("common.saving") : t("common.save")}
                             </button>
                           </div>
                         )}
                       </div>
                     </div>
                   </CardContent>
                 </CollapsibleContent>
              </Card>
            </Collapsible>

            {/* Linked PRs card */}
            {issue.linkedPrNumbers.length > 0 && (
              <Collapsible defaultOpen>
                <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
                  <CollapsibleTrigger className="w-full cursor-pointer">
                    <div className="flex flex-row items-center gap-3 px-4 py-3">
                      <div className="h-7 w-7 flex items-center justify-center rounded-lg bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
                        <GitPullRequest size={14} strokeWidth={2} />
                      </div>
                      <CardTitle className="text-sm font-semibold text-zinc-900 dark:text-white/95 leading-none flex-1 text-left">
                        {t("issues.detail.cardLinkedPrs")}
                      </CardTitle>
                      <ChevronDown className="h-3.5 w-3.5 text-zinc-400 transition-transform duration-200 [[data-state=open]_&]:rotate-180" />
                    </div>
                  </CollapsibleTrigger>
                  <CollapsibleContent>
                    <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">
                      {issue.linkedPrNumbers.map((n) => (
                        <div key={n} className="flex items-center justify-between px-4 py-3">
                          <span className="text-xs text-zinc-700 dark:text-zinc-300 flex items-center gap-1.5">
                            <GitPullRequest className="h-3.5 w-3.5 text-zinc-400" />
                            #{n}
                          </span>
                        </div>
                      ))}
                    </CardContent>
                  </CollapsibleContent>
                </Card>
              </Collapsible>
            )}

          </div>
        </div>

        {/* Footer */}
        <div className="px-5 py-3 border-t border-zinc-100 dark:border-zinc-800 shrink-0 flex flex-col gap-2">
          {closeError && (
            <div className="rounded-lg bg-red-50 dark:bg-red-500/10 border border-red-200 dark:border-red-500/20 px-3 py-2 text-sm text-red-700 dark:text-red-400">
              {closeError}
            </div>
          )}
          <div className="flex gap-2">
            <Button
              variant="outline"
              className="flex-1 cursor-pointer"
              disabled={delegating}
              onClick={async () => {
                setDelegating(true);
                try {
                  await delegateIssue(issue);
                  onOpenChange(false);
                } finally {
                  setDelegating(false);
                }
              }}
            >
              <Bot className="h-4 w-4 mr-1.5" />
              {delegating ? t("issues.detail.delegating") : t("issues.detail.delegate")}
            </Button>
            {isOpen && (
              <Button
                variant="outline"
                className="flex-1 hover:border-red-500/50 hover:text-red-400 cursor-pointer"
                disabled={closeMutation.isPending}
                onClick={() => closeMutation.mutate()}
              >
                <X className="h-4 w-4 mr-1.5" />
                {closeMutation.isPending ? t("issues.detail.closing") : t("issues.detail.close")}
              </Button>
            )}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}
