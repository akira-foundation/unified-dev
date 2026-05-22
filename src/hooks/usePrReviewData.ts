import { useQuery } from "@tanstack/react-query";
import { invoke } from "@tauri-apps/api/core";

import { queryKeys } from "@/lib/query-keys";
import { cache } from "@/config/cache";
import type { ActiveRepo } from "@/stores/navigation-store";
import type { CiCheckDto, PrFileDto, PullRequestDto } from "@/types/organization";

export function usePrReviewData(repo: ActiveRepo | null, pr: PullRequestDto | null) {
  const files = useQuery({
    queryKey: queryKeys.prFiles(repo?.organizationId ?? "", repo?.name ?? "", pr?.number ?? 0),
    queryFn: () =>
      invoke<PrFileDto[]>("get_pr_files", {
        organizationId: repo!.organizationId,
        repoName: repo!.name,
        prNumber: pr!.number,
      }),
    enabled: !!pr && !!repo,
    staleTime: cache.staleTime.default,
    gcTime: cache.gcTime.long,
  });

  const checks = useQuery({
    queryKey: queryKeys.prChecks(repo?.organizationId ?? "", repo?.name ?? "", pr?.head_sha ?? ""),
    queryFn: () =>
      invoke<CiCheckDto[]>("get_pr_checks", {
        organizationId: repo!.organizationId,
        repoName: repo!.name,
        headSha: pr!.head_sha,
      }),
    enabled: !!pr && !!repo && !!pr.head_sha,
    staleTime: cache.staleTime.default,
    gcTime: cache.gcTime.long,
  });

  return {
    files: files.data ?? [],
    filesLoading: files.isLoading,
    checks: checks.data ?? [],
    checksLoading: checks.isLoading,
  };
}
