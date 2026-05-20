import { create } from "zustand";
import { persist } from "zustand/middleware";
import { invoke } from "@tauri-apps/api/core";

export type Plan = "free" | "pro" | "ultimate";
export type BillingCycle = "monthly" | "yearly";
export type LicenseStatus = "active" | "expired" | "invalid";

export interface LicenseDto {
  token: string;
  plan: string;
  cycle: string;
  email: string;
  status: string;
  validUntil: string;
  activatedAt: string;
  lastVerifiedAt: string;
  signature: string;
  gracePeriod: boolean;
  cancelAtPeriodEnd?: boolean;
  cancelAt?: string | null;
  targetPlan?: string | null;
}

interface LicenseState {
  license: LicenseDto | null;
  loading: boolean;
  activating: boolean;
  load: () => Promise<void>;
  verify: () => Promise<void>;
  activate: (sessionId: string) => Promise<void>;
  clear: () => Promise<void>;
  plan: () => Plan;
}

export const useLicenseStore = create<LicenseState>()(
  persist(
    (set, get) => ({
  license: null,
  loading: false,
  activating: false,

  load: async () => {
    set({ loading: true });
    try {
      const license = await invoke<LicenseDto | null>("get_license");
      set({ license });
    } catch {
      set({ license: null });
    } finally {
      set({ loading: false });
    }
  },

  verify: async () => {
    set({ loading: true });
    try {
      const license = await invoke<LicenseDto | null>("verify_license");
      set({ license });
    } catch {
      set({ license: null });
    } finally {
      set({ loading: false });
    }
  },

  activate: async (sessionId: string) => {
    // Prevent concurrent activation from deep link + polling racing
    if (get().activating) return;
    set({ activating: true, loading: true });
    try {
      const license = await invoke<LicenseDto>("activate_license", { input: { sessionId } });
      set({ license });
    } finally {
      set({ activating: false, loading: false });
    }
  },

  clear: async () => {
    await invoke("clear_license");
    set({ license: null });
  },

  plan: (): Plan => {
    const { license } = get();
    if (!license || license.status !== "active") return "free";
    const p = license.plan.toLowerCase();
    if (p === "ultimate") return "ultimate";
    if (p === "pro") return "pro";
    return "free";
  },
}),
    {
      name: "akira-license",
      partialize: (state) => ({ license: state.license }),
    }
  )
);
