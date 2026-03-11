import { GitBranch, Wrench, MonitorCog, Terminal, PanelLeft, PanelRight } from "lucide-react";
import { cn } from "@/lib/utils";
import { useSidebar } from "@/components/ui/sidebar";

interface AgentStatusBarProps {
  branchName: string;
  isRightOpen: boolean;
  onToggleRight: () => void;
  isTerminalOpen?: boolean;
  onToggleTerminal?: () => void;
}

export function AgentStatusBar({
  branchName,
  isRightOpen,
  onToggleRight,
  isTerminalOpen = false,
  onToggleTerminal,
}: AgentStatusBarProps) {
  const { toggleSidebar } = useSidebar();

  return (
    <div className="h-10 border-t border-white/[0.05] bg-background flex items-center px-4 justify-between select-none">
      <div className="flex items-center gap-6">
        <button
          onClick={toggleSidebar}
          className="flex items-center justify-center text-muted-foreground/40 hover:text-foreground transition-colors"
        >
          <PanelLeft className="h-4 w-4" />
        </button>

        <div className="flex items-center gap-2">
          <div className="w-1.5 h-1.5 rounded-full bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.4)]" />
          <span className="text-[11px] font-medium text-muted-foreground/60">Connected</span>
        </div>

        <div className="flex items-center gap-2 text-muted-foreground/40">
          <GitBranch className="h-3.5 w-3.5" />
          <span className="text-[11px] font-medium truncate max-w-[200px]">{branchName}</span>
        </div>

        <div className="flex items-center gap-2 text-muted-foreground/40">
          <Wrench className="h-3.5 w-3.5" />
          <span className="text-[11px] font-medium">26 tool calls</span>
        </div>
      </div>

      <div className="flex items-center gap-6">
        <div className="flex items-center gap-6">
          <button className="flex items-center gap-2 text-[11px] font-medium text-muted-foreground/40 hover:text-foreground transition-colors group">
            <MonitorCog className="h-3.5 w-3.5" />
            <span>Mobile Remote</span>
          </button>
          <button
            onClick={onToggleTerminal}
            className={cn(
              "flex items-center gap-2 text-[11px] font-medium transition-colors group",
              isTerminalOpen
                ? "text-purple-400"
                : "text-muted-foreground/40 hover:text-foreground"
            )}
          >
            <Terminal className="h-3.5 w-3.5" />
            <span>Terminal</span>
          </button>
        </div>

        <button
          onClick={onToggleRight}
          className={cn(
            "flex items-center justify-center transition-colors",
            isRightOpen
              ? "text-purple-400"
              : "text-muted-foreground/40 hover:text-foreground"
          )}
        >
          <PanelRight className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}
