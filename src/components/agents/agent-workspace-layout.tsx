import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { AgentHeader } from "./agent-header";
import { AgentTimeline } from "./agent-timeline";
import { DiffViewer } from "./diff-viewer";
import { AgentChatInput } from "./agent-chat-input";
import { AgentStatusBar } from "./agent-status-bar";
import { TerminalPanel } from "./terminal-panel";
import type { AgentIssue, AgentRepository, RepositoryGroup } from "@/types/agents";

import { FileEditor } from "./file-editor";
import { SkillsPage } from "@/pages/skills";
import { SkillDetailsPage } from "@/pages/skill-details";
import { AutomationsPage } from "@/pages/automations";
import { CreateAutomationPage } from "@/pages/create-automation";
import { useEffect } from "react";

export function AgentWorkspaceLayout() {
  const {
    repositoryGroups,
    selectedIssueId,
    timelineSteps,
    fileChanges,
    selectedFilePath,
    activeTab,
    isRightSidebarOpen,
    setIsRightSidebarOpen,
    isTerminalOpen,
    setIsTerminalOpen,
    messages,
    streamingContent,
    isStreaming,
    loadMessages,
  } = useAgentsStore();

  if (activeTab === "skills") {
    return (
      <div className="flex flex-col h-full bg-background w-full">
        <SkillsPage />
      </div>
    );
  }

  if (activeTab === "manage-skill") {
    return (
      <div className="flex flex-col h-full bg-background w-full">
        <SkillDetailsPage />
      </div>
    );
  }

  if (activeTab === "automations") {
    return (
      <div className="flex flex-col h-full bg-background w-full">
        <AutomationsPage />
      </div>
    );
  }

  if (activeTab === "create-automation") {
    return (
      <div className="flex flex-col h-full bg-background w-full text-zinc-300">
        <CreateAutomationPage />
      </div>
    );
  }

  const allIssues = repositoryGroups.flatMap((g: RepositoryGroup) =>
    g.repositories.flatMap((r: AgentRepository) => r.issues)
  );
  const selectedIssue = allIssues.find((i: AgentIssue) => i.id === selectedIssueId);

  // Load persisted messages whenever the active thread changes.
  useEffect(() => {
    if (selectedIssueId) {
      loadMessages(selectedIssueId);
    }
  }, [selectedIssueId, loadMessages]);

  if (!selectedIssue) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center bg-background h-full relative overflow-hidden">
        {/* Decorative Background Element */}
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[500px] h-[500px] bg-primary/5 rounded-full blur-[120px] pointer-events-none" />

        <div className="relative flex flex-col items-center gap-12 z-10">
          {/* Logo Section */}
          <div className="flex flex-col items-center gap-6">
            <div className="relative group">
              <div className="absolute inset-0 bg-primary/20 blur-2xl rounded-2xl group-hover:bg-primary/30 transition-all duration-500" />
              <div className="relative flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-zinc-800 to-zinc-950 border border-white/10 shadow-2xl">
                <div className="absolute inset-0 bg-gradient-to-br from-primary/20 to-transparent opacity-50 rounded-2xl" />
                <span className="relative text-xl font-black text-white tracking-widest bg-clip-text">UD</span>
              </div>
            </div>

            <div className="flex flex-col items-center gap-2">
              <h2 className="text-[22px] font-bold text-white tracking-tight">Unified Dev</h2>
              <p className="text-[13px] text-zinc-500 font-medium max-w-[280px] text-center leading-relaxed">
                Select a repository from the sidebar to launch your agent workspace.
              </p>
            </div>
          </div>

          {/* Shortcuts Grid */}
          <div className="grid grid-cols-1 gap-y-2 w-full max-w-[320px] p-4 rounded-2xl bg-white/[0.02] border border-white/[0.05] backdrop-blur-sm">
            {[
              { keys: ["⌘", "N"], label: "New thread" },
              { keys: ["⌘", "1–9"], label: "Switch workspace" },
              { keys: ["⌘", "B"], label: "Toggle sidebar" },
              { keys: ["⌘", "D"], label: "Toggle diff panel" },
              { keys: ["⌘", "`"], label: "Toggle terminal" },
            ].map((shortcut, i) => (
              <div key={i} className="flex items-center justify-between px-2 py-1.5 group/item">
                <span className="text-[11px] font-medium text-zinc-500 group-hover/item:text-zinc-400 transition-colors">{shortcut.label}</span>
                <div className="flex items-center gap-1">
                  {shortcut.keys.map((key, ki) => (
                    <kbd key={ki} className="min-w-[20px] h-5 px-1.5 flex items-center justify-center rounded bg-white/[0.05] border border-white/[0.1] text-[9px] font-bold text-zinc-400 font-sans uppercase">
                      {key}
                    </kbd>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full bg-background mt-4">
      <div className="flex-1 flex overflow-hidden relative">
        <div className="flex-1 flex flex-col min-w-0 bg-background">
          {!selectedFilePath && <AgentHeader issue={selectedIssue} />}

          <div className="flex-1 overflow-y-auto custom-scrollbar">
            {selectedFilePath ? (
              <FileEditor />
            ) : (
              <div className="max-w-4xl mx-auto py-12">
                <AgentTimeline
                  steps={timelineSteps}
                  messages={messages}
                  streamingContent={streamingContent}
                  isStreaming={isStreaming}
                />
              </div>
            )}
          </div>

          {!selectedFilePath && (
            <div className="max-w-4xl mx-auto w-full">
              <AgentChatInput />
            </div>
          )}
        </div>

        <div
          className={cn(
            "h-full flex shrink-0 border-l border-border/10 transition-all duration-300 ease-in-out overflow-hidden",
            isRightSidebarOpen ? "w-[600px] border-l" : "w-0 border-l-0"
          )}
        >
          <div className="w-[600px] h-full">
            <DiffViewer files={fileChanges} />
          </div>
        </div>
      </div>

      {isTerminalOpen && (
        <div className="h-[260px] shrink-0 border-t border-white/[0.06]">
          <TerminalPanel onClose={() => setIsTerminalOpen(false)} />
        </div>
      )}

      <AgentStatusBar
        branchName={selectedIssue.branchName}
        isRightOpen={isRightSidebarOpen}
        onToggleRight={() => setIsRightSidebarOpen(!isRightSidebarOpen)}
        isTerminalOpen={isTerminalOpen}
        onToggleTerminal={() => setIsTerminalOpen(!isTerminalOpen)}
      />
    </div>
  );
}
