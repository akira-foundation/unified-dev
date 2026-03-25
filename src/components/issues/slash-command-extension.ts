import { Extension } from "@tiptap/react";
import Suggestion, { type SuggestionOptions } from "@tiptap/suggestion";
import type { Editor } from "@tiptap/react";

export interface SlashCommandItem {
  id: string;
  title: string;
  icon: string;
  command: (editor: Editor) => void;
}

export const SLASH_COMMANDS: SlashCommandItem[] = [
  {
    id: "heading1",
    title: "Heading 1",
    icon: "H1",
    command: (editor) => editor.chain().focus().toggleHeading({ level: 1 }).run(),
  },
  {
    id: "heading2",
    title: "Heading 2",
    icon: "H2",
    command: (editor) => editor.chain().focus().toggleHeading({ level: 2 }).run(),
  },
  {
    id: "heading3",
    title: "Heading 3",
    icon: "H3",
    command: (editor) => editor.chain().focus().toggleHeading({ level: 3 }).run(),
  },
  {
    id: "bulletList",
    title: "Bulleted list",
    icon: "ul",
    command: (editor) => editor.chain().focus().toggleBulletList().run(),
  },
  {
    id: "orderedList",
    title: "Numbered list",
    icon: "ol",
    command: (editor) => editor.chain().focus().toggleOrderedList().run(),
  },
  {
    id: "taskList",
    title: "Checklist",
    icon: "check",
    command: (editor) => editor.chain().focus().toggleTaskList().run(),
  },
  {
    id: "codeBlock",
    title: "Code block",
    icon: "code",
    command: (editor) => editor.chain().focus().toggleCodeBlock().run(),
  },
  {
    id: "blockquote",
    title: "Blockquote",
    icon: "quote",
    command: (editor) => editor.chain().focus().toggleBlockquote().run(),
  },
  {
    id: "bold",
    title: "Bold",
    icon: "bold",
    command: (editor) => editor.chain().focus().toggleBold().run(),
  },
  {
    id: "italic",
    title: "Italic",
    icon: "italic",
    command: (editor) => editor.chain().focus().toggleItalic().run(),
  },
  {
    id: "strike",
    title: "Strikethrough",
    icon: "strike",
    command: (editor) => editor.chain().focus().toggleStrike().run(),
  },
  {
    id: "hr",
    title: "Divider",
    icon: "hr",
    command: (editor) => editor.chain().focus().setHorizontalRule().run(),
  },
];

export type SlashSuggestionOptions = Omit<SuggestionOptions, "editor">;

export const SlashCommandExtension = Extension.create<{
  suggestion: Partial<SlashSuggestionOptions>;
}>({
  name: "slashCommand",

  addOptions() {
    return {
      suggestion: {
        char: "/",
        startOfLine: false,
        command({ editor, range, props }: { editor: Editor; range: { from: number; to: number }; props: SlashCommandItem }) {
          editor.chain().focus().deleteRange(range).run();
          props.command(editor);
        },
      },
    };
  },

  addProseMirrorPlugins() {
    return [
      Suggestion({
        editor: this.editor,
        ...this.options.suggestion,
      }),
    ];
  },
});
