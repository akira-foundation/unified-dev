import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";
import { invoke } from "@tauri-apps/api/core";

import type { Locale } from "@/i18n/translations";
import type { Appearance } from "@/hooks/use-appearance";

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
      }),
    },
  ),
);
