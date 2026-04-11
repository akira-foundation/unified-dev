import { useEffect, useRef, useCallback } from "react";
import { useLicenseStore } from "@/stores/license-store";

const AKIRA_API_URL = "https://akira-github-proxy.kidiatoliny.workers.dev";
const POLL_INTERVAL_MS = 3000;
const POLL_TIMEOUT_MS = 10 * 60 * 1000;

export function useCheckoutPoller(sessionId: string | null, onActivated: () => void) {
  const { activate, activating } = useLicenseStore();
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const startedAtRef = useRef<number | null>(null);
  const doneRef = useRef(false);

  const stop = useCallback(() => {
    if (intervalRef.current !== null) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
    startedAtRef.current = null;
  }, []);

  useEffect(() => {
    if (!sessionId) {
      stop();
      doneRef.current = false;
      return;
    }

    doneRef.current = false;
    startedAtRef.current = Date.now();

    const poll = async () => {
      if (doneRef.current) return;

      if (startedAtRef.current !== null && Date.now() - startedAtRef.current > POLL_TIMEOUT_MS) {
        stop();
        return;
      }

      if (activating) return;

      try {
        const res = await fetch(`${AKIRA_API_URL}/billing/poll?session_id=${sessionId}`);
        if (!res.ok) return;

        const data = await res.json() as { paid: boolean };
        if (!data.paid) return;

        doneRef.current = true;
        stop();

        await activate(sessionId);
        onActivated();
      } catch {
      }
    };

    void poll();
    intervalRef.current = setInterval(() => void poll(), POLL_INTERVAL_MS);

    return stop;
  }, [sessionId]);
}
