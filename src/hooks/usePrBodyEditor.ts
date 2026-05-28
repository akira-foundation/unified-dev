import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { useEditor, ReactRenderer } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import Placeholder from "@tiptap/extension-placeholder";
import TaskList from "@tiptap/extension-task-list";
import TaskItem from "@tiptap/extension-task-item";
import { Markdown } from "tiptap-markdown";
import tippy, { type Instance as TippyInstance } from "tippy.js";

import { SlashCommandExtension, SLASH_COMMANDS } from "@/components/issues/slash-command-extension";
import { SlashCommandMenu, type SlashCommandMenuRef } from "@/components/issues/slash-command-menu";
import { useI18n } from "@/i18n/i18n";

interface PrBodyTarget {
  organizationId: string;
  repoName: string;
  prNumber: number;
  body: string | null;
}

export function usePrBodyEditor(target: PrBodyTarget | null) {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const [savedBody, setSavedBody] = useState(target?.body ?? "");
  const [draft, setDraft] = useState(target?.body ?? "");

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

  const editor = useEditor(
    {
      extensions: [
        StarterKit,
        Placeholder.configure({ placeholder: t("issues.create.bodyPlaceholderWithCommands") }),
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
      content: target?.body ?? "",
      onUpdate({ editor: e }) {
        // @ts-expect-error - tiptap-markdown adds getMarkdown to editor storage
        const md: string = e.storage.markdown?.getMarkdown?.() ?? e.getText();
        setDraft(md);
      },
    },
    [target?.organizationId, target?.repoName, target?.prNumber],
  );

  useEffect(() => {
    setSavedBody(target?.body ?? "");
    setDraft(target?.body ?? "");
  }, [target?.organizationId, target?.repoName, target?.prNumber, target?.body]);

  const isDirty = draft !== savedBody;

  const cancel = useCallback(() => {
    if (!editor) return;
    editor.commands.setContent(savedBody);
    setDraft(savedBody);
  }, [editor, savedBody]);

  const saveMutation = useMutation({
    mutationFn: async () => {
      if (!target) return;
      await invoke("update_pr_body", {
        organizationId: target.organizationId,
        repoName: target.repoName,
        prNumber: target.prNumber,
        body: draft,
      });
    },
    onSuccess: () => {
      if (!target) return;
      setSavedBody(draft);
      queryClient.invalidateQueries({ queryKey: ["pull-requests"] });
      toast.success(t("issues.detail.toastSaved"));
    },
    onError: (err: unknown) => toast.error(err instanceof Error ? err.message : String(err)),
  });

  return { editor, isDirty, cancel, saveMutation };
}
