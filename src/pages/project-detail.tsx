import { useState } from "react";
import { useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, X, FolderGit2, ArrowLeft } from "lucide-react";
import { toast } from "sonner";

import { useI18n } from "@/i18n/i18n";
import { useNavigationStore } from "@/stores/navigation-store";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { PageLayout } from "@/components/layout/page-layout";
import { PageHeader, PageHeaderTitle } from "@/components/layout/page-header";
import { EmptyState } from "@/components/ui/empty-state";
import {
  projectService,
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

export function ProjectDetailPage() {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const activeProjectId = useNavigationStore((s) => s.activeProjectId);
  const goBack = useNavigationStore((s) => s.goBack);
  const [repoName, setRepoName] = useState("");

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

  const project = projects.find((entry) => entry.id === activeProjectId);
  const projectRepos = repos.filter((repo) => repo.projectId === activeProjectId);

  const refresh = () => {
    queryClient.invalidateQueries({ queryKey: ["project-repos"] });
    queryClient.invalidateQueries({ queryKey: ["repo-sources"] });
  };

  async function addRepo() {
    const value = repoName.trim();
    if (!value || !activeProjectId) return;
    try {
      await projectService.createRepo(activeProjectId, value);
      setRepoName("");
      refresh();
    } catch (error) {
      toast.error(String(error));
    }
  }

  if (!project) {
    return (
      <PageLayout scroll>
        <EmptyState title={t("settings.projects.notFound")} description={t("settings.projects.notFoundDesc")} />
      </PageLayout>
    );
  }

  return (
    <PageLayout className="!p-0 !space-y-0 h-[calc(100vh-4rem)] overflow-hidden">
      <PageHeader className="mx-auto w-full max-w-3xl">
        <div className="flex items-center gap-2">
          <button onClick={goBack} className="text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200">
            <ArrowLeft className="h-4 w-4" />
          </button>
          <PageHeaderTitle>{project.name}</PageHeaderTitle>
        </div>
      </PageHeader>

      <div className="flex h-full min-h-0">
        <div className="min-w-0 flex-1 overflow-y-auto custom-scrollbar p-4 md:p-6">
          <div className="mx-auto flex max-w-3xl flex-col gap-2">
            {projectRepos.length === 0 && (
              <p className="text-sm text-muted-foreground">{t("settings.projects.noRepos")}</p>
            )}
            {projectRepos.map((repo) => (
              <RepoRow
                key={repo.id}
                repo={repo}
                sources={sources.filter((source) => source.projectRepoId === repo.id)}
                githubRepos={githubRepos}
                connected={connected}
                named={named}
                onChange={refresh}
              />
            ))}

            <div className="mt-2 flex gap-2">
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
        </div>
      </div>
    </PageLayout>
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
    <div className="rounded-lg border border-zinc-200/70 p-3 dark:border-zinc-800/70">
      <div className="flex items-center justify-between">
        <span className="text-[13px] font-medium text-zinc-800 dark:text-zinc-100">{repo.name}</span>
        <button onClick={removeRepo} className="text-zinc-400 hover:text-destructive">
          <X className="h-3.5 w-3.5" />
        </button>
      </div>

      <div className="mt-2 flex flex-wrap gap-1.5">
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

      <div className="mt-3 flex gap-2">
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
