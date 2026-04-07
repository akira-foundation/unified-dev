import { useState, useEffect } from "react";
import { Settings, RotateCcw, Brain } from "lucide-react";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Card, CardContent, CardTitle } from "@/components/ui/card";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { ModelPicker } from "@/components/agents/model-picker";

interface RepoSettingsSheetProps {
  repoId: string | null;
  onClose: () => void;
}

export function RepoSettingsSheet({ repoId, onClose }: RepoSettingsSheetProps) {
  const { updateRepositorySettings, repositoryGroups } = useAgentsStore();

  const repo = repoId
    ? repositoryGroups.flatMap((g) => g.repositories).find((r) => r.id === repoId) ?? null
    : null;

  const [displayName, setDisplayName] = useState("");
  const [baseBranch, setBaseBranch] = useState("");

  useEffect(() => {
    if (!repo) return;
    setDisplayName(repo.displayName ?? repo.name);
    setBaseBranch(repo.defaultBranch);
  }, [repo?.id]);

  if (!repo) return null;

  async function handleDisplayNameBlur() {
    const value = displayName.trim();
    const current = repo!.displayName ?? repo!.name;
    if (value && value !== current) {
      await updateRepositorySettings(repo!.id, { displayName: value });
    }
  }

  async function handleBaseBranchBlur() {
    const value = baseBranch.trim();
    if (value !== repo!.defaultBranch) {
      await updateRepositorySettings(repo!.id, { defaultBranch: value });
    }
  }

  async function handleResetDisplayName() {
    setDisplayName(repo!.name);
    await updateRepositorySettings(repo!.id, { displayName: null });
  }

  return (
    <Sheet open={!!repo} onOpenChange={(open) => { if (!open) onClose(); }}>
      <SheetContent
        side="right"
        className="flex flex-col p-0 overflow-hidden transition-all duration-200 w-full sm:max-w-md"
      >
        <SheetHeader className="px-5 pt-5 pb-4 border-b border-zinc-100 dark:border-zinc-800 shrink-0">
          <div className="flex items-start gap-3 pr-6">
            <div className="mt-1 shrink-0">
              <div className="h-2.5 w-2.5 rounded-full bg-purple-500" />
            </div>
            <div className="min-w-0 flex-1">
              <SheetTitle className="text-base leading-snug text-left">
                {repo.displayName ?? repo.name}
              </SheetTitle>
              <SheetDescription className="text-xs mt-0.5">Repository Settings</SheetDescription>
            </div>
          </div>
        </SheetHeader>

        <div className="flex-1 overflow-y-auto">
          <div className="flex flex-col gap-3 p-2">

            <Collapsible defaultOpen>
              <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
                <CollapsibleTrigger className="w-full cursor-pointer">
                  <div className="flex flex-row items-center gap-3 px-4 py-3">
                    <div className="h-7 w-7 flex items-center justify-center rounded-lg bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
                      <Settings size={14} strokeWidth={2} />
                    </div>
                    <CardTitle className="text-sm font-semibold text-zinc-900 dark:text-white/95 leading-none flex-1 text-left">
                      General
                    </CardTitle>
                  </div>
                </CollapsibleTrigger>
                <CollapsibleContent>
                  <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">

                    <div className="flex items-center justify-between px-4 py-3 gap-4">
                      <div className="flex flex-col gap-0.5 min-w-0 flex-1">
                        <span className="text-xs font-semibold text-zinc-900 dark:text-white">Display Name</span>
                        <p className="text-[11px] text-zinc-500 dark:text-zinc-400 leading-relaxed">
                          The name shown in the sidebar. Path: {repo.name}
                        </p>
                      </div>
                      <div className="flex items-center gap-1.5 shrink-0">
                        <Input
                          value={displayName}
                          onChange={(e) => setDisplayName(e.target.value)}
                          onBlur={handleDisplayNameBlur}
                          className="h-8 w-36 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300"
                        />
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-8 w-8 text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 shrink-0"
                          onClick={handleResetDisplayName}
                        >
                          <RotateCcw size={13} />
                        </Button>
                      </div>
                    </div>

                    <div className="flex items-center justify-between px-4 py-3 gap-4">
                      <div className="flex flex-col gap-0.5 min-w-0 flex-1">
                        <span className="text-xs font-semibold text-zinc-900 dark:text-white">Base Branch</span>
                        <p className="text-[11px] text-zinc-500 dark:text-zinc-400 leading-relaxed">
                          New workspaces branch off this branch.
                        </p>
                      </div>
                      <Input
                        value={baseBranch}
                        onChange={(e) => setBaseBranch(e.target.value)}
                        onBlur={handleBaseBranchBlur}
                        className="h-8 w-36 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300 shrink-0"
                      />
                    </div>

                  </CardContent>
                </CollapsibleContent>
              </Card>
            </Collapsible>

            <Collapsible defaultOpen>
              <Card className="overflow-hidden gap-0 border-zinc-200/50 dark:border-zinc-800/50 shadow-sm">
                <CollapsibleTrigger className="w-full cursor-pointer">
                  <div className="flex flex-row items-center gap-3 px-4 py-3">
                    <div className="h-7 w-7 flex items-center justify-center rounded-lg bg-purple-500/10 text-purple-500 border border-purple-500/10 shrink-0">
                      <Brain size={14} strokeWidth={2} />
                    </div>
                    <CardTitle className="text-sm font-semibold text-zinc-900 dark:text-white/95 leading-none flex-1 text-left">
                      AI
                    </CardTitle>
                  </div>
                </CollapsibleTrigger>
                <CollapsibleContent>
                  <CardContent className="divide-y divide-zinc-100 dark:divide-zinc-800/50 px-0">

                    <div className="flex items-center justify-between px-4 py-3 gap-4">
                      <div className="flex flex-col gap-0.5 min-w-0 flex-1">
                        <span className="text-xs font-semibold text-zinc-900 dark:text-white">Default Model</span>
                        <p className="text-[11px] text-zinc-500 dark:text-zinc-400 leading-relaxed">
                          Applied when opening a workspace without a saved model selection.
                        </p>
                      </div>
                      <ModelPicker
                        value={repo.defaultModelId}
                        onChange={(value) =>
                          updateRepositorySettings(repo.id, { defaultModelId: value })
                        }
                        noneLabel="Use global default"
                      />
                    </div>

                    <div className="flex items-center justify-between px-4 py-3 gap-4">
                      <div className="flex flex-col gap-0.5 min-w-0 flex-1">
                        <span className="text-xs font-semibold text-zinc-900 dark:text-white">Review Model</span>
                        <p className="text-[11px] text-zinc-500 dark:text-zinc-400 leading-relaxed">
                          Used by the Review action for this repository.
                        </p>
                      </div>
                      <ModelPicker
                        value={repo.reviewModelId}
                        onChange={(value) =>
                          updateRepositorySettings(repo.id, { reviewModelId: value })
                        }
                        noneLabel="Use global review model"
                      />
                    </div>

                  </CardContent>
                </CollapsibleContent>
              </Card>
            </Collapsible>

          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}
