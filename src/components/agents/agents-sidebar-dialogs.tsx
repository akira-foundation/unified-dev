import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { AddRepositoryDialog } from "@/components/repos/add-repository-dialog";
import { RemoveRepositoryDialog } from "@/components/repos/remove-repository-dialog";
import { GhCliErrorDialog } from "@/components/repos/gh-cli-error-dialog";
import { RemoveThreadDialog } from "@/components/agents/remove-thread-dialog";
import { RepoSettingsSheet } from "@/components/agents/repo-settings-sheet";
import { AutopilotDialog } from "@/components/agents/autopilot-dialog";
import { AutopilotJobsPanel } from "@/components/agents/autopilot-jobs-panel";
import { AutopilotJobDetail } from "@/components/agents/autopilot-job-detail";
import { ThreadSourcePickerDialog } from "@/components/agents/thread-source-picker-dialog";
import type { AgentsSidebarVm } from "@/hooks/useAgentsSidebar";

export function AgentsSidebarDialogs({ vm }: { vm: AgentsSidebarVm }) {
  const { t } = vm;

  return (
    <>
      <AddRepositoryDialog open={vm.showAddRepositoryDialog} onOpenChange={vm.setShowAddRepositoryDialog} onAdd={vm.handleAddRepo} isLoading={vm.isAddingRepo} />

      <GhCliErrorDialog open={!!vm.ghCliError} onOpenChange={(open) => { if (!open) vm.setGhCliError(null); }} kind={vm.ghCliError} />

      <RemoveRepositoryDialog open={!!vm.repoToRemove} onOpenChange={(open) => !open && vm.setRepoToRemove(null)} onRemove={vm.handleRemoveRepo} repoName={vm.repoToRemove?.name || ""} isRemoving={vm.isRemovingRepo} localOnly />

      <RemoveThreadDialog open={!!vm.threadToRemove} onOpenChange={(open) => !open && vm.setThreadToRemove(null)} onRemove={vm.handleRemoveThread} threadTitle={vm.threadToRemove?.title || ""} isRemoving={!!vm.removingThreadId} />

      <AlertDialog open={!!vm.repoClearThreads} onOpenChange={(open) => !open && vm.setRepoClearThreads(null)}>
        <AlertDialogContent className="max-w-[420px]">
          <AlertDialogHeader>
            <AlertDialogTitle>{t("agents.sidebar.clearThreadsConfirmTitle")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("agents.sidebar.clearThreadsConfirmDesc").replace("{name}", vm.repoClearThreads?.name ?? "")}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel size="sm">{t("common.cancel")}</AlertDialogCancel>
            <AlertDialogAction size="sm" className="flex-1 bg-red-500 text-white hover:bg-red-600" onClick={() => void vm.handleClearThreads()}>
              {t("agents.sidebar.clearThreadsConfirm")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {vm.sourcePicker ? (
        <ThreadSourcePickerDialog
          open={!!vm.sourcePicker}
          onOpenChange={(open) => { if (!open) vm.setSourcePicker(null); }}
          kind={vm.sourcePicker.kind}
          repoName={vm.sourcePicker.repoName}
          items={vm.sourcePickerItems}
          isLoading={vm.sourcePickerLoading}
          isCreating={vm.creatingSourceThread}
          onSelect={vm.handleSelectSourceItem}
        />
      ) : null}

      <Dialog open={!!vm.linkRepoDialog} onOpenChange={(open) => !open && vm.setLinkRepoDialog(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>{t("agents.linkRepoDialog.title")}</DialogTitle>
            <DialogDescription>
              {t("agents.linkRepoDialog.description").replace("{repo}", vm.linkRepoDialog?.repoName ?? "")}
            </DialogDescription>
          </DialogHeader>

          <div className="mt-4 space-y-2">
            {vm.isLoadingOrganizations ? (
              <div className="rounded-lg border border-border px-3 py-4 text-sm text-muted-foreground">{t("agents.linkRepoDialog.loading")}</div>
            ) : vm.organizations.length === 0 ? (
              <div className="rounded-lg border border-border px-3 py-4 text-sm text-muted-foreground">{t("agents.linkRepoDialog.empty")}</div>
            ) : (
              <div className="space-y-3">
                <Select value={vm.linkOrganizationId} onValueChange={vm.setLinkOrganizationId}>
                  <SelectTrigger className="h-10 w-full rounded-md border-zinc-200 bg-zinc-100 px-3 text-sm text-zinc-700 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-200">
                    <SelectValue placeholder={t("agents.linkRepoDialog.placeholder")} />
                  </SelectTrigger>
                  <SelectContent>
                    {vm.organizations.map((organization) => (
                      <SelectItem key={organization.id} value={organization.id}>{organization.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                {vm.linkRepoDialog?.requiresRemote ? (
                  <Input value={vm.manualRemoteUrl} onChange={(event) => vm.setManualRemoteUrl(event.target.value)} placeholder={t("agents.linkRepoDialog.remotePlaceholder")} className="h-10" />
                ) : null}
              </div>
            )}
          </div>

          <DialogFooter className="mt-6">
            <Button variant="ghost" onClick={() => vm.setLinkRepoDialog(null)}>{t("common.cancel")}</Button>
            <Button
              onClick={() => void vm.handleLinkRepo()}
              disabled={!vm.linkOrganizationId || (vm.linkRepoDialog?.requiresRemote && !vm.manualRemoteUrl.trim())}
            >
              {t("agents.linkRepoDialog.cta")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <RepoSettingsSheet repoId={vm.repoSettingsTarget} onClose={() => vm.setRepoSettingsTarget(null)} />

      <AutopilotDialog open={!!vm.autopilotTarget} onOpenChange={(open) => { if (!open) vm.setAutopilotTarget(null); }} repoId={vm.autopilotTarget?.repoId ?? ""} repoName={vm.autopilotTarget?.repoName ?? ""} />

      <AutopilotJobsPanel open={vm.autopilotPanelOpen} onOpenChange={vm.setAutopilotPanelOpen} />

      <AutopilotJobDetail open={!!vm.selectedJobId} onOpenChange={(open) => { if (!open) vm.selectJob(null); }} />
    </>
  );
}
