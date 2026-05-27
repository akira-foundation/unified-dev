import { useEffect, useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, Loader2 } from "lucide-react";
import { toast } from "sonner";

import { useI18n } from "@/i18n/i18n";
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
import { projectService, type Project } from "@/services/projectService";
import { trackerService } from "@/services/trackerService";

type ConflictStrategy = "merge" | "replace" | "keep";

const NEW_PROJECT = "__new__";

interface ImportProjectsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  provider: string;
  projects: Project[];
}

export function ImportProjectsDialog({ open, onOpenChange, provider, projects }: ImportProjectsDialogProps) {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [dest, setDest] = useState(NEW_PROJECT);
  const [newName, setNewName] = useState("");
  const [busy, setBusy] = useState(false);
  const [conflicts, setConflicts] = useState<string[]>([]);

  const { data: scopes = [], isLoading } = useQuery({
    queryKey: ["tracker-list-projects", provider],
    queryFn: () => trackerService.listProjects(provider),
    enabled: open,
  });

  const { data: allRepos = [] } = useQuery({
    queryKey: ["project-repos"],
    queryFn: () => projectService.listRepos(),
    enabled: open,
  });

  useEffect(() => {
    if (open) {
      setQuery("");
      setSelected(new Set());
      setDest(NEW_PROJECT);
      setNewName("");
      setConflicts([]);
    }
  }, [open]);

  const selectedNames = useMemo(
    () =>
      [...selected]
        .map((id) => scopes.find((s) => s.id === id)?.name)
        .filter((name): name is string => !!name),
    [selected, scopes],
  );

  const filtered = useMemo(
    () => scopes.filter((s) => s.name.toLowerCase().includes(query.trim().toLowerCase())),
    [scopes, query],
  );

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const canApply = selected.size > 0 && (dest !== NEW_PROJECT || !!newName.trim());

  function apply() {
    if (!canApply) return;
    if (dest !== NEW_PROJECT) {
      const existing = new Set(
        allRepos.filter((repo) => repo.projectId === dest).map((repo) => repo.name),
      );
      const clash = selectedNames.filter((name) => existing.has(name));
      if (clash.length > 0) {
        setConflicts([...new Set(clash)]);
        return;
      }
    }
    void doImport("keep");
  }

  async function doImport(strategy: ConflictStrategy) {
    setBusy(true);
    try {
      const projectId =
        dest === NEW_PROJECT ? (await projectService.create(newName.trim(), null)).id : dest;
      const projectRepos = allRepos.filter((repo) => repo.projectId === projectId);

      for (const scopeId of selected) {
        const scope = scopes.find((s) => s.id === scopeId);
        if (!scope) continue;

        const existing = projectRepos.filter((repo) => repo.name === scope.name);
        let repoId: string;
        if (existing.length > 0 && strategy === "merge") {
          repoId = existing[0].id;
        } else {
          if (existing.length > 0 && strategy === "replace") {
            for (const repo of existing) {
              await projectService.removeRepo(repo.id);
            }
          }
          repoId = (await projectService.createRepo(projectId, scope.name)).id;
        }
        await projectService.addSource(repoId, provider, "project", scope.id, true, false);
      }

      // Full sync so every selected project's issues land regardless of the
      // original sync scope (e.g. assignee-only), then map via the new bindings.
      await trackerService.sync(provider);
      queryClient.invalidateQueries({ queryKey: ["projects"] });
      queryClient.invalidateQueries({ queryKey: ["project-repos"] });
      queryClient.invalidateQueries({ queryKey: ["repo-sources"] });
      queryClient.invalidateQueries({ queryKey: ["tracker-issues"] });
      toast.success(t("settings.projects.imported", { count: String(selected.size) }));
      onOpenChange(false);
    } catch (error) {
      toast.error(String(error));
    } finally {
      setBusy(false);
      setConflicts([]);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(value) => !busy && onOpenChange(value)}>
      <DialogContent className="max-w-[460px] gap-0 overflow-hidden p-0">
        <DialogHeader className="border-b border-border px-5 pt-5 pb-4">
          <DialogTitle className="text-base capitalize">{t("import.title", { provider })}</DialogTitle>
          <p className="mt-1.5 text-sm text-muted-foreground">{t("import.description")}</p>
        </DialogHeader>
        <div className="flex flex-col gap-4 px-5 py-4">
          <div className="flex flex-col gap-2">
            <Label>{t("import.scopesLabel")}</Label>
            <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t("import.search")} />
            <div className="max-h-[220px] overflow-y-auto rounded-md border border-zinc-200 dark:border-zinc-800">
              {isLoading ? (
                <div className="flex items-center justify-center gap-2 px-3 py-8 text-[13px] text-muted-foreground">
                  <Loader2 className="h-4 w-4 animate-spin" /> {t("import.loading")}
                </div>
              ) : filtered.length === 0 ? (
                <div className="px-3 py-8 text-center text-[13px] text-muted-foreground">{t("import.empty")}</div>
              ) : (
                <div className="p-1">
                  {filtered.map((scope) => {
                    const on = selected.has(scope.id);
                    return (
                      <button
                        key={scope.id}
                        type="button"
                        onClick={() => toggle(scope.id)}
                        className={`flex w-full items-center gap-2 rounded-md px-2.5 py-2 text-left text-[13px] transition-colors hover:bg-accent ${on ? "bg-accent font-medium" : "text-zinc-700 dark:text-zinc-300"}`}
                      >
                        <Check className={`h-3.5 w-3.5 shrink-0 ${on ? "text-purple-500" : "text-transparent"}`} />
                        {scope.name}
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          </div>

          <div className="flex flex-col gap-2">
            <Label>{t("import.destLabel")}</Label>
            <Select value={dest} onValueChange={setDest}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={NEW_PROJECT}>{t("import.newProject")}</SelectItem>
                {projects.map((project) => (
                  <SelectItem key={project.id} value={project.id}>
                    {project.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {dest === NEW_PROJECT && (
              <Input
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                placeholder={t("settings.projects.namePlaceholder")}
              />
            )}
          </div>

          {conflicts.length > 0 ? (
            <div className="flex flex-col gap-3">
              <p className="text-[13px] text-muted-foreground">
                {t("import.conflict.message", { names: conflicts.join(", ") })}
              </p>
              <div className="flex gap-2">
                <Button variant="outline" size="sm" onClick={() => doImport("merge")} disabled={busy} className="flex-1">
                  {t("import.conflict.merge")}
                </Button>
                <Button variant="outline" size="sm" onClick={() => doImport("replace")} disabled={busy} className="flex-1">
                  {t("import.conflict.replace")}
                </Button>
                <Button size="sm" onClick={() => doImport("keep")} disabled={busy} className="flex-1 bg-purple-600 text-white hover:bg-purple-700">
                  {t("import.conflict.keep")}
                </Button>
              </div>
              <Button variant="ghost" size="sm" onClick={() => setConflicts([])} disabled={busy}>
                {t("common.cancel")}
              </Button>
            </div>
          ) : (
            <DialogFooter className="flex gap-2 px-0 pb-0 pt-0">
              <Button variant="outline" size="sm" onClick={() => onOpenChange(false)} disabled={busy}>
                {t("common.cancel")}
              </Button>
              <Button
                size="sm"
                onClick={apply}
                disabled={!canApply || busy}
                className="flex-1 gap-1.5 bg-purple-600 text-white hover:bg-purple-700"
              >
                {busy && <Loader2 className="h-4 w-4 animate-spin" />}
                {t("import.apply")}
              </Button>
            </DialogFooter>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
