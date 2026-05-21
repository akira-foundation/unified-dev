import { create } from "zustand";
import type { ReactNode } from "react";

export interface SearchResult {
  id: string;
  title: string;
  subtitle?: string;
  icon?: ReactNode;
  onSelect: () => void;
}

export interface SearchProvider {
  placeholder: string;
  items: SearchResult[];
}

interface SearchState {
  open: boolean;
  provider: SearchProvider | null;
  setOpen: (open: boolean) => void;
  registerProvider: (provider: SearchProvider | null) => void;
}

export const useSearchStore = create<SearchState>((set) => ({
  open: false,
  provider: null,
  setOpen: (open) => set({ open }),
  registerProvider: (provider) => set({ provider }),
}));
