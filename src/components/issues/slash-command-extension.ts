import { Extension } from "@tiptap/react";
import Suggestion, { type SuggestionOptions } from "@tiptap/suggestion";
import type { Editor } from "@tiptap/react";

export interface SlashCommandItem {
  id: string;
  title: string;
  group: string;
  icon: string;
  description?: string;
  shortcut?: string;
  command: (editor: Editor) => void;
}

export const SLASH_COMMANDS: SlashCommandItem[] = [
  {
    id: "heading1",
    title: "Heading 1",
    group: "Text",
    icon: "H1",
    description: "Large section heading",
    shortcut: "Cmd+Opt+1",
    command: (editor) => editor.chain().focus().toggleHeading({ level: 1 }).run(),
  },
  {
    id: "heading2",
    title: "Heading 2",
    group: "Text",
    icon: "H2",
    description: "Medium section heading",
    shortcut: "Cmd+Opt+2",
    command: (editor) => editor.chain().focus().toggleHeading({ level: 2 }).run(),
  },
  {
    id: "heading3",
    title: "Heading 3",
    group: "Text",
    icon: "H3",
    description: "Small section heading",
    shortcut: "Cmd+Opt+3",
    command: (editor) => editor.chain().focus().toggleHeading({ level: 3 }).run(),
  },
  {
    id: "bulletList",
    title: "Bulleted",
    group: "Lists",
    icon: "ul",
    description: "Create an unordered list",
    shortcut: "Cmd+Shift+8",
    command: (editor) => editor.chain().focus().toggleBulletList().run(),
  },
  {
    id: "orderedList",
    title: "Numbered",
    group: "Lists",
    icon: "ol",
    description: "Create an ordered list",
    shortcut: "Cmd+Shift+7",
    command: (editor) => editor.chain().focus().toggleOrderedList().run(),
  },
  {
    id: "taskList",
    title: "Checklist",
    group: "Lists",
    icon: "check",
    description: "Track tasks with checkboxes",
    command: (editor) => editor.chain().focus().toggleTaskList().run(),
  },
  {
    id: "codeBlock",
    title: "Code block",
    group: "Insert",
    icon: "code",
    description: "Insert a fenced code block",
    shortcut: "Cmd+Opt+C",
    command: (editor) => editor.chain().focus().toggleCodeBlock().run(),
  },
  {
    id: "blockquote",
    title: "Quote",
    group: "Insert",
    icon: "quote",
    description: "Highlight quoted content",
    command: (editor) => editor.chain().focus().toggleBlockquote().run(),
  },
  {
    id: "bold",
    title: "Bold",
    group: "Format",
    icon: "bold",
    description: "Emphasize selected text",
    shortcut: "Cmd+B",
    command: (editor) => editor.chain().focus().toggleBold().run(),
  },
  {
    id: "italic",
    title: "Italic",
    group: "Format",
    icon: "italic",
    description: "Italicize selected text",
    shortcut: "Cmd+I",
    command: (editor) => editor.chain().focus().toggleItalic().run(),
  },
  {
    id: "strike",
    title: "Strikethrough",
    group: "Format",
    icon: "strike",
    description: "Strike through selected text",
    shortcut: "Cmd+Shift+S",
    command: (editor) => editor.chain().focus().toggleStrike().run(),
  },
  {
    id: "hr",
    title: "Divider",
    group: "Insert",
    icon: "hr",
    description: "Insert a horizontal divider",
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
