import { useState } from "react";
import { useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Trash2, X, MoreVertical, Link2 } from "lucide-react";
import { toast } from "sonner";

import { useI18n } from "@/i18n/i18n";
import { useNavigationStore } from "@/stores/navigation-store";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { EmptyState } from "@/components/ui/empty-state";
import { AppbarActions } from "@/components/layout/appbar-actions";
import { PageLayout } from "@/components/layout/page-layout";
import {
  projectService,
  type ProjectRepo,
  type RepoSource,
} from "@/services/projectService";
import { trackerService, type TrackerNamed } from "@/services/trackerService";
import { repositorySelectionService } from "@/services/repositorySelectionService";

const VCS_PROVIDERS = ["github", "gitlab", "bitbucket"];

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
  const [addRepoOpen, setAddRepoOpen] = useState(false);
  const [sourceRepo, setSourceRepo] = useState<ProjectRepo | null>(null);

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

  async function removeRepo(id: string) {
    try {
      await projectService.removeRepo(id);
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
      <AppbarActions>
        <Button onClick={() => setAddRepoOpen(true)} title={t("settings.projects.addRepo")}>
          <Plus size={18} />
          <span className="hidden xl:inline">{t("settings.projects.addRepo")}</span>
        </Button>
      </AppbarActions>

      <div className="flex h-full min-h-0">
        <div className="min-w-0 flex-1 overflow-y-auto custom-scrollbar p-4 md:p-6">
          {projectRepos.length === 0 ? (
            <EmptyState title={t("settings.projects.noReposTitle")} description={t("settings.projects.noRepos")} />
          ) : (
            <div className="flex flex-col">
              {projectRepos.map((repo) => (
                <RepoRow
                  key={repo.id}
                  repo={repo}
                  sources={sources.filter((source) => source.projectRepoId === repo.id)}
                  named={named}
                  onAddSource={() => setSourceRepo(repo)}
                  onRemove={() => removeRepo(repo.id)}
                  onChange={refresh}
                />
              ))}
            </div>
          )}
        </div>
      </div>

      <AddRepoDialog
        open={addRepoOpen}
        onOpenChange={setAddRepoOpen}
        projectId={project.id}
        onCreated={refresh}
      />
      <AddSourceDialog
        repo={sourceRepo}
        onOpenChange={(open) => !open && setSourceRepo(null)}
        githubRepos={githubRepos}
        connected={connected}
        onAdded={refresh}
      />
    </PageLayout>
  );
}

function sourceLabel(source: RepoSource, named: Record<string, ProviderNamed>): string {
  if (source.provider === "github") return source.ref;
  const list = source.refType === "team" ? named[source.provider]?.teams : named[source.provider]?.projects;
  return (list ?? []).find((entry) => entry.id === source.ref)?.name ?? source.ref;
}

interface RepoRowProps {
  repo: ProjectRepo;
  sources: RepoSource[];
  named: Record<string, ProviderNamed>;
  onAddSource: () => void;
  onRemove: () => void;
  onChange: () => void;
}

