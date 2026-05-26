import { useState } from "react";
import { useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Trash2, MoreVertical, Link2, Check, Folder, FolderGit2 } from "lucide-react";
import { open as openDialog } from "@tauri-apps/plugin-dialog";
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
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
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
        githubRepos={githubRepos}
        onCreated={refresh}
      />
      <AddSourceDialog
        repo={sourceRepo}
        onOpenChange={(open) => !open && setSourceRepo(null)}
        connected={connected}
        onAdded={refresh}
      />
    </PageLayout>
  );
}

const VCS_KINDS = ["github", "gitlab", "bitbucket", "local"];

function sourceLabel(source: RepoSource, named: Record<string, ProviderNamed>): string {
  if (VCS_KINDS.includes(source.provider)) return source.provider;
  const list = source.refType === "team" ? named[source.provider]?.teams : named[source.provider]?.projects;
  const name = (list ?? []).find((entry) => entry.id === source.ref)?.name ?? source.ref;
  return `${source.provider}: ${name}`;
}

interface RepoRowProps {
  repo: ProjectRepo;
  sources: RepoSource[];
  named: Record<string, ProviderNamed>;
  onAddSource: () => void;
  onRemove: () => void;
  onChange: () => void;
}

function RepoRow({ repo, sources, named, onAddSource, onRemove }: RepoRowProps) {
  const { t } = useI18n();

  return (
    <div className="group flex h-10 items-center gap-2.5 rounded-md px-3 transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.03]">
      <FolderGit2 className="h-4 w-4 shrink-0 text-zinc-400" />
      <span className="shrink-0 truncate text-[13px] font-medium text-zinc-800 dark:text-zinc-100">{repo.name}</span>

      <div className="ml-auto flex min-w-0 items-center gap-2">
        <div className="flex min-w-0 items-center gap-1.5 overflow-hidden">
          {sources.map((source) => (
            <span
              key={source.id}
              className="flex shrink-0 items-center gap-1 rounded-full border border-zinc-200 px-2 py-0.5 text-[11px] capitalize text-zinc-600 dark:border-zinc-700 dark:text-zinc-300"
            >
              {source.isVcsTarget && <span className="text-emerald-500">●</span>}
              {sourceLabel(source, named)}
            </span>
          ))}
        </div>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button className="flex h-6 w-6 shrink-0 items-center justify-center rounded text-zinc-400 transition-colors hover:bg-zinc-200 hover:text-zinc-700 dark:hover:bg-zinc-700 dark:hover:text-zinc-200">
              <MoreVertical className="h-4 w-4" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onSelect={onAddSource}>
              <Link2 className="mr-2 h-4 w-4" />
              {t("settings.projects.addProvider")}
            </DropdownMenuItem>
            <DropdownMenuItem onSelect={onRemove} className="text-red-500">
              <Trash2 className="mr-2 h-4 w-4" />
              {t("common.delete")}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  );
}

interface AddRepoDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  projectId: string;
  githubRepos: { organization_id: string; repo_name: string }[];
  onCreated: () => void;
}

