export interface SlashCommand {
  id: string;
  label: string;
  description: string;
  icon?: string;
}

export const slashCommands: SlashCommand[] = [
  { id: "clear", label: "/clear", description: "Clear the current conversation" },
  { id: "help",  label: "/help",  description: "Show available commands and shortcuts" },
  { id: "tree",  label: "/tree",  description: "Show the project file tree in chat" },
  { id: "diff",  label: "/diff",  description: "Show current git diff" },
  { id: "branch", label: "/branch", description: "Show current branch and status" },
];
