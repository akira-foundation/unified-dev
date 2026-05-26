import { useEffect, useMemo, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { Check } from "lucide-react";
import { toast } from "sonner";

import { useI18n } from "@/i18n/i18n";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { projectService, type Project, type ProjectRepo } from "@/services/projectService";
import type { IssueDto } from "@/types/issue";

const VCS_PROVIDERS = ["github", "gitlab", "bitbucket", "local"];

interface AssignToProjectDialogProps {
  issue: IssueDto | null;
  projects: Project[];
  repos: ProjectRepo[];
  onClose: () => void;
}

export function AssignToProjectDialog({ issue, projects, repos, onClose }: AssignToProjectDialogProps) {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const [repoId, setRepoId] = useState("");
  const [query, setQuery] = useState("");

  useEffect(() => {
    if (issue) {
      setRepoId("");
      setQuery("");
    }
  }, [issue]);

  const projectName = (id: string) => projects.find((p) => p.id === id)?.name ?? "";

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return repos.filter((repo) => `${projectName(repo.projectId)} / ${repo.name}`.toLowerCase().includes(q));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [repos, projects, query]);

  async function assign() {
    if (!issue || !repoId || !issue.sourceProvider || !issue.sourceRefType || !issue.sourceRef) return;
    const isVcs = VCS_PROVIDERS.includes(issue.sourceProvider);
    try {
      await projectService.addSource(
        repoId,
        issue.sourceProvider,
        issue.sourceRefType,
        issue.sourceRef,
        true,
        isVcs,
      );
      queryClient.invalidateQueries({ queryKey: ["projects"] });
      queryClient.invalidateQueries({ queryKey: ["project-repos"] });
      queryClient.invalidateQueries({ queryKey: ["repo-sources"] });
      toast.success(t("issues.assign.done"));
      onClose();
    } catch (error) {
      toast.error(String(error));
    }
  }

  return (
    <Dialog open={issue !== null} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-[420px] gap-0 overflow-hidden p-0">
        <DialogHeader className="border-b border-border px-5 pt-5 pb-4">
          <DialogTitle className="text-base">{t("issues.assign.title")}</DialogTitle>
          <p className="mt-1.5 text-sm text-muted-foreground">{t("issues.assign.description")}</p>
        </DialogHeader>
        <div className="flex flex-col gap-4 px-5 py-4">
          <div className="flex flex-col gap-2">
            <Label>{t("issues.assign.repoLabel")}</Label>
            <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t("issues.assign.selectRepo")} />
            <div className="max-h-[220px] overflow-y-auto rounded-md border border-zinc-200 dark:border-zinc-800">
              {filtered.length === 0 ? (
                <div className="px-3 py-6 text-center text-[13px] text-muted-foreground">
                  {t("settings.projects.noReposMatch")}
                </div>
              ) : (
                <div className="p-1">
                  {filtered.map((repo) => {
                    const on = repoId === repo.id;
                    return (
                      <button
                        key={repo.id}
                        type="button"
                        onClick={() => setRepoId(repo.id)}
                        className={`flex w-full items-center gap-2 rounded-md px-2.5 py-2 text-left text-[13px] transition-colors hover:bg-accent ${on ? "bg-accent font-medium" : "text-zinc-700 dark:text-zinc-300"}`}
                      >
                        <Check className={`h-3.5 w-3.5 shrink-0 ${on ? "text-purple-500" : "text-transparent"}`} />
                        {projectName(repo.projectId)} / {repo.name}
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
          <DialogFooter className="flex gap-2 px-0 pb-0 pt-0">
            <Button variant="outline" size="sm" onClick={onClose}>
              {t("common.cancel")}
            </Button>
            <Button
              size="sm"
              onClick={assign}
              disabled={!repoId}
              className="flex-1 bg-purple-600 text-white hover:bg-purple-700"
            >
              {t("issues.assign.confirm")}
            </Button>
          </DialogFooter>
        </div>
      </DialogContent>
    </Dialog>
  );
}
