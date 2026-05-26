import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Trash2, Eye, FolderKanban, MoreVertical } from "lucide-react";
import { toast } from "sonner";

import { useI18n } from "@/i18n/i18n";
import { useHotkey } from "@/hooks/useHotkey";
import { useOrganizations } from "@/hooks/useOrganizations";
import { useNavigationStore } from "@/stores/navigation-store";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
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

const SELECT =
  "h-8 rounded-md border border-zinc-200 bg-zinc-100 px-2.5 text-[13px] text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300";

export function ProjectsPage() {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const { organizations } = useOrganizations();
  const navigateTo = useNavigationStore((s) => s.navigateTo);
  const setActiveProjectId = useNavigationStore((s) => s.setActiveProjectId);
  const [createOpen, setCreateOpen] = useState(false);
  const [name, setName] = useState("");
  const [orgId, setOrgId] = useState("");

  useHotkey("n", () => setCreateOpen(true));

  const { data: projects = [] } = useQuery({ queryKey: ["projects"], queryFn: () => projectService.list() });
  const { data: repos = [] } = useQuery({ queryKey: ["project-repos"], queryFn: () => projectService.listRepos() });

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
            />
            <select value={orgId} onChange={(event) => setOrgId(event.target.value)} className={SELECT}>
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
