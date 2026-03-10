import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";
import type { AgentTimelineStep, FileChange, RepositoryGroup } from "../types/agents";
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
  setSelectedIssueId: (id: string | null) => void;
  setSelectedFilePath: (path: string | null) => void;
  setActiveTab: (tab: "workspace" | "skills" | "automations" | "create-automation" | "manage-skill") => void;
  setSelectedSkill: (skill: any | null) => void;
  setSelectedAutomation: (automation: any | null) => void;
  setSelectedModelId: (id: string) => void;
  loadAiProviders: () => Promise<void>;
}

const mockGroups: RepositoryGroup[] = [
  {
    name: "THREADS",
    repositories: [
      {
        id: "repo-1",
        name: "laravel-sisp",
        issues: [
          {
            id: "i1",
            title: "Address callback DoS and IDOR",
            repoName: "laravel-sisp",
            branchName: "security/fix-dos",
            agentName: "BugFixAgent",
            status: "Completed",
            updatedAt: "3d",
          },
          {
            id: "i2",
            title: "ensure 100% coverage test Com...",
            repoName: "laravel-sisp",
            branchName: "chore/coverage",
            agentName: "TestAgent",
            status: "Completed",
            updatedAt: "1mo",
          },
          {
            id: "i3",
            title: "ensure ValueObjects/PaymentRe...",
            repoName: "laravel-sisp",
            branchName: "refactor/vo",
            agentName: "CodeButler",
            status: "Completed",
            updatedAt: "1mo",
          },
        ],
      },
      { id: "repo-2", name: "rh", issues: [] },
      { id: "repo-3", name: "audit", issues: [] },
      {
        id: "repo-4",
        name: "nosferry-core",
        issues: [
          {
            id: "i4",
            title: "ISSUE CREATOR",
            repoName: "nosferry-core",
            branchName: "feat/issue-creator",
            agentName: "ProductBot",
            status: "Running",
            updatedAt: "1w",
          },
          {
            id: "i5",
            title: "ensure 100% test coverage Actio...",
            repoName: "nosferry-core",
            branchName: "test/actions",
            agentName: "TestAgent",
            status: "Completed",
            updatedAt: "3w",
          },
          {
            id: "i6",
            title: "Refine recent Laravel code",
            repoName: "nosferry-core",
            branchName: "refactor/laravel",
            agentName: "CodeButler",
            status: "Completed",
            updatedAt: "3w",
          },
        ],
      },
      { id: "repo-5", name: "Support refunds", issues: [] },
      { id: "repo-6", name: "nosferry.com", issues: [] },
      { id: "repo-7", name: "laravel-pdf-invoices", issues: [] },
    ],
  },
];

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

export const useAgentsStore = create<AgentsState>((set) => ({
  repositoryGroups: mockGroups,
  selectedIssueId: "i4",
  timelineSteps: mockTimeline,
  fileChanges: mockFiles,
  selectedFilePath: null,
  activeTab: "workspace",
  selectedSkill: null,
  selectedAutomation: null,
  aiProviders: [],
  selectedModelId: null,
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
}));
