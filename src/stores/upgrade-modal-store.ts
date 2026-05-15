import { create } from "zustand";

export type FreeTierLimitType =
    | "run_limit_reached"
    | "thread_limit_reached"
    | "repo_limit_reached"
    | "org_limit_reached"
    | "remote_requires_ultimate"
    | "autopilot_requires_pro";

export interface UpgradeModalContext {
    count?: number;
    limit?: number;
}

interface UpgradeModalStore {
    open: boolean;
    limitType: FreeTierLimitType | null;
    context: UpgradeModalContext;
    openUpgradeModal: (limitType: FreeTierLimitType, context?: UpgradeModalContext) => void;
    closeUpgradeModal: () => void;
}

export const useUpgradeModalStore = create<UpgradeModalStore>((set) => ({
    open: false,
    limitType: null,
    context: {},
    openUpgradeModal: (limitType, context = {}) => set({ open: true, limitType, context }),
    closeUpgradeModal: () => set({ open: false, limitType: null, context: {} }),
}));

export function openUpgradeModal(limitType: FreeTierLimitType, context?: UpgradeModalContext): void {
    useUpgradeModalStore.getState().openUpgradeModal(limitType, context);
}
