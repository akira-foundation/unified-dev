import type { OrganizationRepoSummary } from "../../types/organization";

interface RepoItemProps {
  repo: OrganizationRepoSummary;
}

export function RepoItem({ repo }: RepoItemProps) {
  return (
    <div className="flex items-center justify-between rounded-xl border  px-4 py-3 ">
      <div>
        <div className="text-sm font-semibold text-gray-900 dark:text-white">
          {repo.owner}/{repo.repo_name}
        </div>
        <div className="text-xs text-gray-500 dark:text-gray-400">
          Auto sync: {repo.auto_sync ? "On" : "Off"}
        </div>
      </div>
    </div>
  );
}
