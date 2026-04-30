import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useNavigationStore } from "@/stores/navigation-store";
import { useI18n } from "@/i18n/i18n";
import { AgentHeader } from "./agent-header";
import { AgentTimeline } from "./agent-timeline";
import { PrCiCard } from "./pr-ci-card";
import { PrMergedBanner } from "./pr-merged-banner";
import { DiffViewer } from "./diff-viewer";
import { AgentChatInput } from "./agent-chat-input";
import { AgentStatusBar } from "./agent-status-bar";
import { TerminalPanel } from "./terminal-panel";
import type { AgentIssue, AgentRepository, RepositoryGroup } from "@/types/agents";

import { FileEditor } from "./file-editor";
import { SkillsPage } from "@/pages/skills";
import { SkillDetailsPage } from "@/pages/skill-details";
import { SkillSourcePage } from "@/pages/skill-source";
import { AutomationsPage } from "@/pages/automations";
import { CreateAutomationPage } from "@/pages/create-automation";
import { McpPage } from "@/pages/mcp";
import { useEffect, useRef, useState, useCallback } from "react";

const DIFF_MIN_WIDTH = 280;
const DIFF_MAX_WIDTH = 900;
const DIFF_DEFAULT_WIDTH = 500;
const CHAT_MIN_WIDTH = 500;
const TERMINAL_MIN_HEIGHT = 100;
const TERMINAL_MAX_HEIGHT = 600;
const TERMINAL_DEFAULT_HEIGHT = 260;

