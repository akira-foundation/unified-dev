import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";
import { invoke } from "@tauri-apps/api/core";

import type { Locale } from "@/i18n/translations";
import type { Appearance } from "@/hooks/use-appearance";
import {
  DEFAULT_ISSUE_SCOPE,
  DEFAULT_PR_SCOPE,
  repositoryScopeKey,
  type IssueScope,
  type PullRequestScope,
} from "@/types/work-visibility";

const COMMIT_CONVENTION_BLOCK = `
Detect the project's commit convention by checking (in order):
- \`.commitlintrc\`, \`.commitlintrc.js\`, \`.commitlintrc.json\`, \`.commitlintrc.yml\`, \`commitlint.config.js\`, \`commitlint.config.ts\`
- \`git config commit.template\` for a \`.gitmessage\` template
- \`CONTRIBUTING.md\` or \`CONTRIBUTING.rst\` for commit message guidelines
Use the detected format. If Conventional Commits: \`type(scope): description\`. If nothing found: short imperative sentence.`;

export const DEFAULT_PROMPTS: Record<string, string> = {
  merge_local: `You are operating inside a git worktree. Execute the following steps NOW using your shell tools. Do NOT explain or describe — just run the commands.

1. Run \`git status --porcelain\`
2. If there are uncommitted changes: run \`git add -A\`, then commit.
${COMMIT_CONVENTION_BLOCK}
3. Switch to the base branch and merge this branch into it.
4. Do NOT push to any remote.

Execute immediately. Do not ask for confirmation.`,

  merge_push: `You are operating inside a git worktree. Execute the following steps NOW using your shell tools. Do NOT explain or describe — just run the commands.

1. Run \`git status --porcelain\`
2. If there are uncommitted changes: run \`git add -A\`, then commit.
${COMMIT_CONVENTION_BLOCK}
3. Switch to the base branch and merge this branch into it.
4. Run \`git push\` to push to the remote.

Execute immediately. Do not ask for confirmation.`,

  draft_pr: `You are operating inside a git worktree. Execute the following steps NOW using your shell tools. Do NOT explain or describe — just run the commands.

1. Run \`git status --porcelain\`
2. If there are uncommitted changes: run \`git add -A\`, then commit.
${COMMIT_CONVENTION_BLOCK}
3. Run \`git push -u origin HEAD\`
4. Run \`gh pr create --draft --title "<title>" --body "<body>"\` with an appropriate title and body based on the diff.
5. Output only the PR URL.

Execute immediately. Do not ask for confirmation. Do not say you cannot run write commands — you can.`,

  create_pr: `You are operating inside a git worktree. Execute the following steps NOW using your shell tools. Do NOT explain or describe — just run the commands.

1. Run \`git status --porcelain\`
2. If there are uncommitted changes: run \`git add -A\`, then commit.
${COMMIT_CONVENTION_BLOCK}
3. Run \`git push -u origin HEAD\`
4. Run \`gh pr create --title "<title>" --body "<body>"\` with an appropriate title and body based on the diff.
5. Output only the PR URL.

Execute immediately. Do not ask for confirmation. Do not say you cannot run write commands — you can.`,

  merge_commit: `You are operating inside a git worktree. A pull request already exists for this branch. Execute the following steps NOW using your shell tools. Do NOT explain or describe — just run the commands.

1. Run \`git status --porcelain\`
2. If there are uncommitted changes: run \`git add -A\`, then commit.
${COMMIT_CONVENTION_BLOCK}
3. Run \`git push\` to push to the remote. The open PR will update automatically.
4. Output: "Changes pushed. PR updated."

Execute immediately. Do not ask for confirmation. Do not say you cannot run write commands — you can.`,
};

interface SettingsState {
  locale: Locale;
  setLocale: (locale: Locale) => void;
  appearance: Appearance;
  setAppearance: (appearance: Appearance) => void;
  sidebarOpen: boolean;
  setSidebarOpen: (open: boolean) => void;
  editorTheme: string;
  setEditorTheme: (theme: string) => void;

  // Prompt overrides — source of truth is SQLite; this is an in-memory cache
  promptOverrides: Record<string, string>;
  loadPrompts: () => Promise<void>;
  savePrompt: (action: string, content: string) => Promise<void>;
  resetPrompt: (action: string) => Promise<void>;
  getPrompt: (action: string) => string;
  defaultIssueScope: IssueScope;
  defaultPrScope: PullRequestScope;
  assignIssuesToSelfByDefault: boolean;
  organizationIssueScopes: Record<string, IssueScope>;
  organizationPrScopes: Record<string, PullRequestScope>;
  repositoryIssueScopes: Record<string, IssueScope>;
  repositoryPrScopes: Record<string, PullRequestScope>;
  setDefaultIssueScope: (scope: IssueScope) => void;
  setDefaultPrScope: (scope: PullRequestScope) => void;
  setAssignIssuesToSelfByDefault: (enabled: boolean) => void;
  setOrganizationIssueScope: (orgId: string, scope: IssueScope | null) => void;
  setOrganizationPrScope: (orgId: string, scope: PullRequestScope | null) => void;
  setRepositoryIssueScope: (orgId: string, repoName: string, scope: IssueScope | null) => void;
  setRepositoryPrScope: (orgId: string, repoName: string, scope: PullRequestScope | null) => void;
  resolveIssueScope: (orgId: string, repoName?: string) => IssueScope;
  resolvePrScope: (orgId: string, repoName?: string) => PullRequestScope;
}

