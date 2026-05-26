import { invoke } from "@tauri-apps/api/core";

export interface Project {
  id: string;
  name: string;
  provider: string;
  externalId?: string | null;
  color?: string | null;
  orgId?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface ProjectRepo {
  id: string;
  projectId: string;
  name: string;
  defaultVcsSourceId?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface RepoSource {
  id: string;
  projectRepoId: string;
  provider: string;
  refType: string;
  ref: string;
  isIssueSource: boolean;
  isVcsTarget: boolean;
  createdAt: string;
}

export const projectService = {
  list(): Promise<Project[]> {
    return invoke<Project[]>("project_list");
  },
  create(name: string, orgId?: string | null, color?: string | null): Promise<Project> {
    return invoke<Project>("project_create", { name, orgId: orgId ?? null, color: color ?? null });
  },
  update(id: string, name?: string | null, color?: string | null): Promise<Project> {
    return invoke<Project>("project_update", { id, name: name ?? null, color: color ?? null });
  },
  remove(id: string): Promise<void> {
    return invoke<void>("project_delete", { id });
  },
  listRepos(): Promise<ProjectRepo[]> {
    return invoke<ProjectRepo[]>("project_repo_list");
  },
  createRepo(projectId: string, name: string): Promise<ProjectRepo> {
    return invoke<ProjectRepo>("project_repo_create", { projectId, name });
  },
  updateRepo(id: string, name?: string | null, defaultVcsSourceId?: string | null): Promise<ProjectRepo> {
    return invoke<ProjectRepo>("project_repo_update", {
      id,
      name: name ?? null,
      defaultVcsSourceId: defaultVcsSourceId ?? null,
    });
  },
  removeRepo(id: string): Promise<void> {
    return invoke<void>("project_repo_delete", { id });
  },
  listSources(): Promise<RepoSource[]> {
    return invoke<RepoSource[]>("repo_source_list");
  },
  addSource(
    projectRepoId: string,
    provider: string,
    refType: string,
    reference: string,
    isIssueSource: boolean,
    isVcsTarget: boolean,
  ): Promise<RepoSource> {
    return invoke<RepoSource>("repo_source_add", {
      projectRepoId,
      provider,
      refType,
      reference,
      isIssueSource,
      isVcsTarget,
    });
  },
  removeSource(id: string): Promise<void> {
    return invoke<void>("repo_source_remove", { id });
  },
};

export function sourceKey(provider: string, refType: string, ref: string): string {
  return `${provider}:${refType}:${ref}`;
}

export interface SourceTarget {
  project: Project;
  repo: ProjectRepo;
}

export function buildProjectSourceMap(
  projects: Project[],
  repos: ProjectRepo[],
  sources: RepoSource[],
): Map<string, SourceTarget> {
  const projectById = new Map(projects.map((project) => [project.id, project]));
  const repoById = new Map(repos.map((repo) => [repo.id, repo]));
  const map = new Map<string, SourceTarget>();
  for (const source of sources) {
    const repo = repoById.get(source.projectRepoId);
    const project = repo ? projectById.get(repo.projectId) : undefined;
    if (repo && project) map.set(sourceKey(source.provider, source.refType, source.ref), { project, repo });
  }
  return map;
}
