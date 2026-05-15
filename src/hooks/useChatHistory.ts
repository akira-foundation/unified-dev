import { useCallback, useEffect, useRef, useState } from "react";

const STORAGE_KEY = "akira_chat_history";
const MAX_ENTRIES = 50;

function readHistory(): string[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((entry): entry is string => typeof entry === "string");
  } catch {
    return [];
  }
}

function writeHistory(history: string[]): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(history));
  } catch {
    /* ignore quota errors */
  }
}

export interface UseChatHistoryReturn {
  pushEntry: (message: string) => void;
  navigatePrev: (currentDraft: string) => string | null;
  navigateNext: () => string | null;
  reset: () => void;
  isNavigating: boolean;
}

export function useChatHistory(): UseChatHistoryReturn {
  const [history, setHistory] = useState<string[]>(() => readHistory());
  const [index, setIndex] = useState<number | null>(null);
  const draftRef = useRef<string>("");

  useEffect(() => {
    writeHistory(history);
  }, [history]);

  const pushEntry = useCallback((message: string) => {
    const trimmed = message.trim();
    if (!trimmed) return;
    setHistory((prev) => {
      const next = prev.filter((entry) => entry !== trimmed);
      next.push(trimmed);
      if (next.length > MAX_ENTRIES) {
        next.splice(0, next.length - MAX_ENTRIES);
      }
      return next;
    });
    setIndex(null);
    draftRef.current = "";
  }, []);

  const navigatePrev = useCallback(
    (currentDraft: string): string | null => {
      if (history.length === 0) return null;
      if (index === null) {
        draftRef.current = currentDraft;
        const newIndex = history.length - 1;
        setIndex(newIndex);
        return history[newIndex];
      }
      if (index <= 0) return history[0];
      const newIndex = index - 1;
      setIndex(newIndex);
      return history[newIndex];
    },
    [history, index],
  );

  const navigateNext = useCallback((): string | null => {
    if (index === null) return null;
    if (index >= history.length - 1) {
      setIndex(null);
      const draft = draftRef.current;
      draftRef.current = "";
      return draft;
    }
    const newIndex = index + 1;
    setIndex(newIndex);
    return history[newIndex];
  }, [history, index]);

  const reset = useCallback(() => {
    setIndex(null);
    draftRef.current = "";
  }, []);

  return {
    pushEntry,
    navigatePrev,
    navigateNext,
    reset,
    isNavigating: index !== null,
  };
}
