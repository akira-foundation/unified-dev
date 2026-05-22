import { Check, FileDiff, Files, ListChecks, ListTodo, PanelRight, Play, TerminalSquare } from "lucide-react";
import type { ElementType } from "react";

import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuShortcut,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useAgentsStore } from "@/stores/useAgentsStore";

function PanelItem({
  icon: Icon,
  label,
  active,
  shortcut,
  soon,
  onSelect,
}: {
  icon: ElementType;
  label: string;
  active?: boolean;
  shortcut?: string;
  soon?: boolean;
  onSelect?: () => void;
}) {
  return (
    <DropdownMenuItem disabled={soon} onSelect={() => onSelect?.()} className="gap-2.5">
      <Icon className="h-4 w-4 text-muted-foreground" />
      <span>{label}</span>
      {soon ? (
        <span className="ml-auto rounded border border-muted-foreground/20 px-1 py-0.5 text-[9px] font-semibold uppercase tracking-wider text-muted-foreground/60">
          Soon
        </span>
      ) : active ? (
        <Check className="ml-auto h-4 w-4 text-purple-500" />
      ) : shortcut ? (
        <DropdownMenuShortcut>{shortcut}</DropdownMenuShortcut>
      ) : null}
    </DropdownMenuItem>
  );
}

export function AgentPanelSelector() {
  const {
    isRightSidebarOpen,
    setIsRightSidebarOpen,
    diffViewTab,
    setDiffViewTab,
    islandPanel,
    setIslandPanel,
  } = useAgentsStore();

  const diffActive = isRightSidebarOpen && islandPanel === "diff" && diffViewTab === "changes";
  const filesActive = isRightSidebarOpen && islandPanel === "diff" && diffViewTab === "files";
  const terminalActive = isRightSidebarOpen && islandPanel === "terminal";

  const openDiff = (tab: "changes" | "files") => {
    if (isRightSidebarOpen && islandPanel === "diff" && diffViewTab === tab) {
      setIsRightSidebarOpen(false);
      return;
    }
    setIslandPanel("diff");
    setDiffViewTab(tab);
    setIsRightSidebarOpen(true);
  };

  const openTerminal = () => {
    if (isRightSidebarOpen && islandPanel === "terminal") {
      setIsRightSidebarOpen(false);
      return;
    }
    setIslandPanel("terminal");
    setIsRightSidebarOpen(true);
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="icon-sm">
          <PanelRight className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className={cn("w-56")}>
        <PanelItem icon={Play} label="Preview" shortcut="⇧⌘P" soon />
        <PanelItem icon={FileDiff} label="Diff" shortcut="⇧⌘D" active={diffActive} onSelect={() => openDiff("changes")} />
        <PanelItem icon={TerminalSquare} label="Terminal" shortcut="^`" active={terminalActive} onSelect={openTerminal} />
        <PanelItem icon={Files} label="Files" shortcut="⇧⌘F" active={filesActive} onSelect={() => openDiff("files")} />
        <PanelItem icon={ListChecks} label="Background tasks" soon />
        <PanelItem icon={ListTodo} label="Plan" soon />
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
