import * as React from "react";
import {
  Plus,
  Zap,
  Lightbulb,
  History,

  PanelRight,
  GitBranch,
  ChevronRight,
  Monitor,
  FileCode,
  Terminal,
  Bot
} from "lucide-react";
import { CommandGroup, CommandItem, CommandSeparator, CommandShortcut } from "@/components/ui/command";
import { useNavigationStore } from "@/stores/navigation-store";
import { useAgentsStore } from "@/stores/useAgentsStore";
import type { CommandPage } from "../layout/command-palette";

interface AgentCommanderProps {
  runCommand: (command: () => void) => void;
  currentPage: CommandPage;
  setPage: (page: CommandPage) => void;
}

export function AgentCommander({ runCommand, currentPage, setPage }: AgentCommanderProps) {
  const { navigateTo, setIsAgentMode, isAgentMode, currentPage: appCurrentPage } = useNavigationStore();
  const {
    repositoryGroups,
    selectedIssueId,
    setSelectedIssueId,
    fileChanges,
    setSelectedFilePath,
    setActiveTab,
    setShowAddRepositoryDialog,
    isRightSidebarOpen,
    setIsRightSidebarOpen,
    setDiffViewTab,
    setExpandedRepos,
    islandPanel,
    setIslandPanel
  } = useAgentsStore();

  const allThreads = React.useMemo(() => {
    return repositoryGroups.flatMap(g =>
      g.repositories.flatMap(r =>
        r.issues.map(i => ({
          ...i,
          repoName: r.name,
          repoId: r.id
        }))
      )
    );
  }, [repositoryGroups]);

  const selectedThread = React.useMemo(() => {
    return allThreads.find(t => t.id === selectedIssueId);
  }, [allThreads, selectedIssueId]);

  if (appCurrentPage === "dashboard" && currentPage === "root") return null;

  if (currentPage === "root") {
    return (
      <>
        <CommandGroup heading="Agent Management">
          <CommandItem onSelect={() => runCommand(() => setShowAddRepositoryDialog(true))}>
            <Plus className="mr-2 h-4 w-4 text-purple-400" />
            <span>Add Repository</span>
          </CommandItem>
          <CommandItem onSelect={() => setPage("agents")}>
            <div className="flex items-center gap-3">
              <Bot className="h-4 w-4 text-zinc-400" />
              <span>Agent Threads</span>
            </div>
            <div className="ml-auto flex items-center gap-2">
              <span className="text-[10px] text-zinc-500 font-medium tabular-nums">{allThreads.length}</span>
              <ChevronRight className="h-3 w-3 opacity-40" />
            </div>
          </CommandItem>
          <CommandItem onSelect={() => setPage("skills")}>
            <div className="flex items-center gap-3">
              <Lightbulb className="h-4 w-4 text-zinc-400" />
              <span>Skills</span>
            </div>
            <ChevronRight className="ml-auto h-3 w-3 opacity-40" />
          </CommandItem>
          <CommandItem onSelect={() => setPage("automations")}>
            <div className="flex items-center gap-3">
              <Zap className="h-4 w-4 text-zinc-400" />
              <span>Automations</span>
            </div>
            <ChevronRight className="ml-auto h-3 w-3 opacity-40" />
          </CommandItem>
        </CommandGroup>

        {(isAgentMode || appCurrentPage === "agents") && selectedThread && (
          <>
            <CommandSeparator />
            <CommandGroup heading={`Active Workspace: ${selectedThread.title}`}>
              <CommandItem onSelect={() => runCommand(() => setSelectedFilePath(null))}>
                <History className="mr-2 h-4 w-4 text-purple-400" />
                <span>Go to Timeline</span>
              </CommandItem>
              <CommandItem onSelect={() => runCommand(() => setIsRightSidebarOpen(!isRightSidebarOpen))}>
                <PanelRight className="mr-2 h-4 w-4 text-zinc-500" />
                <span>Toggle Workspace Panels</span>
                <CommandShortcut>⌘J</CommandShortcut>
              </CommandItem>
              <CommandItem onSelect={() => runCommand(() => {
                if (isRightSidebarOpen && islandPanel === "terminal") setIsRightSidebarOpen(false);
                else { setIslandPanel("terminal"); setIsRightSidebarOpen(true); }
              })}>
                <Terminal className="mr-2 h-4 w-4 text-zinc-500" />
                <span>Toggle Terminal</span>
                <CommandShortcut>⌘`</CommandShortcut>
              </CommandItem>
              <CommandItem onSelect={() => { setIslandPanel("diff"); setDiffViewTab("files"); setIsRightSidebarOpen(true); runCommand(() => { }); }}>
                <FileCode className="mr-2 h-4 w-4 text-blue-400" />
                <span>Go to Files</span>
                <CommandShortcut>⇧⌘F</CommandShortcut>
              </CommandItem>
              {fileChanges.length > 0 && (
                <CommandItem onSelect={() => { setIslandPanel("diff"); setDiffViewTab("changes"); setIsRightSidebarOpen(true); runCommand(() => { }); }}>
                  <GitBranch className="mr-2 h-4 w-4 text-emerald-400" />
                  <span>View Active Changes</span>
                  <CommandShortcut>({fileChanges.length})</CommandShortcut>
                </CommandItem>
              )}
            </CommandGroup>
          </>
        )}
        <CommandSeparator />
      </>
    );
  }

  if (currentPage === "agents") {
    return (
      <>
        <CommandGroup heading="Workspace Actions">
          <CommandItem onSelect={() => runCommand(() => setShowAddRepositoryDialog(true))}>
            <Plus className="mr-2 h-4 w-4 text-purple-400" />
            <span>Add Repository</span>
          </CommandItem>
        </CommandGroup>
        <CommandSeparator />
        <CommandGroup heading="Switch Thread">
          {allThreads.map(thread => (
            <CommandItem
              key={thread.id}
              onSelect={() => runCommand(() => {
                setIsAgentMode(true);
                navigateTo("agents");
                setSelectedIssueId(thread.id);
                setSelectedFilePath(null);
                setActiveTab("workspace");
                setExpandedRepos(prev => ({ ...prev, [thread.repoId]: true }));
              })}
            >
              <Bot className="mr-2 h-4 w-4 text-zinc-500" />
              <div className="flex flex-col">
                <span className="font-medium text-white/90">{thread.title}</span>
                <span className="text-[10px] text-zinc-500">{thread.repoName} • {thread.branchName}</span>
              </div>
              {selectedIssueId === thread.id && (
                <Monitor className="ml-auto h-3 w-3 text-purple-500" />
              )}
            </CommandItem>
          ))}
          {allThreads.length === 0 && (
            <div className="py-8 text-center text-[13px] text-zinc-500 font-medium">
              No threads found. Start by adding a repository.
            </div>
          )}
        </CommandGroup>
      </>
    );
  }

  if (currentPage === "skills") {
    return (
      <>
        <CommandGroup heading="Skills Actions">
          <CommandItem onSelect={() => runCommand(() => { navigateTo("agents"); setActiveTab("skills"); })}>
            <Lightbulb className="mr-2 h-4 w-4 text-yellow-400" />
            <span>Go to Skills Library</span>
          </CommandItem>
          <CommandItem onSelect={() => runCommand(() => { navigateTo("agents"); setActiveTab("skills"); })}>
            <Plus className="mr-2 h-4 w-4 text-yellow-400" />
            <span>Create New Skill</span>
          </CommandItem>
        </CommandGroup>
        <CommandSeparator />
        <CommandGroup heading="Active Skills">
          <div className="py-12 flex flex-col items-center justify-center gap-4 text-center">
            <div className="h-10 w-10 rounded-full bg-yellow-500/10 flex items-center justify-center">
              <Lightbulb className="h-5 w-5 text-yellow-500" />
            </div>
            <div className="flex flex-col gap-1 px-8">
              <span className="text-sm font-bold text-white/90">No Custom Skills</span>
              <p className="text-[11px] text-zinc-500 leading-relaxed font-medium">Create custom skills to give your agents specialized domain knowledge.</p>
            </div>
          </div>
        </CommandGroup>
      </>
    );
  }

  if (currentPage === "automations") {
    return (
      <>
        <CommandGroup heading="Automation Actions">
          <CommandItem onSelect={() => runCommand(() => { navigateTo("agents"); setActiveTab("automations"); })}>
            <Zap className="mr-2 h-4 w-4 text-blue-400" />
            <span>Go to Automations Library</span>
          </CommandItem>
          <CommandItem onSelect={() => runCommand(() => { navigateTo("agents"); setActiveTab("create-automation"); })}>
            <Plus className="mr-2 h-4 w-4 text-blue-400" />
            <span>Create New Automation</span>
          </CommandItem>
        </CommandGroup>
        <CommandSeparator />
        <CommandGroup heading="Available Automations">
          <div className="py-12 flex flex-col items-center justify-center gap-4 text-center">
            <div className="h-10 w-10 rounded-full bg-blue-500/10 flex items-center justify-center">
              <Zap className="h-5 w-5 text-blue-500" />
            </div>
            <div className="flex flex-col gap-1 px-8">
              <span className="text-sm font-bold text-white/90">No Automations Setup</span>
              <p className="text-[11px] text-zinc-500 leading-relaxed font-medium">Automate recurring tasks like code audits, dependencies checks or security scans.</p>
            </div>
          </div>
        </CommandGroup>
      </>
    );
  }

  return null;
}
