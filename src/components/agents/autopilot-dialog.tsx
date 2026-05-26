import { useState, useEffect } from "react";
import { Loader2, Rocket } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { ModelPicker } from "@/components/agents/model-picker";
import { useAutopilotStore, type AutopilotConfig, type AutopilotFilter, type AutopilotModelMode, type AutopilotPrMode } from "@/stores/useAutopilotStore";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useI18n } from "@/i18n/i18n";
import type { IssueDto } from "@/types/issue";

interface AutopilotDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  repoId: string;
  repoName: string;
}

export function AutopilotDialog({ open, onOpenChange, repoId, repoName }: AutopilotDialogProps) {
  const { t } = useI18n();
  const { startJob } = useAutopilotStore();
  const { selectedModelId } = useAgentsStore();

  const [issues, setIssues] = useState<IssueDto[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [providerLogin, setProviderLogin] = useState<string | null>(null);

  const [batchSize, setBatchSize] = useState("5");
  const [delayMs, setDelayMs] = useState("3000");
  const [modelMode, setModelMode] = useState<AutopilotModelMode>("current");
  const [singleModelId, setSingleModelId] = useState<string | null>(selectedModelId);
  const [filter, setFilter] = useState<AutopilotFilter>("assigned_to_me");
  const [autoSend, setAutoSend] = useState(true);
  const [prMode, setPrMode] = useState<AutopilotPrMode>("off");
  const [resolveConflicts, setResolveConflicts] = useState(true);

  useEffect(() => {
    if (!open) return;
    setIsLoading(true);
    Promise.all([
      invoke<IssueDto[]>("list_thread_source_issues", { repoId }),
      invoke<string | null>("get_repo_provider_login", { repoId }),
    ])
      .then(([data, login]) => {
        setIssues(data.filter((i) => i.status === "open"));
        setProviderLogin(login);
        setFilter(login ? "assigned_to_me" : "all");
      })
      .catch(() => toast.error(t("autopilot.dialog.loadError")))
      .finally(() => setIsLoading(false));
  }, [open, repoId]);

  function filteredCount(): number {
    switch (filter) {
      case "unassigned":
        return issues.filter((i) => i.assignees.length === 0).length;
      case "no_pr":
        return issues.filter((i) => i.linkedPrNumbers.length === 0).length;
      case "assigned_to_me":
        if (!providerLogin) return 0;
        return issues.filter((i) =>
          i.assignees.some((a) => a.toLowerCase() === providerLogin.toLowerCase()),
        ).length;
      default:
        return issues.length;
    }
  }

  function handleStart() {
    if (issues.length === 0) {
      toast.info(t("autopilot.dialog.noIssues"));
      return;
    }

    const config: AutopilotConfig = {
      batchSize: parseInt(batchSize, 10),
      delayMs: parseInt(delayMs, 10),
      modelMode,
      modelId: modelMode === "single" ? singleModelId : null,
      filter,
      assignedToLogin: filter === "assigned_to_me" ? providerLogin : null,
      autoSend,
      prMode,
      resolveConflicts,
    };

    startJob(repoId, repoName, issues, config);
    onOpenChange(false);
    toast.info(t("autopilot.dialog.started").replace("{repo}", repoName));
  }

  const count = filteredCount();

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-[420px] p-0 gap-0 overflow-hidden">
        {/* Header */}
        <DialogHeader className="px-5 pt-5 pb-4 border-b border-border">
          <div className="flex items-center gap-2">
            <Rocket className="h-4 w-4 text-purple-500" />
            <DialogTitle className="text-base">{t("autopilot.dialog.title")}</DialogTitle>
          </div>
          <div className="flex items-center gap-2 mt-1.5">
            {isLoading ? (
              <Loader2 className="h-3 w-3 animate-spin text-muted-foreground" />
            ) : (
              <span className="text-2xl font-bold text-foreground">{count}</span>
            )}
            <span className="text-sm text-muted-foreground">
              {t("autopilot.dialog.description").replace("{repo}", repoName)}
            </span>
          </div>
        </DialogHeader>

        {/* Settings */}
        <div className="px-5 py-4 space-y-3">
          {/* Row 1: Filter + Batch */}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <p className="text-[11px] text-muted-foreground">{t("autopilot.dialog.filter")}</p>
              <Select value={filter} onValueChange={(v) => setFilter(v as AutopilotFilter)}>
                <SelectTrigger className="h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("autopilot.filter.all")}</SelectItem>
                  <SelectItem value="unassigned">{t("autopilot.filter.unassigned")}</SelectItem>
                  <SelectItem value="assigned_to_me" disabled={!providerLogin}>
                    {t("autopilot.filter.assigned_to_me")}
                    {providerLogin ? ` (@${providerLogin})` : ""}
                  </SelectItem>
                  <SelectItem value="no_pr">{t("autopilot.filter.no_pr")}</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1">
              <p className="text-[11px] text-muted-foreground">{t("autopilot.dialog.batchSize")}</p>
              <Select value={batchSize} onValueChange={setBatchSize}>
                <SelectTrigger className="h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="5">5</SelectItem>
                  <SelectItem value="10">10</SelectItem>
                  <SelectItem value="20">20</SelectItem>
                  <SelectItem value="50">50</SelectItem>
                  <SelectItem value="999999">{t("autopilot.dialog.batchAll")}</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          {/* Row 2: Model + Delay */}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <p className="text-[11px] text-muted-foreground">{t("autopilot.dialog.modelMode")}</p>
              <Select value={modelMode} onValueChange={(v) => setModelMode(v as AutopilotModelMode)}>
                <SelectTrigger className="h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="current">{t("autopilot.modelMode.current")}</SelectItem>
                  <SelectItem value="single">{t("autopilot.modelMode.single")}</SelectItem>
                  <SelectItem value="random">{t("autopilot.modelMode.random")}</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1">
              <p className="text-[11px] text-muted-foreground">{t("autopilot.dialog.delay")}</p>
              <Select value={delayMs} onValueChange={setDelayMs}>
                <SelectTrigger className="h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="1000">1s</SelectItem>
                  <SelectItem value="3000">3s</SelectItem>
                  <SelectItem value="5000">5s</SelectItem>
                  <SelectItem value="10000">10s</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          {/* Model picker (only for single) */}
          {modelMode === "single" && (
            <div className="space-y-1">
              <p className="text-[11px] text-muted-foreground">{t("autopilot.dialog.pickModel")}</p>
              <ModelPicker value={singleModelId} onChange={setSingleModelId} align="start" className="w-full" />
            </div>
          )}

          {/* Auto-send toggle */}
          <div className="flex items-center justify-between pt-1">
            <div>
              <p className="text-xs font-medium">{t("autopilot.dialog.autoSend")}</p>
              <p className="text-[11px] text-muted-foreground">{t("autopilot.dialog.autoSendDesc")}</p>
            </div>
            <Switch checked={autoSend} onCheckedChange={setAutoSend} />
          </div>

          {/* Finish + PR */}
          <div className="space-y-2 pt-1">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-xs font-medium">{t("autopilot.dialog.prMode")}</p>
                <p className="text-[11px] text-muted-foreground">{t("autopilot.dialog.prModeDesc")}</p>
              </div>
              <Select value={prMode} onValueChange={(v) => setPrMode(v as AutopilotPrMode)}>
                <SelectTrigger className="h-8 w-32 text-xs">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="off">{t("autopilot.prMode.off")}</SelectItem>
                  <SelectItem value="draft">{t("autopilot.prMode.draft")}</SelectItem>
                  <SelectItem value="ready">{t("autopilot.prMode.ready")}</SelectItem>
                </SelectContent>
              </Select>
            </div>
            {prMode !== "off" ? (
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-xs font-medium">{t("autopilot.dialog.resolveConflicts")}</p>
                  <p className="text-[11px] text-muted-foreground">{t("autopilot.dialog.resolveConflictsDesc")}</p>
                </div>
                <Switch checked={resolveConflicts} onCheckedChange={setResolveConflicts} />
              </div>
            ) : null}
          </div>
        </div>

        <DialogFooter className="px-5 pb-5 pt-0 flex gap-2">
          <Button variant="outline" size="sm" onClick={() => onOpenChange(false)}>
            {t("common.cancel")}
          </Button>
          <Button
            size="sm"
            onClick={handleStart}
            disabled={isLoading || count === 0}
            className="flex-1 gap-2 bg-purple-600 hover:bg-purple-700 text-white"
          >
            <Rocket className="h-3.5 w-3.5" />
            {t("autopilot.dialog.start").replace("{count}", String(count))}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
