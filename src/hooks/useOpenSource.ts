import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { cache } from "@/config/cache";
import { queryKeys } from "@/lib/query-keys";
import { openSourceService } from "@/services/openSourceService";
import type { OssFilters } from "@/types/openSource";

export function useOssSummary() {
  return useQuery({
    queryKey: queryKeys.ossSummary(),
    queryFn: () => openSourceService.fetchSummary(),
    staleTime: cache.staleTime.short,
  });
}

export function useOssRepositories(filters: OssFilters) {
  return useQuery({
    queryKey: queryKeys.ossRepos(filters),
    queryFn: () => openSourceService.fetchRepositories(filters),
    staleTime: cache.staleTime.short,
  });
}

export function useOssPullRequests(filters: OssFilters) {
  return useQuery({
    queryKey: queryKeys.ossPullRequests(filters),
    queryFn: () => openSourceService.fetchPullRequests(filters),
    staleTime: cache.staleTime.short,
  });
}

export function useOssIssues(filters: OssFilters) {
  return useQuery({
    queryKey: queryKeys.ossIssues(filters),
    queryFn: () => openSourceService.fetchIssues(filters),
    staleTime: cache.staleTime.short,
  });
}

export function useOssReviews(filters: OssFilters) {
  return useQuery({
    queryKey: queryKeys.ossReviews(filters),
    queryFn: () => openSourceService.fetchReviews(filters),
    staleTime: cache.staleTime.short,
  });
}

export function useOssCalendar(year?: number) {
  return useQuery({
    queryKey: queryKeys.ossCalendar(year),
    queryFn: () => openSourceService.fetchCalendar(year),
    staleTime: cache.staleTime.default,
  });
}

export function useOssSync() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => openSourceService.sync(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["oss"] });
    },
  });
}
