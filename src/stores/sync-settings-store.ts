import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";

export interface SyncSettingsDto {
  id: string;
  scope: string;
  syncIssuesEnabled: boolean;
  syncIssuesIntervalSecs: number;
  syncPrsEnabled: boolean;
  syncPrsIntervalSecs: number;
  syncReposEnabled: boolean;
  syncReposIntervalSecs: number;
  syncOrgsEnabled: boolean;
  syncOrgsIntervalSecs: number;
}

export interface UpsertSyncSettingsInput {
  id: string;
  syncIssuesEnabled: boolean;
  syncIssuesIntervalSecs: number;
  syncPrsEnabled: boolean;
  syncPrsIntervalSecs: number;
  syncReposEnabled: boolean;
  syncReposIntervalSecs: number;
  syncOrgsEnabled: boolean;
  syncOrgsIntervalSecs: number;
}

export const GLOBAL_SYNC_ID = "global";

export const INTERVAL_OPTIONS = {
  issues: [
    { label: "5 min", value: 300 },
    { label: "15 min", value: 900 },
    { label: "30 min", value: 1800 },
    { label: "1 hora", value: 3600 },
    { label: "2 horas", value: 7200 },
  ],
  prs: [
    { label: "1 min", value: 60 },
    { label: "2 min", value: 120 },
    { label: "5 min", value: 300 },
    { label: "10 min", value: 600 },
    { label: "30 min", value: 1800 },
  ],
  repos: [
    { label: "5 min", value: 300 },
    { label: "15 min", value: 900 },
    { label: "30 min", value: 1800 },
    { label: "1 hora", value: 3600 },
    { label: "2 horas", value: 7200 },
  ],
  orgs: [
    { label: "30 min", value: 1800 },
    { label: "1 hora", value: 3600 },
    { label: "2 horas", value: 7200 },
    { label: "4 horas", value: 14400 },
    { label: "8 horas", value: 28800 },
  ],
} as const;

interface SyncSettingsState {
  globalSettings: SyncSettingsDto | null;
  orgSettings: Record<string, SyncSettingsDto>;
  isLoading: boolean;

  loadSettings: (id: string) => Promise<SyncSettingsDto>;
  saveSettings: (input: UpsertSyncSettingsInput) => Promise<SyncSettingsDto>;
  resetSettings: (id: string) => Promise<SyncSettingsDto>;
}

export const useSyncSettingsStore = create<SyncSettingsState>((set) => ({
  globalSettings: null,
  orgSettings: {},
  isLoading: false,

  loadSettings: async (id) => {
    set({ isLoading: true });
    try {
      const result = await invoke<SyncSettingsDto>("get_sync_settings", { id });
      if (id === GLOBAL_SYNC_ID) {
        set({ globalSettings: result });
      } else {
        set((state) => ({ orgSettings: { ...state.orgSettings, [id]: result } }));
      }
      return result;
    } finally {
      set({ isLoading: false });
    }
  },

  saveSettings: async (input) => {
    const result = await invoke<SyncSettingsDto>("upsert_sync_settings", { input });
    if (input.id === GLOBAL_SYNC_ID) {
      set({ globalSettings: result });
    } else {
      set((state) => ({ orgSettings: { ...state.orgSettings, [input.id]: result } }));
    }
    return result;
  },

  resetSettings: async (id) => {
    const result = await invoke<SyncSettingsDto>("reset_sync_settings", { id });
    if (id === GLOBAL_SYNC_ID) {
      set({ globalSettings: result });
    } else {
      set((state) => ({
        orgSettings: { ...state.orgSettings, [id]: result },
      }));
    }
    return result;
  },
}));
