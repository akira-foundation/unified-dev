import { useState } from "react";
import { useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Trash2, Eye, FolderKanban, MoreVertical, Download } from "lucide-react";
import { toast } from "sonner";

import { useI18n } from "@/i18n/i18n";
import { useHotkey } from "@/hooks/useHotkey";
import { useOrganizations } from "@/hooks/useOrganizations";
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
import { projectService, type Project } from "@/services/projectService";
import { trackerService } from "@/services/trackerService";
import { ImportProjectsDialog } from "@/components/projects/import-projects-dialog";
import { ProviderIcon } from "@/components/projects/provider-icon";

export function ProjectsPage() {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const { organizations } = useOrganizations();
  const navigateTo = useNavigationStore((s) => s.navigateTo);
  const setActiveProjectId = useNavigationStore((s) => s.setActiveProjectId);
  const [createOpen, setCreateOpen] = useState(false);
  const [name, setName] = useState("");
  const [orgId, setOrgId] = useState("");
  const [importProvider, setImportProvider] = useState<string | null>(null);

  useHotkey("n", () => setCreateOpen(true));

  const { data: projects = [] } = useQuery({ queryKey: ["projects"], queryFn: () => projectService.list() });
  const { data: repos = [] } = useQuery({ queryKey: ["project-repos"], queryFn: () => projectService.listRepos() });

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

  const repoCount = (projectId: string) => repos.filter((repo) => repo.projectId === projectId).length;

  function open(id: string) {
    setActiveProjectId(id);
    navigateTo("project-detail");
  }

  async function createProject() {
    const value = name.trim();
    if (!value) return;
    try {
      const project = await projectService.create(value, orgId || null);
      setName("");
      setOrgId("");
      setCreateOpen(false);
      queryClient.invalidateQueries({ queryKey: ["projects"] });
      open(project.id);
    } catch (error) {
      toast.error(String(error));
    }
  }

  async function removeProject(id: string) {
    try {
      await projectService.remove(id);
      queryClient.invalidateQueries({ queryKey: ["projects"] });
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
        {connected.length > 0 && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" className="gap-2">
                <Download className="h-4 w-4" />
                <span className="hidden xl:inline">{t("settings.projects.import")}</span>
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              {connected.map((provider) => (
                <DropdownMenuItem key={provider} onClick={() => setImportProvider(provider)} className="capitalize">
                  <ProviderIcon provider={provider} className="mr-2 h-4 w-4" />
                  {provider}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </AppbarActions>

      <div className="flex h-full min-h-0">
        <div className="min-w-0 flex-1 overflow-y-auto custom-scrollbar p-4 md:p-6">
          {projects.length === 0 ? (
            <EmptyState
              title={t("settings.projects.emptyTitle")}
              description={t("settings.projects.empty")}
            />
          ) : (
            <div className="flex flex-col">
              {projects.map((project) => (
                <ProjectRow
                  key={project.id}
                  project={project}
                  repoCount={repoCount(project.id)}
                  onOpen={() => open(project.id)}
                  onDelete={() => removeProject(project.id)}
                />
              ))}
            </div>
          )}
        </div>
      </div>

      <Dialog
        open={createOpen}
        onOpenChange={(value) => {
          setCreateOpen(value);
          if (!value) {
            setName("");
            setOrgId("");
          }
        }}
      >
        <DialogContent className="max-w-[420px] gap-0 overflow-hidden p-0">
          <DialogHeader className="border-b border-border px-5 pt-5 pb-4">
            <DialogTitle className="text-base">{t("settings.projects.create")}</DialogTitle>
            <p className="mt-1.5 text-sm text-muted-foreground">{t("settings.projects.createDescription")}</p>
          </DialogHeader>
          <div className="flex flex-col gap-4 px-5 py-4">
            <div className="flex flex-col gap-2">
              <Label>{t("settings.projects.nameLabel")}</Label>
              <Input
                autoFocus
                value={name}
                onChange={(event) => setName(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter") createProject();
                }}
                placeholder={t("settings.projects.namePlaceholder")}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label>{t("settings.projects.orgLabel")}</Label>
              <Select value={orgId} onValueChange={setOrgId}>
                <SelectTrigger>
                  <SelectValue placeholder={t("settings.projects.noOrg")} />
                </SelectTrigger>
                <SelectContent>
                  {organizations.map((org) => (
                    <SelectItem key={org.id} value={org.id}>
                      {org.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <DialogFooter className="flex gap-2 px-0 pb-0 pt-0">
              <Button variant="outline" size="sm" onClick={() => setCreateOpen(false)}>
                {t("common.cancel")}
              </Button>
              <Button
                size="sm"
                onClick={createProject}
                disabled={!name.trim()}
                className="flex-1 bg-purple-600 text-white hover:bg-purple-700"
              >
                {t("settings.projects.create")}
              </Button>
            </DialogFooter>
          </div>
        </DialogContent>
      </Dialog>

      <ImportProjectsDialog
        open={importProvider !== null}
        provider={importProvider ?? ""}
        projects={projects}
        onOpenChange={(value) => !value && setImportProvider(null)}
      />
    </PageLayout>
  );
}

interface ProjectRowProps {
  project: Project;
  repoCount: number;
  onOpen: () => void;
  onDelete: () => void;
}

function ProjectRow({ project, repoCount, onOpen, onDelete }: ProjectRowProps) {
  const { t } = useI18n();

  return (
    <div
      onClick={onOpen}
      className="group flex h-10 cursor-pointer items-center gap-2.5 rounded-md pl-3 pr-2 transition-colors hover:bg-zinc-100 dark:hover:bg-white/[0.03]"
    >
      <FolderKanban className="h-4 w-4 shrink-0 text-zinc-400" />
      <span className="truncate text-[13px] font-medium text-zinc-800 dark:text-zinc-100">{project.name}</span>
      <div className="ml-auto flex shrink-0 items-center gap-2">
        <span className="text-[11px] text-zinc-500 dark:text-zinc-400">
          {repoCount} {t("settings.projects.repoCount")}
        </span>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              onClick={(event) => event.stopPropagation()}
              className="flex h-6 w-6 items-center justify-center rounded text-zinc-400 transition-colors hover:bg-zinc-200 hover:text-zinc-700 dark:hover:bg-zinc-700 dark:hover:text-zinc-200"
            >
              <MoreVertical className="h-4 w-4" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onSelect={onOpen}>
              <Eye className="mr-2 h-4 w-4" />
              {t("common.open")}
            </DropdownMenuItem>
            <DropdownMenuItem onSelect={onDelete} className="text-red-500">
              <Trash2 className="mr-2 h-4 w-4" />
              {t("common.delete")}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  );
}
