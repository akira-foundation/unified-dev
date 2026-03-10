import { useState } from "react";
import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { AgentHeader } from "./agent-header";
import { AgentTimeline } from "./agent-timeline";
import { DiffViewer } from "./diff-viewer";
import { AgentChatInput } from "./agent-chat-input";
import { AgentStatusBar } from "./agent-status-bar";
import type { AgentIssue, AgentRepository, RepositoryGroup } from "@/types/agents";

import { FileEditor } from "./file-editor";
import { SkillsPage } from "@/pages/skills";

export function AgentWorkspaceLayout() {
  const { repositoryGroups, selectedIssueId, timelineSteps, fileChanges, selectedFilePath, activeTab } = useAgentsStore();
  const [isRightSidebarOpen, setIsRightSidebarOpen] = useState(true);

  if (activeTab === "skills") {
    return (
      <div className="flex flex-col h-full bg-[#080808] w-full">
        <SkillsPage />
      </div>
    );
  }

  // Find the selected issue
  const allIssues = repositoryGroups.flatMap((g: RepositoryGroup) =>
    g.repositories.flatMap((r: AgentRepository) => r.issues)
  );
  const selectedIssue = allIssues.find((i: AgentIssue) => i.id === selectedIssueId);

  if (!selectedIssue) {
    return (
      <div className="flex-1 flex items-center justify-center text-muted-foreground opacity-20">
        <span className="text-xl font-bold uppercase tracking-[0.3em]">Select an AI Task</span>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full bg-zinc-50 dark:bg-zinc-950/20">
      <div className="flex-1 flex overflow-hidden relative">
        {/* Center Panel: Header, Timeline & Chat (or Editor) */}
        <div className="flex-1 flex flex-col min-w-0 bg-[#080808]">
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

          {!selectedFilePath && <AgentChatInput />}
        </div>

        {/* Right Panel: Diff / Files (Collapsible & 100% Height) */}
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

      <AgentStatusBar
        branchName={selectedIssue.branchName}
        isRightOpen={isRightSidebarOpen}
        onToggleRight={() => setIsRightSidebarOpen(!isRightSidebarOpen)}
      />
    </div>
  );
}
