import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import { invoke } from "@tauri-apps/api/core";
import type { AgentTimelineStep, FileChange, RepositoryGroup, AgentStatus } from "../types/agents";
import type { AiProviderGroup, AiProviderResponse } from "../types/ai-providers";

interface AgentsState {
  repositoryGroups: RepositoryGroup[];
  selectedIssueId: string | null;
  timelineSteps: AgentTimelineStep[];
  fileChanges: FileChange[];
  selectedFilePath: string | null;
  activeTab: "workspace" | "skills" | "automations" | "create-automation" | "manage-skill";
  selectedSkill: any | null;
  selectedAutomation: any | null;
  aiProviders: AiProviderGroup[];
  selectedModelId: string | null;
  repositoriesLoaded: boolean;
  setSelectedIssueId: (id: string | null) => void;
  setSelectedFilePath: (path: string | null) => void;
  setActiveTab: (tab: "workspace" | "skills" | "automations" | "create-automation" | "manage-skill") => void;
  setSelectedSkill: (skill: any | null) => void;
  setSelectedAutomation: (automation: any | null) => void;
  setSelectedModelId: (id: string) => void;
  loadAiProviders: () => Promise<void>;
  loadRepositories: () => Promise<void>;
  addRepository: (repo: { name: string, id: string }, thread: { title: string, id: string }) => void;
  addThread: (repoId: string, thread: { title: string, id: string }) => void;
  removeThread: (repoId: string, threadId: string) => void;
  removeRepository: (id: string) => void;
}

const mockTimeline: AgentTimelineStep[] = [
  { id: "1", message: "Analyzing repository structure...", timestamp: "14:20", status: "completed" },
  { id: "2", message: "Scanning for CSV injection patterns in report_exports.php", timestamp: "14:21", status: "completed" },
  { id: "3", message: "Found vulnerability: Unsanitized input in export function", timestamp: "14:22", status: "warning", details: "The 'filename' parameter is used directly in the CSV output without proper escaping." },
  { id: "4", message: "Applying security fix in security_helper.php", timestamp: "14:23", status: "completed" },
  { id: "5", message: "Running regression tests", timestamp: "14:25", status: "running" },
  { id: "6", message: "CI running", timestamp: "14:26", status: "info" },
];

const mockFiles: FileChange[] = [
  {
    filename: "report_exports.php",
    status: "modified",
    diff: `@@ -45,7 +45,7 @@ class ReportExporter\n     public function export(array $data, string $filename)\n     {\n-        $handle = fopen('php://output', 'w');\n+        $handle = fopen('php://output', 'w');\n+        // Secure escaping for CSV injection\n         $filename = SecurityHelper::sanitizeCsv($filename);\n         fputcsv($handle, $data);\n     }`,
  },
  {
    filename: "security_helper.php",
    status: "modified",
    diff: `@@ -12,4 +12,9 @@ class SecurityHelper\n {\n+    public static function sanitizeCsv(string $input): string\n+    {\n+        return preg_replace('/^[=+-@]/', "'$0", $input);\n+    }\n }`,
  },
];

function selectDefaultModel(providers: AiProviderGroup[]): string | null {
  if (providers.length === 0) return null;

  const claude = providers.find((p) => p.name === "Claude");
  if (claude && claude.models.length > 0) {
    const sonnet = claude.models.find((m) => m.id === "claude-sonnet");
    return sonnet ? sonnet.id : claude.models[0].id;
  }

  return providers[0].models[0]?.id ?? null;
}

