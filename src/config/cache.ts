/**
 * Centralized cache configuration for React Query.
 *
 * staleTime  — how long cached data is considered fresh (no refetch on mount)
 * gcTime     — how long inactive cache entries are kept in memory before GC
 *
 * Usage:
 *   import { cache } from "@/config/cache"
 *   useQuery({ ..., staleTime: cache.staleTime.live, gcTime: cache.gcTime.default })
 */

const SECOND = 1_000;
const MINUTE = 60 * SECOND;
const HOUR = 60 * MINUTE;

export const cache = {
  staleTime: {
    /** Always refetch on mount — live data (PRs, checks). */
    live: 0,
    /** 30 seconds — near-realtime data (kanban PR columns). */
    realtime: 30 * SECOND,
    /** 1 minute — frequently updated data (repo lists, issues). */
    short: 1 * MINUTE,
    /** 5 minutes — moderately stable data (default global). */
    default: 5 * MINUTE,
    /** 30 minutes — rarely changing data (GitHub org repo list). */
    long: 30 * MINUTE,
  },
  gcTime: {
    /** 15 minutes — default global GC window. */
    default: 15 * MINUTE,
    /** 1 hour — for long-lived rarely-fetched data. */
    long: 1 * HOUR,
  },
} as const;
