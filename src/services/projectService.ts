import { invoke } from "@tauri-apps/api/core";

export interface Project {
  id: string;
  name: string;
  provider: string;
  externalId?: string | null;
  color?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface ProjectSource {
  id: string;
  projectId: string;
  provider: string;
  refType: string;
  ref: string;
  createdAt: string;
}

export const projectService = {
  list(): Promise<Project[]> {
    return invoke<Project[]>("project_list");
  },
  listSources(): Promise<ProjectSource[]> {
    return invoke<ProjectSource[]>("project_list_sources");
  },
  create(name: string, color?: string | null): Promise<Project> {
    return invoke<Project>("project_create", { name, color: color ?? null });
  },
  update(id: string, name?: string | null, color?: string | null): Promise<Project> {
    return invoke<Project>("project_update", { id, name: name ?? null, color: color ?? null });
  },
  remove(id: string): Promise<void> {
    return invoke<void>("project_delete", { id });
  },
  addSource(
    projectId: string,
    provider: string,
    refType: string,
    reference: string,
  ): Promise<ProjectSource> {
    return invoke<ProjectSource>("project_add_source", {
      projectId,
      provider,
      refType,
      reference,
    });
  },
  removeSource(id: string): Promise<void> {
    return invoke<void>("project_remove_source", { id });
  },
  import(provider: string): Promise<Project[]> {
    return invoke<Project[]>("project_import", { provider });
  },
};

export function sourceKey(provider: string, refType: string, ref: string): string {
  return `${provider}:${refType}:${ref}`;
}

export function buildProjectSourceMap(
  projects: Project[],
  sources: ProjectSource[],
): Map<string, Project> {
  const byId = new Map(projects.map((project) => [project.id, project]));
  const map = new Map<string, Project>();
  for (const source of sources) {
    const project = byId.get(source.projectId);
    if (project) map.set(sourceKey(source.provider, source.refType, source.ref), project);
  }
  return map;
}
