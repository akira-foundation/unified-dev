import { useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";

import { useI18n } from "@/i18n/i18n";
import { Button } from "@/components/ui/button";
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

  useEffect(() => {
    if (issue) setRepoId("");
  }, [issue]);

  const projectName = (id: string) => projects.find((p) => p.id === id)?.name ?? "";

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
            <Select value={repoId} onValueChange={setRepoId}>
              <SelectTrigger>
                <SelectValue placeholder={t("issues.assign.selectRepo")} />
              </SelectTrigger>
              <SelectContent>
                {repos.map((repo) => (
                  <SelectItem key={repo.id} value={repo.id}>
                    {projectName(repo.projectId)} / {repo.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
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
