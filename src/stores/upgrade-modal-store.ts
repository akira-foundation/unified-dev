import { create } from "zustand";

export type FreeTierLimitType =
    | "run_limit_reached"
    | "thread_limit_reached"
    | "repo_limit_reached"
    | "org_limit_reached"
    | "remote_requires_ultimate";

interface UpgradeModalStore {
    open: boolean;
    limitType: FreeTierLimitType | null;
    openUpgradeModal: (limitType: FreeTierLimitType) => void;
    closeUpgradeModal: () => void;
}

export const useUpgradeModalStore = create<UpgradeModalStore>((set) => ({
    open: false,
    limitType: null,
    openUpgradeModal: (limitType) => set({ open: true, limitType }),
    closeUpgradeModal: () => set({ open: false, limitType: null }),
}));

export function openUpgradeModal(limitType: FreeTierLimitType): void {
    useUpgradeModalStore.getState().openUpgradeModal(limitType);
}
