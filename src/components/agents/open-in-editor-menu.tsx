import type { ReactNode } from "react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

const EDITORS: Array<{ label: string; app: string }> = [
  { label: "VS Code", app: "Visual Studio Code" },
  { label: "Cursor", app: "Cursor" },
  { label: "Zed", app: "Zed" },
  { label: "PhpStorm", app: "PhpStorm" },
  { label: "WebStorm", app: "WebStorm" },
  { label: "IntelliJ IDEA", app: "IntelliJ IDEA" },
  { label: "RustRover", app: "RustRover" },
  { label: "Sublime Text", app: "Sublime Text" },
  { label: "Xcode", app: "Xcode" },
];

interface OpenInEditorMenuProps {
  trigger: ReactNode;
  workspacePath?: string | null;
  filePath: string;
}

export function OpenInEditorMenu({ trigger, workspacePath, filePath }: OpenInEditorMenuProps) {
  const open = async (app: string) => {
    if (!workspacePath) return;
    try {
      await invoke("open_in_editor", { app, path: `${workspacePath}/${filePath}` });
    } catch (error) {
      toast.error(String(error));
    }
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>{trigger}</DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-48">
        {EDITORS.map((editor) => (
          <DropdownMenuItem key={editor.app} onSelect={() => void open(editor.app)}>
            {editor.label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
