import type { OrganizationRepoSummary } from "../../types/organization";
import { useI18n } from "../../i18n/i18n";

interface RepoItemProps {
  repo: OrganizationRepoSummary;
}

export function RepoItem({ repo }: RepoItemProps) {
  const { t } = useI18n();
  return (
    <div className="flex items-center justify-between rounded-xl border  px-4 py-3 ">
      <div>
        <div className="text-sm font-semibold text-gray-900 dark:text-white">
          {repo.owner}/{repo.repo_name}
        </div>
        <div className="text-xs text-gray-500 dark:text-gray-400">
          {t("components.repoItem.autoSync")} {repo.auto_sync ? t("components.repoItem.on") : t("components.repoItem.off")}
        </div>
      </div>
    </div>
  );
}
