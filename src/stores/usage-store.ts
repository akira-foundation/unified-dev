import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";

interface UsageDto {
    runCount: number;
    runLimit: number | null;
    date: string;
    isFree: boolean;
}

interface UsageState {
    runCount: number;
    runLimit: number | null;
    date: string;
    isFree: boolean;
    refresh: () => Promise<void>;
}

export const useUsageStore = create<UsageState>((set) => ({
    runCount: 0,
    runLimit: null,
    date: "",
    isFree: false,
    refresh: async () => {
        try {
            const dto = await invoke<UsageDto>("get_usage");
            set({
                runCount: dto.runCount,
                runLimit: dto.runLimit,
                date: dto.date,
                isFree: dto.isFree,
            });
        } catch {
        }
    },
}));

export function refreshUsage(): void {
    void useUsageStore.getState().refresh();
}