function RepoRow({ repo, sources, named, onAddSource, onRemove, onChange }: RepoRowProps) {
  const { t } = useI18n();

  async function removeSource(id: string) {
    try {
      await projectService.removeSource(id);
      onChange();
    } catch (error) {
      toast.error(String(error));
    }
  }

  return (
    <div className="flex flex-col gap-1.5 rounded-md px-3 py-2.5 transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.03]">
      <div className="flex items-center gap-2.5">
        <span className="truncate text-[13px] font-medium text-zinc-800 dark:text-zinc-100">{repo.name}</span>
        <div className="ml-auto flex items-center gap-2">
          <span className="text-[11px] text-zinc-500 dark:text-zinc-400">
            {sources.length} {t("settings.projects.sourceCount")}
          </span>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button className="flex h-6 w-6 items-center justify-center rounded text-zinc-400 transition-colors hover:bg-zinc-200 hover:text-zinc-700 dark:hover:bg-zinc-700 dark:hover:text-zinc-200">
                <MoreVertical className="h-4 w-4" />
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onSelect={onAddSource}>
                <Link2 className="mr-2 h-4 w-4" />
                {t("settings.projects.addSource")}
              </DropdownMenuItem>
              <DropdownMenuItem onSelect={onRemove} className="text-red-500">
                <Trash2 className="mr-2 h-4 w-4" />
                {t("common.delete")}
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>

      {sources.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {sources.map((source) => (
            <span
              key={source.id}
              className="flex items-center gap-1 rounded-full border border-zinc-200 px-2 py-0.5 text-[11px] text-zinc-600 dark:border-zinc-700 dark:text-zinc-300"
            >
              {source.isVcsTarget && <span className="text-emerald-500">●</span>}
              {sourceLabel(source, named)}
              <button onClick={() => removeSource(source.id)} className="text-zinc-400 hover:text-destructive">
                <X className="h-3 w-3" />
              </button>
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

interface AddRepoDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  projectId: string;
  onCreated: () => void;
}

function AddRepoDialog({ open, onOpenChange, projectId, onCreated }: AddRepoDialogProps) {
  const { t } = useI18n();
  const [name, setName] = useState("");

  async function create() {
    const value = name.trim();
    if (!value) return;
    try {
      await projectService.createRepo(projectId, value);
      setName("");
      onOpenChange(false);
      onCreated();
    } catch (error) {
      toast.error(String(error));
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(value) => {
        onOpenChange(value);
        if (!value) setName("");
      }}
    >
      <DialogContent className="max-w-[420px] gap-0 overflow-hidden p-0">
        <DialogHeader className="border-b border-border px-5 pt-5 pb-4">
          <DialogTitle className="text-base">{t("settings.projects.addRepo")}</DialogTitle>
          <p className="mt-1.5 text-sm text-muted-foreground">{t("settings.projects.addRepoDescription")}</p>
        </DialogHeader>
        <div className="flex flex-col gap-4 px-5 py-4">
          <div className="flex flex-col gap-2">
            <Label>{t("settings.projects.repoNameLabel")}</Label>
            <Input
              autoFocus
              value={name}
              onChange={(event) => setName(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter") create();
              }}
              placeholder={t("settings.projects.repoNamePlaceholder")}
            />
          </div>
          <DialogFooter className="flex gap-2 px-0 pb-0 pt-0">
            <Button variant="outline" size="sm" onClick={() => onOpenChange(false)}>
              {t("common.cancel")}
            </Button>
            <Button
              size="sm"
              onClick={create}
              disabled={!name.trim()}
              className="flex-1 bg-purple-600 text-white hover:bg-purple-700"
            >
              {t("settings.projects.addRepo")}
            </Button>
          </DialogFooter>
        </div>
      </DialogContent>
    </Dialog>
  );
}

interface AddSourceDialogProps {
  repo: ProjectRepo | null;
  onOpenChange: (open: boolean) => void;
  githubRepos: { organization_id: string; repo_name: string }[];
  connected: string[];
  onAdded: () => void;
}

function AddSourceDialog({ repo, onOpenChange, githubRepos, connected, onAdded }: AddSourceDialogProps) {
  const { t } = useI18n();
  const [kind, setKind] = useState("github:repo");
  const [ref, setRef] = useState("");

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

  async function add() {
    if (!ref || !repo) return;
    const [provider, refType] = kind.split(":");
    const roles = rolesFor(provider);
    try {
      await projectService.addSource(repo.id, provider, refType, ref, roles.issue, roles.vcs);
      setRef("");
      onOpenChange(false);
      onAdded();
    } catch (error) {
      toast.error(String(error));
    }
  }

  return (
    <Dialog
      open={repo !== null}
      onOpenChange={(value) => {
        onOpenChange(value);
        if (!value) {
          setKind("github:repo");
          setRef("");
        }
      }}
    >
      <DialogContent className="max-w-[420px] gap-0 overflow-hidden p-0">
        <DialogHeader className="border-b border-border px-5 pt-5 pb-4">
          <DialogTitle className="text-base">{t("settings.projects.addSource")}</DialogTitle>
          <p className="mt-1.5 text-sm text-muted-foreground">{t("settings.projects.addSourceDescription")}</p>
        </DialogHeader>
        <div className="flex flex-col gap-4 px-5 py-4">
          <div className="flex flex-col gap-2">
            <Label>{t("settings.projects.sourceTypeLabel")}</Label>
            <Select
              value={kind}
              onValueChange={(value) => {
                setKind(value);
                setRef("");
              }}
            >
              <SelectTrigger className="capitalize">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {kindOptions.map((option) => (
                  <SelectItem key={option.value} value={option.value} className="capitalize">
                    {option.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="flex flex-col gap-2">
            <Label>{t("settings.projects.sourceLabel")}</Label>
            <Select value={ref} onValueChange={setRef}>
              <SelectTrigger>
                <SelectValue placeholder={t("settings.projects.selectSource")} />
              </SelectTrigger>
              <SelectContent>
                {refOptions().map((option) => (
                  <SelectItem key={option.value} value={option.value}>
                    {option.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <DialogFooter className="flex gap-2 px-0 pb-0 pt-0">
            <Button variant="outline" size="sm" onClick={() => onOpenChange(false)}>
              {t("common.cancel")}
            </Button>
            <Button
              size="sm"
              onClick={add}
              disabled={!ref}
              className="flex-1 bg-purple-600 text-white hover:bg-purple-700"
            >
              {t("settings.projects.addSource")}
            </Button>
          </DialogFooter>
        </div>
      </DialogContent>
    </Dialog>
  );
}
