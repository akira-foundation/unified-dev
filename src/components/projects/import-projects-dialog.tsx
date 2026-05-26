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

  const { data: scopes = [], isLoading } = useQuery({
    queryKey: ["tracker-list-projects", provider],
    queryFn: () => trackerService.listProjects(provider),
    enabled: open,
  });

  useEffect(() => {
    if (open) {
      setQuery("");
      setSelected(new Set());
      setDest(NEW_PROJECT);
      setNewName("");
    }
  }, [open]);

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

  async function apply() {
    if (!canApply) return;
    setBusy(true);
    try {
      const projectId =
        dest === NEW_PROJECT ? (await projectService.create(newName.trim(), null)).id : dest;
      for (const scopeId of selected) {
        const scope = scopes.find((s) => s.id === scopeId);
        if (!scope) continue;
        const repo = await projectService.createRepo(projectId, scope.name);
        await projectService.addSource(repo.id, provider, "project", scope.id, true, false);
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
        </div>
      </DialogContent>
    </Dialog>
  );
}