export const useAgentsStore = create<AgentsState>()(
  persist(
    (set) => ({
      repositoryGroups: [{ name: "THREADS", repositories: [] }],
      selectedIssueId: null,
      timelineSteps: mockTimeline,
      fileChanges: mockFiles,
      selectedFilePath: null,
      activeTab: "workspace",
      selectedSkill: null,
      selectedAutomation: null,
      aiProviders: [],
      selectedModelId: null,
      repositoriesLoaded: false,
      setSelectedIssueId: (id) => set({ selectedIssueId: id, activeTab: "workspace" }),
      setSelectedFilePath: (path) => set({ selectedFilePath: path }),
      setActiveTab: (tab) => set({ activeTab: tab }),
      setSelectedSkill: (skill) => set({ selectedSkill: skill, activeTab: "manage-skill" }),
      setSelectedAutomation: (automation) => set({ selectedAutomation: automation, activeTab: "create-automation" }),
      setSelectedModelId: (id) => set({ selectedModelId: id }),
      loadAiProviders: async () => {
        try {
          const response = await invoke<AiProviderResponse>("get_available_models");
          const providers = response.providers;
          const defaultModel = selectDefaultModel(providers);
          set({ aiProviders: providers, selectedModelId: defaultModel });
        } catch {
          set({ aiProviders: [], selectedModelId: null });
        }
      },
      loadRepositories: async () => {
        try {
          const rows = await invoke<Array<{ id: string; name: string; threads: Array<{ id: string; title: string; branch: string; status: string; created_at: string }> }>>("list_repositories");
          const repositories = rows.map((row) => ({
            id: row.id,
            name: row.name,
            issues: row.threads.map((t) => ({
              id: t.id,
              title: t.title,
              repoName: row.name,
              branchName: t.branch,
              agentName: "Unified Dev",
              status: "Running" as AgentStatus,
              updatedAt: t.created_at,
            })),
          }));
          set({
            repositoryGroups: [{ name: "THREADS", repositories }],
            repositoriesLoaded: true,
          });
        } catch {
          set({ repositoriesLoaded: true });
        }
      },
      addRepository: (repo, thread) => set((state) => {
        const newGroups = [...state.repositoryGroups];
        const threadsGroup = newGroups.find(g => g.name === "THREADS");
        if (threadsGroup) {
          threadsGroup.repositories.unshift({
            id: repo.id,
            name: repo.name,
            issues: [{
              id: thread.id,
              title: thread.title,
              repoName: repo.name,
              branchName: "main",
              agentName: "Polyscope",
              status: "Running",
              updatedAt: "just now"
            }]
          });
        }
        return { repositoryGroups: newGroups, selectedIssueId: thread.id };
      }),
      addThread: (repoId, thread) => set((state) => {
        const newGroups = state.repositoryGroups.map(group => ({
          ...group,
          repositories: group.repositories.map(repo => {
            if (repo.id !== repoId) return repo;
            return {
              ...repo,
              issues: [...repo.issues, {
                id: thread.id,
                title: thread.title,
                repoName: repo.name,
                branchName: "main",
                agentName: "Unified Dev",
                status: "Running" as AgentStatus,
                updatedAt: "just now"
              }]
            };
          })
        }));
        return { repositoryGroups: newGroups, selectedIssueId: thread.id };
      }),
      removeThread: (repoId, threadId) => set((state) => {
        const newGroups = state.repositoryGroups.map(group => ({
          ...group,
          repositories: group.repositories.map(repo => {
            if (repo.id !== repoId) return repo;
            return {
              ...repo,
              issues: repo.issues.filter(i => i.id !== threadId)
            };
          })
        }));

        const nextSelectedId = state.selectedIssueId === threadId ? null : state.selectedIssueId;

        return { repositoryGroups: newGroups, selectedIssueId: nextSelectedId };
      }),
      removeRepository: (id) => set((state) => {
        const newGroups = state.repositoryGroups.map(group => ({
          ...group,
          repositories: group.repositories.filter(r => r.id !== id)
        }));
        return { repositoryGroups: newGroups };
      }),
    }),
    {
      name: "unified_dev_agents",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({
        selectedIssueId: state.selectedIssueId,
        activeTab: state.activeTab,
        selectedModelId: state.selectedModelId,
      }),
    }
  )
);
