import { useEffect } from "react";
import { useEditor, ReactRenderer } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import Placeholder from "@tiptap/extension-placeholder";
import TaskList from "@tiptap/extension-task-list";
import TaskItem from "@tiptap/extension-task-item";
import { Markdown } from "tiptap-markdown";
import tippy, { type Instance as TippyInstance } from "tippy.js";

import { SlashCommandExtension, SLASH_COMMANDS } from "@/components/issues/slash-command-extension";
import { SlashCommandMenu, type SlashCommandMenuRef } from "@/components/issues/slash-command-menu";

interface UseIssueComposerEditorOptions {
  placeholder: string;
  open: boolean;
  recreateKey: unknown;
  onChange: (markdown: string) => void;
}

export function useIssueComposerEditor({ placeholder, open, recreateKey, onChange }: UseIssueComposerEditorOptions) {
  const editor = useEditor(
    {
      extensions: [
        StarterKit,
        Placeholder.configure({ placeholder }),
        TaskList.configure({ HTMLAttributes: { class: "issue-task-list" } }),
        TaskItem.configure({ nested: true, HTMLAttributes: { class: "issue-task-item" } }),
        Markdown.configure({ transformPastedText: true }),
        SlashCommandExtension.configure({
          suggestion: {
            items: ({ query }: { query: string }) =>
              SLASH_COMMANDS.filter((item) => item.title.toLowerCase().includes(query.toLowerCase())),
            render() {
              let renderer: ReactRenderer<any>;
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
            },
          },
        }),
      ],
      editorProps: { attributes: { class: "outline-none" } },
      onUpdate({ editor: e }) {
        // @ts-expect-error - tiptap-markdown adds getMarkdown to editor storage
        const md: string = e.storage.markdown?.getMarkdown?.() ?? e.getText();
        onChange(md);
      },
    },
    [recreateKey],
  );

  useEffect(() => {
    if (!open && editor) editor.commands.clearContent();
  }, [open, editor]);

  return editor;
}
