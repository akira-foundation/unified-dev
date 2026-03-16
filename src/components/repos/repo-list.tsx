import type { OrganizationRepoSummary } from "../../types/organization";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../ui/card";
import { EmptyState } from "../ui/empty-state";
import { RepoItem } from "./repo-item";
import { useI18n } from "../../i18n/i18n";

interface RepoListProps {
  repos: OrganizationRepoSummary[];
}

export function RepoList({ repos }: RepoListProps) {
  const { t } = useI18n();
  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("components.repoList.title")}</CardTitle>
        <CardDescription>{t("components.repoList.description")}</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {repos.length === 0 ? (
          <EmptyState
            title={t("components.repoList.empty.title")}
            description={t("components.repoList.empty.description")}
          />
        ) : (
          repos.map((repo) => <RepoItem key={repo.id} repo={repo} />)
        )}
      </CardContent>
    </Card>
  );
}
