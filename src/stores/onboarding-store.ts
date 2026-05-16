import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";

interface OnboardingState {
  completed: boolean;
  authOnly: boolean;
  complete: () => void;
  reset: () => void;
  requireAuth: () => void;
  clearRequireAuth: () => void;
}

export const useOnboardingStore = create<OnboardingState>()(
  persist(
    (set) => ({
      completed: false,
      authOnly: false,
      complete: () => set({ completed: true, authOnly: false }),
      reset: () => set({ completed: false, authOnly: false }),
      requireAuth: () => set({ authOnly: true }),
      clearRequireAuth: () => set({ authOnly: false }),
    }),
    {
      name: "unified_dev_onboarding",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({ completed: state.completed }),
    },
  ),
);