function parseGitUrl(input: string): { provider: string; owner: string; name: string } | null {
  const value = input.trim();
  if (!value) return null;
  let host = "";
  let path = "";
  const ssh = value.match(/^git@([^:]+):(.+)$/);
  if (ssh) {
    host = ssh[1];
    path = ssh[2];
  } else {
    try {
      const url = new URL(value);
      host = url.hostname;
      path = url.pathname.replace(/^\//, "");
    } catch {
      return null;
    }
  }
  path = path.replace(/\.git$/, "");
  const [owner, name] = path.split("/");
  if (!owner || !name) return null;
  const provider = host.includes("gitlab") ? "gitlab" : host.includes("bitbucket") ? "bitbucket" : "github";
  return { provider, owner, name };
}

function AddRepoDialog({ open, onOpenChange, projectId, githubRepos, onCreated }: AddRepoDialogProps) {
  const { t } = useI18n();
  const [tab, setTab] = useState("existing");
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [url, setUrl] = useState("");
  const [localPath, setLocalPath] = useState("");

  function reset() {
    setQuery("");
    setSelected(new Set());
    setUrl("");
    setLocalPath("");
    setTab("existing");
  }

  function toggle(ref: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(ref)) next.delete(ref);
      else next.add(ref);
      return next;
    });
  }

  async function handleBrowse() {
    try {
      const picked = await openDialog({ directory: true, multiple: false });
      if (picked && typeof picked === "string") setLocalPath(picked);
    } catch (error) {
      console.error("Failed to select directory:", error);
    }
  }

  const filteredRepos = githubRepos.filter((entry) =>
    entry.repo_name.toLowerCase().includes(query.trim().toLowerCase()),
  );

  async function addRepoWithSource(provider: string, ref: string, name: string) {
    const repo = await projectService.createRepo(projectId, name);
    await projectService.addSource(repo.id, provider, "repo", ref, true, true);
  }

  async function submit() {
    try {
      if (tab === "existing") {
        if (selected.size === 0) return;
        for (const ref of selected) {
          const repo = githubRepos.find((entry) => `${entry.organization_id}/${entry.repo_name}` === ref);
          if (repo) await addRepoWithSource("github", ref, repo.repo_name);
        }
      } else if (tab === "url") {
        const parsed = parseGitUrl(url);
        if (!parsed) {
          toast.error(t("settings.projects.invalidUrl"));
          return;
        }
        await addRepoWithSource(parsed.provider, `${parsed.owner}/${parsed.name}`, parsed.name);
      } else {
        const path = localPath.trim();
        if (!path) return;
        const name = path.split("/").filter(Boolean).pop() ?? path;
        await addRepoWithSource("local", path, name);
      }
      reset();
      onOpenChange(false);
      onCreated();
    } catch (error) {
      toast.error(String(error));
    }
  }

  const canSubmit = tab === "existing" ? selected.size > 0 : tab === "url" ? !!url.trim() : !!localPath.trim();

  return (
    <Dialog
      open={open}
      onOpenChange={(value) => {
        onOpenChange(value);
        if (!value) reset();
      }}
    >
      <DialogContent className="max-w-[440px] gap-0 overflow-hidden p-0">
        <DialogHeader className="border-b border-border px-5 pt-5 pb-4">
          <DialogTitle className="text-base">{t("settings.projects.addRepo")}</DialogTitle>
          <p className="mt-1.5 text-sm text-muted-foreground">{t("settings.projects.addRepoDescription")}</p>
        </DialogHeader>
        <div className="flex flex-col gap-4 px-5 py-4">
          <Tabs value={tab} onValueChange={setTab}>
            <TabsList variant="line" className="mb-4 h-auto gap-6">
              <TabsTrigger value="existing">{t("settings.projects.addRepo.existing")}</TabsTrigger>
              <TabsTrigger value="url">{t("settings.projects.addRepo.url")}</TabsTrigger>
              <TabsTrigger value="local">{t("settings.projects.addRepo.local")}</TabsTrigger>
            </TabsList>

            <TabsContent value="existing" className="mt-0 space-y-2">
              <Input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder={t("settings.projects.selectRepo")}
              />
              <div className="max-h-[260px] overflow-y-auto rounded-md border border-zinc-200 dark:border-zinc-800">
                {filteredRepos.length === 0 ? (
                  <div className="px-3 py-8 text-center text-[13px] text-muted-foreground">
                    {t("settings.projects.noReposMatch")}
                  </div>
                ) : (
                  <div className="p-1">
                    {filteredRepos.map((entry) => {
                      const ref = `${entry.organization_id}/${entry.repo_name}`;
                      const isOn = selected.has(ref);
                      return (
                        <button
                          key={ref}
                          type="button"
                          onClick={() => toggle(ref)}
                          className={`flex w-full items-center gap-2 rounded-md px-2.5 py-2 text-left text-[13px] transition-colors hover:bg-accent ${isOn ? "bg-accent font-medium" : "text-zinc-700 dark:text-zinc-300"}`}
                        >
                          <Check className={`h-3.5 w-3.5 shrink-0 ${isOn ? "text-purple-500" : "text-transparent"}`} />
                          {entry.repo_name}
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>
            </TabsContent>

            <TabsContent value="url" className="mt-0">
              <Input
                autoFocus
                value={url}
                onChange={(event) => setUrl(event.target.value)}
                placeholder="https://github.com/owner/repo.git"
              />
            </TabsContent>

            <TabsContent value="local" className="mt-0">
              <div className="flex gap-2">
                <Input
                  value={localPath}
                  onChange={(event) => setLocalPath(event.target.value)}
                  placeholder="/path/to/repo"
                />
                <Button variant="outline" size="sm" onClick={handleBrowse} className="gap-1.5">
                  <Folder className="h-4 w-4" />
                  {t("dialogs.addRepository.browse")}
                </Button>
              </div>
            </TabsContent>
          </Tabs>

          <DialogFooter className="flex gap-2 px-0 pb-0 pt-0">
            <Button variant="outline" size="sm" onClick={() => onOpenChange(false)}>
              {t("common.cancel")}
            </Button>
            <Button
              size="sm"
              onClick={submit}
              disabled={!canSubmit}
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
  connected: string[];
  onAdded: () => void;
}

function AddSourceDialog({ repo, onOpenChange, connected, onAdded }: AddSourceDialogProps) {
  const { t } = useI18n();
  const [kind, setKind] = useState("");
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

  const kindOptions = connected.flatMap((provider) => [
    { value: `${provider}:project`, label: `${provider} · ${t("settings.projects.kind.project")}` },
    { value: `${provider}:team`, label: `${provider} · ${t("settings.projects.kind.team")}` },
  ]);

  function refOptions(): { value: string; label: string }[] {
    if (!kind) return [];
    const [provider, refType] = kind.split(":");
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
          setKind("");
          setRef("");
        }
      }}
    >
      <DialogContent className="max-w-[420px] gap-0 overflow-hidden p-0">
        <DialogHeader className="border-b border-border px-5 pt-5 pb-4">
          <DialogTitle className="text-base">{t("settings.projects.addProvider")}</DialogTitle>
          <p className="mt-1.5 text-sm text-muted-foreground">{t("settings.projects.addProviderDescription")}</p>
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
                <SelectValue placeholder={t("settings.projects.selectProvider")} />
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
