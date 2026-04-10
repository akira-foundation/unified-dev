import { useEffect } from "react";
import { useUsageStore } from "@/stores/usage-store";

export function useUsage() {
    const { runCount, runLimit, isFree, date, refresh } = useUsageStore();

    useEffect(() => {
        refresh();
    }, []);

    return {
        count: runCount,
        limit: runLimit,
        isFree,
        isAtLimit: runLimit !== null && runCount >= runLimit,
        date,
        refresh,
    };
}
