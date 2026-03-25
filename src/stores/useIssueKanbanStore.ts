import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";

import type { IssueColumnId } from "../types/issue";

interface IssueKanbanState {
  overrides: Record<string, IssueColumnId>;
  setOverride: (issueId: string, columnId: IssueColumnId) => void;
  clearOverride: (issueId: string) => void;
}

export const useIssueKanbanStore = create<IssueKanbanState>()(
  persist(
    (set) => ({
      overrides: {},
      setOverride: (issueId, columnId) =>
        set((state) => ({ overrides: { ...state.overrides, [issueId]: columnId } })),
      clearOverride: (issueId) =>
        set((state) => {
          const next = { ...state.overrides };
          delete next[issueId];
          return { overrides: next };
        }),
    }),
    {
      name: "akira_issue_kanban_overrides",
      storage: createJSONStorage(() => localStorage),
    },
  ),
);
