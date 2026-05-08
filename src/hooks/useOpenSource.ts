import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef } from "react";
import { toast } from "sonner";

import { cache } from "@/config/cache";
import { useI18n } from "@/i18n/i18n";
import { queryKeys } from "@/lib/query-keys";
import { openSourceService } from "@/services/openSourceService";
import type { OssFilters } from "@/types/openSource";

const STALE_THRESHOLD_MS = 12 * 60 * 60 * 1000;

export function useOssSummary() {
  return useQuery({
    queryKey: queryKeys.ossSummary(),
    queryFn: () => openSourceService.fetchSummary(),
    staleTime: cache.staleTime.long,
    gcTime: cache.gcTime.long,
    retry: (count, err) => {
      const msg = err instanceof Error ? err.message : String(err);
      if (msg.includes("github_not_synced") || msg.includes("github_not_connected")) return false;
      return count < 2;
    },
  });
}

export function useOssRepositories(filters: OssFilters) {
  return useQuery({
    queryKey: queryKeys.ossRepos(filters),
    queryFn: () => openSourceService.fetchRepositories(filters),
    staleTime: cache.staleTime.long,
    gcTime: cache.gcTime.long,
  });
}

export function useOssPullRequests(filters: OssFilters) {
  return useQuery({
    queryKey: queryKeys.ossPullRequests(filters),
    queryFn: () => openSourceService.fetchPullRequests(filters),
    staleTime: cache.staleTime.long,
    gcTime: cache.gcTime.long,
  });
}

export function useOssIssues(filters: OssFilters) {
  return useQuery({
    queryKey: queryKeys.ossIssues(filters),
    queryFn: () => openSourceService.fetchIssues(filters),
    staleTime: cache.staleTime.long,
    gcTime: cache.gcTime.long,
  });
}

export function useOssReviews(filters: OssFilters) {
  return useQuery({
    queryKey: queryKeys.ossReviews(filters),
    queryFn: () => openSourceService.fetchReviews(filters),
    staleTime: cache.staleTime.long,
    gcTime: cache.gcTime.long,
  });
}

export function useOssCalendar(year?: number) {
  return useQuery({
    queryKey: queryKeys.ossCalendar(year),
    queryFn: () => openSourceService.fetchCalendar(year),
    staleTime: cache.staleTime.long,
    gcTime: cache.gcTime.long,
  });
}

export function useOssYearOverview(year: number) {
  return useQuery({
    queryKey: queryKeys.ossYearOverview(year),
    queryFn: () => openSourceService.fetchYearOverview(year),
    staleTime: cache.staleTime.long,
    gcTime: cache.gcTime.long,
  });
}

export function useOssSync() {
  const queryClient = useQueryClient();
  const { t } = useI18n();
  return useMutation({
    mutationFn: () => openSourceService.sync(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["oss"] });
      toast.success(t("openSource.sync.success"));
    },
    onError: (err) => {
      const msg = err instanceof Error ? err.message : String(err);
      toast.error(t("openSource.sync.error"), { description: msg });
    },
  });
}

export function useOssAutoSync(lastSyncedAt: string | null | undefined, connected: boolean) {
  const sync = useOssSync();
  const triggered = useRef(false);

  useEffect(() => {
    if (triggered.current) return;
    if (!connected) return;
    const stale =
      !lastSyncedAt || Date.now() - new Date(lastSyncedAt).getTime() > STALE_THRESHOLD_MS;
    if (stale && !sync.isPending) {
      triggered.current = true;
      sync.mutate(undefined, {
        onError: () => {
          triggered.current = false;
        },
      });
    }
  }, [lastSyncedAt, connected, sync]);
}
