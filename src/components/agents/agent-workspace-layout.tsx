import { useAgentsStore } from "@/stores/useAgentsStore";
import { useNavigationStore } from "@/stores/navigation-store";
import { useI18n } from "@/i18n/i18n";
import { AgentHeader } from "./agent-header";
import { AgentTimeline } from "./agent-timeline";
import { PrMergedBanner } from "./pr-merged-banner";
import { AgentPushPrButton } from "./agent-push-pr-button";
import { AgentDiffIsland } from "./agent-diff-island";
import { PrCiPanel } from "./pr-ci-panel";
import { AgentChatInput } from "./agent-chat-input";
import { AgentStatusBar } from "./agent-status-bar";
import type { AgentIssue, AgentRepository, RepositoryGroup } from "@/types/agents";

import { SkillsPage } from "@/pages/skills";
import { SkillDetailsPage } from "@/pages/skill-details";
import { SkillSourcePage } from "@/pages/skill-source";
import { AutomationsPage } from "@/pages/automations";
import { CreateAutomationPage } from "@/pages/create-automation";
import { McpPage } from "@/pages/mcp";
import { useEffect } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";

export function AgentWorkspaceLayout() {
  const { t } = useI18n();
  const isAgentMode = useNavigationStore((state) => state.isAgentMode);
  const {
    repositoryGroups,
    selectedIssueId,
    timelineSteps,
    fileChanges,
    setSelectedFilePath,
    activeTab,
    isRightSidebarOpen,
    setIsRightSidebarOpen,
    diffViewTab,
    setDiffViewTab,
    islandPanel,
    setIslandPanel,
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

  useEffect(() => {
    if (!isAgentMode) return;
    const onKey = (e: KeyboardEvent) => {
      const mod = e.metaKey || e.ctrlKey;
      const toggleDiff = (tab: "changes" | "files") => {
        e.preventDefault();
        if (isRightSidebarOpen && islandPanel === "diff" && diffViewTab === tab) setIsRightSidebarOpen(false);
        else { setIslandPanel("diff"); setDiffViewTab(tab); setIsRightSidebarOpen(true); }
      };
      if (mod && e.shiftKey && e.key.toLowerCase() === "d") { toggleDiff("changes"); return; }
      if (mod && e.shiftKey && e.key.toLowerCase() === "f") { toggleDiff("files"); return; }
      if (e.ctrlKey && e.key === "`") {
        e.preventDefault();
        if (isRightSidebarOpen && islandPanel === "terminal") setIsRightSidebarOpen(false);
        else { setIslandPanel("terminal"); setIsRightSidebarOpen(true); }
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [isAgentMode, isRightSidebarOpen, islandPanel, diffViewTab, setIsRightSidebarOpen, setDiffViewTab, setIslandPanel]);

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

  useEffect(() => {
    if (!isAgentMode) return;
    const workspacePath = selectedIssue?.workspacePath;
    if (!workspacePath) return;
    const unlisten = getCurrentWindow().onFocusChanged(({ payload: focused }) => {
      if (focused) loadFileChanges(workspacePath);
    });
    return () => { void unlisten.then((fn) => fn()); };
  }, [isAgentMode, selectedIssue?.workspacePath, loadFileChanges]);

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
    <div className="flex flex-col h-full bg-background">
      <div className="flex-1 flex overflow-hidden relative">
        <div className="flex-1 flex flex-col min-w-0 bg-background">
          <AgentHeader issue={selectedIssue} />

          <div className="flex-1 flex flex-col overflow-hidden max-w-5xl mx-auto w-full px-6">
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
              <AgentPushPrButton
                threadId={selectedIssue.id}
                workspacePath={selectedIssue.workspacePath}
                branchName={selectedIssue.branchName}
                title={selectedIssue.title}
                className="mb-3"
              />
              <AgentChatInput />
            </div>
          </div>
        </div>

        {isRightSidebarOpen && islandPanel === "ci" ? (
          <PrCiPanel
            threadId={selectedIssue.id}
            onClose={() => setIsRightSidebarOpen(false)}
          />
        ) : isRightSidebarOpen ? (
          <AgentDiffIsland
            branchName={selectedIssue.branchName}
            files={fileChanges}
            workspacePath={selectedIssue.workspacePath}
            onClose={() => { setIsRightSidebarOpen(false); setSelectedFilePath(null); }}
          />
        ) : null}
      </div>

      <AgentStatusBar
        branchName={selectedIssue.branchName}
        toolCallCount={toolCalls.length}
        isRightOpen={isRightSidebarOpen}
        onToggleRight={() => setIsRightSidebarOpen(!isRightSidebarOpen)}
        isTerminalOpen={isRightSidebarOpen && islandPanel === "terminal"}
        onToggleTerminal={() => {
          if (isRightSidebarOpen && islandPanel === "terminal") setIsRightSidebarOpen(false);
          else { setIslandPanel("terminal"); setIsRightSidebarOpen(true); }
        }}
      />
    </div>
  );
}