export const useSettingsStore = create<SettingsState>()(
  persist(
    (set, get) => ({
      locale: "en",
      setLocale: (locale) => set({ locale }),
      appearance: "system",
      setAppearance: (appearance) => set({ appearance }),
      sidebarOpen: true,
      setSidebarOpen: (open) => set({ sidebarOpen: open }),
      editorTheme: "oneDark",
      setEditorTheme: (theme) => set({ editorTheme: theme }),
      defaultIssueScope: DEFAULT_ISSUE_SCOPE,
      defaultPrScope: DEFAULT_PR_SCOPE,
      assignIssuesToSelfByDefault: true,
      organizationIssueScopes: {},
      organizationPrScopes: {},
      repositoryIssueScopes: {},
      repositoryPrScopes: {},
      setDefaultIssueScope: (scope) => set({ defaultIssueScope: scope }),
      setDefaultPrScope: (scope) => set({ defaultPrScope: scope }),
      setAssignIssuesToSelfByDefault: (enabled) => set({ assignIssuesToSelfByDefault: enabled }),
      setOrganizationIssueScope: (orgId, scope) => set((state) => {
        const next = { ...state.organizationIssueScopes };
        if (scope === null) {
          delete next[orgId];
        } else {
          next[orgId] = scope;
        }
        return { organizationIssueScopes: next };
      }),
      setOrganizationPrScope: (orgId, scope) => set((state) => {
        const next = { ...state.organizationPrScopes };
        if (scope === null) {
          delete next[orgId];
        } else {
          next[orgId] = scope;
        }
        return { organizationPrScopes: next };
      }),
      setRepositoryIssueScope: (orgId, repoName, scope) => set((state) => {
        const key = repositoryScopeKey(orgId, repoName);
        const next = { ...state.repositoryIssueScopes };
        if (scope === null) {
          delete next[key];
        } else {
          next[key] = scope;
        }
        return { repositoryIssueScopes: next };
      }),
      setRepositoryPrScope: (orgId, repoName, scope) => set((state) => {
        const key = repositoryScopeKey(orgId, repoName);
        const next = { ...state.repositoryPrScopes };
        if (scope === null) {
          delete next[key];
        } else {
          next[key] = scope;
        }
        return { repositoryPrScopes: next };
      }),
      resolveIssueScope: (orgId, repoName) => {
        const state = get();
        if (repoName) {
          const repoScope = state.repositoryIssueScopes[repositoryScopeKey(orgId, repoName)];
          if (repoScope) return repoScope;
        }
        return state.organizationIssueScopes[orgId] ?? state.defaultIssueScope ?? DEFAULT_ISSUE_SCOPE;
      },
      resolvePrScope: (orgId, repoName) => {
        const state = get();
        if (repoName) {
          const repoScope = state.repositoryPrScopes[repositoryScopeKey(orgId, repoName)];
          if (repoScope) return repoScope;
        }
        return state.organizationPrScopes[orgId] ?? state.defaultPrScope ?? DEFAULT_PR_SCOPE;
      },

      promptOverrides: {},

      loadPrompts: async () => {
        try {
          const overrides = await invoke<Record<string, string>>("get_prompts");
          set({ promptOverrides: overrides });
        } catch {
          // non-fatal — defaults will be used
        }
      },

      savePrompt: async (action, content) => {
        await invoke("save_prompt", { action, content });
        set((state) => ({
          promptOverrides: { ...state.promptOverrides, [action]: content },
        }));
      },

      resetPrompt: async (action) => {
        await invoke("reset_prompt", { action });
        set((state) => {
          const next = { ...state.promptOverrides };
          delete next[action];
          return { promptOverrides: next };
        });
      },

      getPrompt: (action) => {
        const { promptOverrides } = get();
        return promptOverrides[action] ?? DEFAULT_PROMPTS[action] ?? "";
      },
    }),
    {
      name: "unified_dev_settings",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({
        locale: state.locale,
        appearance: state.appearance,
        sidebarOpen: state.sidebarOpen,
        editorTheme: state.editorTheme,
        defaultIssueScope: state.defaultIssueScope,
        defaultPrScope: state.defaultPrScope,
        assignIssuesToSelfByDefault: state.assignIssuesToSelfByDefault,
        organizationIssueScopes: state.organizationIssueScopes,
        organizationPrScopes: state.organizationPrScopes,
        repositoryIssueScopes: state.repositoryIssueScopes,
        repositoryPrScopes: state.repositoryPrScopes,
      }),
    },
  ),
);
