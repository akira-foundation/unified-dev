import { useEffect, useRef } from "react";
import { useAgentsStore } from "@/stores/useAgentsStore";

const POLL_INTERVAL_MS = 30_000;

export function usePRChecksPolling(threadId: string | undefined, workspacePath: string | undefined) {
  const loadPrCi = useAgentsStore((s) => s.loadPrCi);
  const prInfo = useAgentsStore((s) => (threadId ? s.prUrlByThread[threadId] : null));
  const ci = useAgentsStore((s) => (threadId ? s.prCiByThread[threadId] : null));
  const intervalRef = useRef<number | null>(null);

  useEffect(() => {
    if (!threadId || !workspacePath || !prInfo?.url) {
      if (intervalRef.current) {
        window.clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
      return;
    }

    void loadPrCi(threadId, workspacePath);

    const shouldPoll = !ci || ci.pending > 0 || ci.total === 0;
    if (!shouldPoll) {
      if (intervalRef.current) {
        window.clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
      return;
    }

    intervalRef.current = window.setInterval(() => {
      void loadPrCi(threadId, workspacePath);
    }, POLL_INTERVAL_MS);

    return () => {
      if (intervalRef.current) {
        window.clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [threadId, workspacePath, prInfo?.url, ci?.pending, ci?.total, loadPrCi]);
}
