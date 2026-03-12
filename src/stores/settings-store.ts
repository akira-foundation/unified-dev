import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";
import { invoke } from "@tauri-apps/api/core";

import type { Locale } from "@/i18n/translations";
import type { Appearance } from "@/hooks/use-appearance";

const COMMIT_CONVENTION_BLOCK = `
Before committing, detect the project's commit convention:
- Check for \`.commitlintrc\`, \`.commitlintrc.js\`, \`.commitlintrc.json\`, \`.commitlintrc.yml\`, \`commitlint.config.js\`, \`commitlint.config.ts\` in the workspace root
- Check for a \`.gitmessage\` template via \`git config commit.template\`
- Check \`CONTRIBUTING.md\` or \`CONTRIBUTING.rst\` for commit message guidelines
- If Conventional Commits is detected: use \`type(scope): description\` format (e.g. \`fix(ci): adjust config\`, \`feat(auth): add OAuth support\`)
- If no convention is found: use a short, descriptive imperative message`;

export const DEFAULT_PROMPTS: Record<string, string> = {
  merge_local: `Merge the changes from this worktree into the base branch locally.

Steps:
1. Check for uncommitted changes with \`git status --porcelain\`
2. If there are uncommitted changes, stage them all with \`git add -A\` and commit with a meaningful message.
${COMMIT_CONVENTION_BLOCK}
3. Switch to the base branch and merge the worktree branch
4. Do NOT push to the remote`,

  merge_push: `Merge the changes from this worktree into the base branch and push to the remote.

Steps:
1. Check for uncommitted changes with \`git status --porcelain\`
2. If there are uncommitted changes, stage them all with \`git add -A\` and commit with a meaningful message.
${COMMIT_CONVENTION_BLOCK}
3. Switch to the base branch and merge the worktree branch
4. Push the base branch to the remote with \`git push\``,

  draft_pr: `Create a draft pull request for the changes on this branch.

Steps:
1. Check for uncommitted changes with \`git status --porcelain\`
2. If there are uncommitted changes, stage them all with \`git add -A\` and commit with a meaningful message.
${COMMIT_CONVENTION_BLOCK}
3. Push the branch to the remote with \`git push -u origin <branch>\`
4. Create a draft PR with \`gh pr create --draft --title "<title>" --body "<body>"\`
5. Return the PR URL`,

  create_pr: `Create a pull request for the changes on this branch.

Steps:
1. Check for uncommitted changes with \`git status --porcelain\`
2. If there are uncommitted changes, stage them all with \`git add -A\` and commit with a meaningful message.
${COMMIT_CONVENTION_BLOCK}
3. Push the branch to the remote with \`git push -u origin <branch>\`
4. Create a PR with \`gh pr create --title "<title>" --body "<body>"\`
5. Return the PR URL`,
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
