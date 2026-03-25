import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";

type ColumnId = "todo" | "inprogress" | "review" | "done";

interface KanbanState {
  // cardId → overridden column
  overrides: Record<string, ColumnId>;
  setOverride: (cardId: string, columnId: ColumnId) => void;
  clearOverride: (cardId: string) => void;
}

export const useKanbanStore = create<KanbanState>()(
  persist(
    (set) => ({
      overrides: {},

      setOverride: (cardId, columnId) =>
        set((state) => ({ overrides: { ...state.overrides, [cardId]: columnId } })),

      clearOverride: (cardId) =>
        set((state) => {
          const next = { ...state.overrides };
          delete next[cardId];
          return { overrides: next };
        }),
    }),
    {
      name: "unified_dev_kanban_overrides",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({ overrides: state.overrides }),
    },
  ),
);