export function AgentWorkspaceLayout() {
  const { t } = useI18n();
  const isAgentMode = useNavigationStore((state) => state.isAgentMode);
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
    messagesByThread,
    messagesLoadingByThread,
    streamingContentByThread,
    streamingThreadIds,
    toolCallsByThread,
    loadMessages,
    loadFileChanges,
    loadPrUrl,
    repositoriesLoaded,
  } = useAgentsStore();

  const [diffWidth, setDiffWidth] = useState(DIFF_DEFAULT_WIDTH);
  const isDragging = useRef(false);
  const [isResizing, setIsResizing] = useState(false);
  const [terminalHeight, setTerminalHeight] = useState(TERMINAL_DEFAULT_HEIGHT);
  const isTerminalDragging = useRef(false);
  const [isTerminalMounted, setIsTerminalMounted] = useState(false);

  const onTerminalResizeMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    isTerminalDragging.current = true;
    document.body.style.cursor = "row-resize";
    document.body.style.userSelect = "none";

    const onMouseMove = (ev: MouseEvent) => {
      if (!isTerminalDragging.current) return;
      const next = Math.min(TERMINAL_MAX_HEIGHT, Math.max(TERMINAL_MIN_HEIGHT, window.innerHeight - ev.clientY));
      setTerminalHeight(next);
    };

    const onMouseUp = () => {
      isTerminalDragging.current = false;
      document.body.style.cursor = "";
      document.body.style.userSelect = "";
      window.removeEventListener("mousemove", onMouseMove);
      window.removeEventListener("mouseup", onMouseUp);
    };

    window.addEventListener("mousemove", onMouseMove);
    window.addEventListener("mouseup", onMouseUp);
  }, []);

  const handleToggleTerminal = useCallback(() => {
    if (!isTerminalMounted) {
      setIsTerminalMounted(true);
      setIsTerminalOpen(true);
    } else if (isTerminalOpen) {
      setIsTerminalOpen(false);
    } else {
      setIsTerminalOpen(true);
    }
  }, [isTerminalMounted, isTerminalOpen, setIsTerminalOpen]);

  const onMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    isDragging.current = true;
    setIsResizing(true);
    document.body.style.cursor = "col-resize";
    document.body.style.userSelect = "none";

    const onMouseMove = (ev: MouseEvent) => {
      if (!isDragging.current) return;
      const maxAllowed = window.innerWidth - CHAT_MIN_WIDTH;
      const next = Math.min(DIFF_MAX_WIDTH, Math.max(DIFF_MIN_WIDTH, Math.min(maxAllowed, window.innerWidth - ev.clientX)));
      setDiffWidth(next);
    };

    const onMouseUp = () => {
      isDragging.current = false;
      setIsResizing(false);
      document.body.style.cursor = "";
      document.body.style.userSelect = "";
      window.removeEventListener("mousemove", onMouseMove);
      window.removeEventListener("mouseup", onMouseUp);
    };

    window.addEventListener("mousemove", onMouseMove);
    window.addEventListener("mouseup", onMouseUp);
  }, []);

  const isCurrentThreadStreaming = !!streamingThreadIds[selectedIssueId ?? ""];
  const streamingContent = streamingContentByThread[selectedIssueId ?? ""] ?? "";
  const toolCalls = toolCallsByThread[selectedIssueId ?? ""] ?? [];
  const messages = messagesByThread[selectedIssueId ?? ""] ?? [];
  const messagesLoading = !!(selectedIssueId && messagesLoadingByThread[selectedIssueId]);

  const allIssues = repositoryGroups.flatMap((g: RepositoryGroup) =>
    g.repositories.flatMap((r: AgentRepository) => r.issues)
  );
  const selectedIssue = allIssues.find((i: AgentIssue) => i.id === selectedIssueId);

  useEffect(() => {
    if (!isAgentMode) return;
    if (!repositoriesLoaded) return;
    if (selectedIssueId) {
      if (!streamingThreadIds[selectedIssueId]) {
        loadMessages(selectedIssueId);
      }
      const issue = allIssues.find((i: AgentIssue) => i.id === selectedIssueId);
      if (issue?.workspacePath) {
        loadFileChanges(issue.workspacePath);
        loadPrUrl(selectedIssueId, issue.workspacePath);
      }
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isAgentMode, selectedIssueId, repositoriesLoaded, loadMessages, loadFileChanges, loadPrUrl]);

  useEffect(() => {
    if (!isAgentMode) return;
    if (!isCurrentThreadStreaming) return;
    const workspacePath = selectedIssue?.workspacePath;
    if (!workspacePath) return;

    const interval = setInterval(() => {
      loadFileChanges(workspacePath);
    }, 3000);

    return () => clearInterval(interval);
  }, [isCurrentThreadStreaming, selectedIssue?.workspacePath, loadFileChanges]);

  if (activeTab === "skills") {
    return (
      <div className="flex flex-col h-full bg-background w-full">
        <SkillsPage />
      </div>
    );
  }

  if (activeTab === "mcp") {
    return (
      <div className="flex flex-col h-full bg-background w-full">
        <McpPage />
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

  if (activeTab === "skill-source") {
    return (
      <div className="flex flex-col h-full bg-background w-full">
        <SkillSourcePage />
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

  if (!selectedIssue) {
    if (!repositoriesLoaded && selectedIssueId) {
      // Repos still loading — show skeletons only briefly
      return (
        <div className="flex flex-col h-full bg-background pt-4">
          <div className="flex-1 flex overflow-hidden relative">
            <div className="flex-1 flex flex-col min-w-0 bg-background">
              <div className="flex-1 flex flex-col overflow-hidden max-w-5xl mx-auto w-full px-6">
                <div className="flex-1 overflow-y-auto py-8" style={{ scrollbarWidth: "none" }}>
                  <AgentTimeline
                    steps={[]}
                    messages={[]}
                    streamingContent=""
                    isStreaming={false}
                    toolCalls={[]}
                    isLoadingMessages={true}
                  />
                </div>
              </div>
            </div>
          </div>
        </div>
      );
    }

    // repositoriesLoaded=true but no matching thread — stale selectedIssueId, show splash
    return (
      <div className="flex-1 flex flex-col items-center justify-center bg-background h-full relative overflow-hidden">
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[500px] h-[500px] bg-primary/5 rounded-full blur-[120px] pointer-events-none" />

        <div className="flex flex-col items-center gap-6 z-10">
          <div className="relative group">
            <div className="absolute inset-0 bg-primary/20 blur-2xl rounded-2xl group-hover:bg-primary/30 transition-all duration-500" />
            <div className="relative flex h-16 w-16 items-center justify-center rounded-2xl overflow-hidden shadow-2xl">
              <img src="/app-icon.svg" alt="Akira" className="h-16 w-16 object-cover" />
            </div>
          </div>

          <div className="flex flex-col items-center gap-2">
            <h2 className="text-[22px] font-bold text-white tracking-tight">{t("app.name")}</h2>
            <p className="text-[13px] text-zinc-500 font-medium max-w-[280px] text-center leading-relaxed">
              {t("agents.workspace.emptyDescription")}
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full bg-background pt-4">
      <div className="flex-1 flex overflow-hidden relative">
        <div className="flex-1 flex flex-col min-w-0 bg-background">
          {!selectedFilePath && <AgentHeader issue={selectedIssue} />}

          {selectedFilePath ? (
            <div className="flex-1 overflow-y-auto custom-scrollbar">
              <FileEditor />
            </div>
          ) : (
            <div className="flex-1 flex flex-col overflow-hidden max-w-5xl mx-auto w-full px-6">
              <PrCiCard threadId={selectedIssue.id} className="mt-3" />
              <div className="flex-1 overflow-y-auto py-8" style={{ scrollbarWidth: "none" }}>
                <AgentTimeline
                  steps={timelineSteps}
                  messages={messages}
                  streamingContent={streamingContent}
                  isStreaming={isCurrentThreadStreaming}
                  toolCalls={toolCalls}
                  isLoadingMessages={messagesLoading}
                />
              </div>
              <div className="shrink-0 pb-6 pt-2">
                <PrMergedBanner threadId={selectedIssue.id} threadTitle={selectedIssue.title} className="mb-3" />
                <AgentChatInput />
              </div>
            </div>
          )}
        </div>

        <div
          className={cn(
            "h-full flex shrink-0 overflow-hidden",
            !isResizing && "transition-all duration-300 ease-in-out",
            isRightSidebarOpen ? "border-l border-border/10" : "w-0"
          )}
          style={isRightSidebarOpen ? { width: diffWidth } : undefined}
        >
          {isRightSidebarOpen && (
            <div
              className="w-1 h-full cursor-col-resize shrink-0 group relative"
              onMouseDown={onMouseDown}
            >
              <div className="absolute inset-y-0 left-0 w-1 group-hover:bg-purple-500/40 group-active:bg-purple-500/60 transition-colors" />
            </div>
          )}
          <div className="flex-1 h-full min-w-0">
            <DiffViewer files={fileChanges} />
          </div>
        </div>
      </div>

      {isTerminalMounted && (
        <div
          className={cn(
            "shrink-0 relative",
            isTerminalOpen ? "border-t border-white/[0.06]" : "h-0 overflow-hidden"
          )}
          style={isTerminalOpen ? { height: terminalHeight } : undefined}
        >
          {isTerminalOpen && (
            <div
              className="absolute top-0 left-0 right-0 h-1 cursor-row-resize group z-10"
              onMouseDown={onTerminalResizeMouseDown}
            >
              <div className="absolute inset-x-0 top-0 h-1 group-hover:bg-purple-500/40 group-active:bg-purple-500/60 transition-colors" />
            </div>
          )}
          <TerminalPanel
            onMinimize={() => setIsTerminalOpen(false)}
            onClose={() => { setIsTerminalOpen(false); setIsTerminalMounted(false); }}
            cwd={selectedIssue.workspacePath}
          />
        </div>
      )}

      <AgentStatusBar
        branchName={selectedIssue.branchName}
        toolCallCount={toolCalls.length}
        isRightOpen={isRightSidebarOpen}
        onToggleRight={() => setIsRightSidebarOpen(!isRightSidebarOpen)}
        isTerminalOpen={isTerminalOpen}
        onToggleTerminal={handleToggleTerminal}
      />
    </div>
  );
}
