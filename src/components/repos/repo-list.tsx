import type { OrganizationRepoSummary } from "../../types/organization";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../ui/card";
import { EmptyState } from "../ui/empty-state";
import { RepoItem } from "./repo-item";

interface RepoListProps {
  repos: OrganizationRepoSummary[];
}

export function RepoList({ repos }: RepoListProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Repositories</CardTitle>
        <CardDescription>Repositories attached to the selected organization.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {repos.length === 0 ? (
          <EmptyState
            title="No repositories yet"
            description="Import repositories from your organizations to start tracking activity."
          />
        ) : (
          repos.map((repo) => <RepoItem key={repo.id} repo={repo} />)
        )}
      </CardContent>
    </Card>
  );
}
