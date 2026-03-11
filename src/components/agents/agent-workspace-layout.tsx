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
    setIsTerminalOpen
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

  if (!selectedIssue) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center bg-[#0c0c0c] h-full gap-10">
        <div className="flex flex-col items-center gap-5">
          <div className="flex items-center gap-4">
            <div className="relative">
              <div className="absolute inset-0 bg-primary/30 blur-xl rounded-full" />
              <div className="relative flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-primary to-purple-600 text-white font-black text-sm shadow-lg shadow-primary/20">
                UD
              </div>
            </div>
            <span className="text-[28px] font-bold text-white tracking-[0.12em] uppercase">Unified Dev</span>
          </div>
          <p className="text-[13px] text-zinc-500">Add a repository and start your first agent thread.</p>
        </div>

        <div className="flex flex-col gap-3.5">
          <div className="flex items-center gap-5">
            <div className="flex items-center gap-1.5 min-w-[100px] justify-end">
              <kbd className="h-6 px-2 flex items-center justify-center rounded bg-white/5 border border-white/10 text-[11px] font-medium text-white/40">⌘</kbd>
              <kbd className="h-6 px-2 flex items-center justify-center rounded bg-white/5 border border-white/10 text-[11px] font-medium text-white/40">N</kbd>
            </div>
            <span className="text-[13px] text-zinc-500">New workspace</span>
          </div>

          <div className="flex items-center gap-5">
            <div className="flex items-center gap-1.5 min-w-[100px] justify-end">
              <kbd className="h-6 px-2 flex items-center justify-center rounded bg-white/5 border border-white/10 text-[11px] font-medium text-white/40">⌘</kbd>
              <kbd className="h-6 px-2 flex items-center justify-center rounded bg-white/5 border border-white/10 text-[11px] font-medium text-white/40">1–9</kbd>
            </div>
            <span className="text-[13px] text-zinc-500">Switch workspace</span>
          </div>

          <div className="flex items-center gap-5">
            <div className="min-w-[100px] flex justify-end">
              <kbd className="h-6 px-2.5 flex items-center justify-center rounded bg-white/5 border border-white/10 text-[11px] font-medium text-white/40">⌘B</kbd>
            </div>
            <span className="text-[13px] text-zinc-500">Toggle sidebar</span>
          </div>

          <div className="flex items-center gap-5">
            <div className="min-w-[100px] flex justify-end">
              <kbd className="h-6 px-2.5 flex items-center justify-center rounded bg-white/5 border border-white/10 text-[11px] font-medium text-white/40">⌘D</kbd>
            </div>
            <span className="text-[13px] text-zinc-500">Toggle diff panel</span>
          </div>

          <div className="flex items-center gap-5">
            <div className="min-w-[100px] flex justify-end">
              <kbd className="h-6 px-2.5 flex items-center justify-center rounded bg-white/5 border border-white/10 text-[11px] font-medium text-white/40">⌘`</kbd>
            </div>
            <span className="text-[13px] text-zinc-500">Toggle terminal</span>
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
                <AgentTimeline steps={timelineSteps} />
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
