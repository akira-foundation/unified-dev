import { RepoList } from "../components/repos/repo-list";
import type { OrganizationRepoSummary } from "../types/organization";

const repos: OrganizationRepoSummary[] = [];

export function RepositoryPage() {
  return (
    <div className="flex flex-col gap-6">
      <RepoList repos={repos} />
    </div>
  );
}
