import { useEffect, useMemo, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { Check } from "lucide-react";
import { toast } from "sonner";

import { useI18n } from "@/i18n/i18n";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { projectService, type ProjectRepo } from "@/services/projectService";
import type { OrganizationRepoWithOrg } from "@/types/organization";

interface LinkRepoDialogProps {
  repo: ProjectRepo | null;
  githubRepos: OrganizationRepoWithOrg[];
  onOpenChange: (open: boolean) => void;
  onLinked: () => void;
}

export function LinkRepoDialog({ repo, githubRepos, onOpenChange, onLinked }: LinkRepoDialogProps) {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const [query, setQuery] = useState("");
  const [selectedRef, setSelectedRef] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (repo) {
      setQuery("");
      setSelectedRef("");
    }
  }, [repo]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return githubRepos.filter((entry) =>
      `${entry.organization_name}/${entry.repo_name}`.toLowerCase().includes(q),
    );
  }, [githubRepos, query]);

  async function link() {
    if (!repo || !selectedRef) return;
    setBusy(true);
    try {
      await projectService.addSource(repo.id, "github", "repo", selectedRef, false, true);
      queryClient.invalidateQueries({ queryKey: ["project-repos"] });
      queryClient.invalidateQueries({ queryKey: ["repo-sources"] });
      onLinked();
      toast.success(t("linkRepo.done"));
      onOpenChange(false);
    } catch (error) {
      toast.error(String(error));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open={repo !== null} onOpenChange={(open) => !busy && !open && onOpenChange(false)}>
      <DialogContent className="max-w-[420px] gap-0 overflow-hidden p-0">
        <DialogHeader className="border-b border-border px-5 pt-5 pb-4">
          <DialogTitle className="text-base">{t("linkRepo.title")}</DialogTitle>
          <p className="mt-1.5 text-sm text-muted-foreground">{t("linkRepo.description")}</p>
        </DialogHeader>
        <div className="flex flex-col gap-4 px-5 py-4">
          <div className="flex flex-col gap-2">
            <Label>{t("linkRepo.repoLabel")}</Label>
            <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t("issues.assign.selectRepo")} />
            <div className="max-h-[220px] overflow-y-auto rounded-md border border-zinc-200 dark:border-zinc-800">
              {filtered.length === 0 ? (
                <div className="px-3 py-6 text-center text-[13px] text-muted-foreground">
                  {t("settings.projects.noReposMatch")}
                </div>
              ) : (
                <div className="p-1">
                  {filtered.map((entry) => {
                    const ref = `${entry.organization_id}/${entry.repo_name}`;
                    const label = `${entry.organization_name}/${entry.repo_name}`;
                    const on = selectedRef === ref;
                    return (
                      <button
                        key={ref}
                        type="button"
                        onClick={() => setSelectedRef(ref)}
                        className={`flex w-full items-center gap-2 rounded-md px-2.5 py-2 text-left text-[13px] transition-colors hover:bg-accent ${on ? "bg-accent font-medium" : "text-zinc-700 dark:text-zinc-300"}`}
                      >
                        <Check className={`h-3.5 w-3.5 shrink-0 ${on ? "text-purple-500" : "text-transparent"}`} />
                        {label}
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
          <DialogFooter className="flex gap-2 px-0 pb-0 pt-0">
            <Button variant="outline" size="sm" onClick={() => onOpenChange(false)} disabled={busy}>
              {t("common.cancel")}
            </Button>
            <Button
              size="sm"
              onClick={link}
              disabled={!selectedRef || busy}
              className="flex-1 bg-purple-600 text-white hover:bg-purple-700"
            >
              {t("linkRepo.apply")}
            </Button>
          </DialogFooter>
        </div>
      </DialogContent>
    </Dialog>
  );
}
