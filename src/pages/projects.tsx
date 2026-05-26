import { useState } from "react";
import { useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Trash2, X, FolderGit2 } from "lucide-react";
import { toast } from "sonner";

import { useI18n } from "@/i18n/i18n";
import { useHotkey } from "@/hooks/useHotkey";
import { useOrganizations } from "@/hooks/useOrganizations";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { EmptyState } from "@/components/ui/empty-state";
import { AppbarActions } from "@/components/layout/appbar-actions";
import { PageLayout } from "@/components/layout/page-layout";
import {
  projectService,
  type Project,
  type ProjectRepo,
  type RepoSource,
} from "@/services/projectService";
import { trackerService, type TrackerNamed } from "@/services/trackerService";
import { repositorySelectionService } from "@/services/repositorySelectionService";

const VCS_PROVIDERS = ["github", "gitlab", "bitbucket"];
const SELECT =
  "h-8 rounded-md border border-zinc-200 bg-zinc-100 px-2 text-xs text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300";

interface ProviderNamed {
  projects: TrackerNamed[];
  teams: TrackerNamed[];
}

function rolesFor(provider: string): { issue: boolean; vcs: boolean } {
  return { issue: true, vcs: VCS_PROVIDERS.includes(provider) };
}

export function ProjectsPage() {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const { organizations } = useOrganizations();
  const [createOpen, setCreateOpen] = useState(false);
  const [name, setName] = useState("");
  const [orgId, setOrgId] = useState("");

  useHotkey("n", () => setCreateOpen(true));

  const { data: projects = [] } = useQuery({ queryKey: ["projects"], queryFn: () => projectService.list() });
  const { data: repos = [] } = useQuery({ queryKey: ["project-repos"], queryFn: () => projectService.listRepos() });
  const { data: sources = [] } = useQuery({ queryKey: ["repo-sources"], queryFn: () => projectService.listSources() });

  const { data: githubRepos = [] } = useQuery({
    queryKey: ["all-selected-repositories"],
    queryFn: () => repositorySelectionService.listAllSelectedRepositories(),
  });
  const { data: trackerProviders = [] } = useQuery({
    queryKey: ["tracker-providers"],
    queryFn: () => trackerService.providers(),
  });
  const statusQueries = useQueries({
    queries: trackerProviders.map((provider) => ({
      queryKey: ["tracker-status", provider],
      queryFn: () => trackerService.status(provider),
    })),
  });
  const connected = trackerProviders.filter((_, index) => statusQueries[index]?.data);
  const namedQueries = useQueries({
    queries: connected.flatMap((provider) => [
      { queryKey: ["tracker-list-projects", provider], queryFn: () => trackerService.listProjects(provider) },
      { queryKey: ["tracker-list-teams", provider], queryFn: () => trackerService.listTeams(provider) },
    ]),
  });
  const named: Record<string, ProviderNamed> = {};
  connected.forEach((provider, index) => {
    named[provider] = {
      projects: (namedQueries[2 * index]?.data as TrackerNamed[]) ?? [],
      teams: (namedQueries[2 * index + 1]?.data as TrackerNamed[]) ?? [],
    };
  });

  const refresh = () => {
    queryClient.invalidateQueries({ queryKey: ["projects"] });
    queryClient.invalidateQueries({ queryKey: ["project-repos"] });
    queryClient.invalidateQueries({ queryKey: ["repo-sources"] });
  };

  async function createProject() {
    const value = name.trim();
    if (!value) return;
    try {
      await projectService.create(value, orgId || null);
      setName("");
      setOrgId("");
      setCreateOpen(false);
      refresh();
    } catch (error) {
      toast.error(String(error));
    }
  }

  async function removeProject(id: string) {
    try {
      await projectService.remove(id);
      refresh();
    } catch (error) {
      toast.error(String(error));
    }
  }

  return (
    <PageLayout className="!p-0 !space-y-0 h-[calc(100vh-4rem)] overflow-hidden">
      <AppbarActions>
        <Button onClick={() => setCreateOpen(true)} title={t("settings.projects.create")}>
          <Plus size={18} />
          <span className="hidden xl:inline">{t("settings.projects.create")}</span>
        </Button>
      </AppbarActions>

      <div className="flex h-full min-h-0">
        <div className="min-w-0 flex-1 overflow-y-auto custom-scrollbar p-4 md:p-6">
          {projects.length === 0 ? (
            <EmptyState
              title={t("settings.projects.emptyTitle")}
              description={t("settings.projects.empty")}
            />
          ) : (
            <div className="mx-auto flex max-w-3xl flex-col gap-3">
              {projects.map((project) => (
                <ProjectCard
                  key={project.id}
                  project={project}
                  repos={repos.filter((repo) => repo.projectId === project.id)}
                  sources={sources}
                  githubRepos={githubRepos}
                  connected={connected}
                  named={named}
                  onChange={refresh}
                  onDelete={() => removeProject(project.id)}
                />
              ))}
            </div>
          )}
        </div>
      </div>

      <Dialog
        open={createOpen}
        onOpenChange={(open) => {
          setCreateOpen(open);
          if (!open) {
            setName("");
            setOrgId("");
          }
        }}
      >
        <DialogContent className="max-w-[420px]">
          <DialogHeader>
            <DialogTitle>{t("settings.projects.create")}</DialogTitle>
          </DialogHeader>
          <div className="flex flex-col gap-2">
            <Input
              autoFocus
              value={name}
              onChange={(event) => setName(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter") createProject();
              }}
              placeholder={t("settings.projects.namePlaceholder")}
              className="h-9"
            />
            <select value={orgId} onChange={(event) => setOrgId(event.target.value)} className={`${SELECT} h-9`}>
              <option value="">{t("settings.projects.noOrg")}</option>
              {organizations.map((org) => (
                <option key={org.id} value={org.id}>
                  {org.name}
                </option>
              ))}
            </select>
          </div>
          <DialogFooter>
            <Button variant="outline" size="sm" onClick={() => setCreateOpen(false)}>
              {t("common.cancel")}
            </Button>
            <Button size="sm" onClick={createProject} disabled={!name.trim()}>
              {t("settings.projects.create")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </PageLayout>
  );
}

interface ProjectCardProps {
  project: Project;
  repos: ProjectRepo[];
  sources: RepoSource[];
  githubRepos: { organization_id: string; repo_name: string }[];
  connected: string[];
  named: Record<string, ProviderNamed>;
  onChange: () => void;
  onDelete: () => void;
}

function ProjectCard({
  project,
  repos,
  sources,
  githubRepos,
  connected,
  named,
  onChange,
  onDelete,
}: ProjectCardProps) {
  const { t } = useI18n();
  const [repoName, setRepoName] = useState("");

  async function addRepo() {
    const value = repoName.trim();
    if (!value) return;
    try {
      await projectService.createRepo(project.id, value);
      setRepoName("");
      onChange();
    } catch (error) {
      toast.error(String(error));
    }
  }

  return (
    <div className="rounded-lg border border-zinc-200/70 p-3 dark:border-zinc-800/70">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-zinc-800 dark:text-zinc-100">{project.name}</span>
          {project.orgId && (
            <span className="rounded bg-zinc-500/10 px-1.5 py-0.5 text-[10px] font-medium text-zinc-500">org</span>
          )}
        </div>
        <Button variant="ghost" size="icon" onClick={onDelete} className="h-7 w-7 text-zinc-400 hover:text-destructive">
          <Trash2 className="h-4 w-4" />
        </Button>
      </div>

      <div className="mt-3 flex flex-col gap-2">
        {repos.map((repo) => (
          <RepoRow
            key={repo.id}
            repo={repo}
            sources={sources.filter((source) => source.projectRepoId === repo.id)}
            githubRepos={githubRepos}
            connected={connected}
            named={named}
            onChange={onChange}
          />
        ))}
      </div>

      <div className="mt-3 flex gap-2">
        <Input
          value={repoName}
          onChange={(event) => setRepoName(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") addRepo();
          }}
          placeholder={t("settings.projects.repoNamePlaceholder")}
          className="h-8"
        />
        <Button size="sm" variant="outline" onClick={addRepo} disabled={!repoName.trim()} className="gap-1.5">
          <FolderGit2 className="h-4 w-4" />
          {t("settings.projects.addRepo")}
        </Button>
      </div>
    </div>
  );
}

interface RepoRowProps {
  repo: ProjectRepo;
  sources: RepoSource[];
  githubRepos: { organization_id: string; repo_name: string }[];
  connected: string[];
  named: Record<string, ProviderNamed>;
  onChange: () => void;
}

function RepoRow({ repo, sources, githubRepos, connected, named, onChange }: RepoRowProps) {
  const { t } = useI18n();
  const [kind, setKind] = useState("github:repo");
  const [ref, setRef] = useState("");

  const kindOptions = [
    { value: "github:repo", label: t("settings.projects.kind.repo") },
    ...connected.flatMap((provider) => [
      { value: `${provider}:project`, label: `${provider} · ${t("settings.projects.kind.project")}` },
      { value: `${provider}:team`, label: `${provider} · ${t("settings.projects.kind.team")}` },
    ]),
  ];

  function refOptions(): { value: string; label: string }[] {
    const [provider, refType] = kind.split(":");
    if (provider === "github") {
      return githubRepos.map((entry) => ({
        value: `${entry.organization_id}/${entry.repo_name}`,
        label: entry.repo_name,
      }));
    }
    const list = refType === "team" ? named[provider]?.teams : named[provider]?.projects;
    return (list ?? []).map((entry) => ({ value: entry.id, label: entry.name }));
  }

  function sourceLabel(source: RepoSource): string {
    if (source.provider === "github") return source.ref;
    const list = source.refType === "team" ? named[source.provider]?.teams : named[source.provider]?.projects;
    return (list ?? []).find((entry) => entry.id === source.ref)?.name ?? source.ref;
  }

  async function addSource() {
    if (!ref) return;
    const [provider, refType] = kind.split(":");
    const roles = rolesFor(provider);
    try {
      await projectService.addSource(repo.id, provider, refType, ref, roles.issue, roles.vcs);
      setRef("");
      onChange();
    } catch (error) {
      toast.error(String(error));
    }
  }

  async function removeSource(id: string) {
    try {
      await projectService.removeSource(id);
      onChange();
    } catch (error) {
      toast.error(String(error));
    }
  }

  async function removeRepo() {
    try {
      await projectService.removeRepo(repo.id);
      onChange();
    } catch (error) {
      toast.error(String(error));
    }
  }

  return (
    <div className="rounded-md bg-zinc-50 p-2.5 dark:bg-zinc-900/40">
      <div className="flex items-center justify-between">
        <span className="text-[13px] font-medium text-zinc-700 dark:text-zinc-200">{repo.name}</span>
        <button onClick={removeRepo} className="text-zinc-400 hover:text-destructive">
          <X className="h-3.5 w-3.5" />
        </button>
      </div>

      <div className="mt-1.5 flex flex-wrap gap-1.5">
        {sources.length === 0 && (
          <span className="text-[11px] text-muted-foreground">{t("settings.projects.noSources")}</span>
        )}
        {sources.map((source) => (
          <span
            key={source.id}
            className="flex items-center gap-1 rounded-full border border-zinc-200 px-2 py-0.5 text-[11px] text-zinc-600 dark:border-zinc-700 dark:text-zinc-300"
          >
            {source.isVcsTarget && <span className="text-emerald-500">●</span>}
            {sourceLabel(source)}
            <button onClick={() => removeSource(source.id)} className="text-zinc-400 hover:text-destructive">
              <X className="h-3 w-3" />
            </button>
          </span>
        ))}
      </div>

      <div className="mt-2 flex gap-2">
        <select
          value={kind}
          onChange={(event) => {
            setKind(event.target.value);
            setRef("");
          }}
          className={`${SELECT} capitalize`}
        >
          {kindOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
        <select value={ref} onChange={(event) => setRef(event.target.value)} className={`${SELECT} flex-1`}>
          <option value="">{t("settings.projects.selectSource")}</option>
          {refOptions().map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
        <Button size="sm" variant="outline" onClick={addSource} disabled={!ref} className="gap-1.5">
          <Plus className="h-4 w-4" />
          {t("settings.projects.addSource")}
        </Button>
      </div>
    </div>
  );
}
