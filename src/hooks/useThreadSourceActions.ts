import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";

import { useAgentsStore } from "@/stores/useAgentsStore";
import { useNavigationStore } from "@/stores/navigation-store";
import { useI18n } from "@/i18n/i18n";
import type { ThreadSourceKind, ThreadSourcePickerItem } from "@/components/agents/thread-source-picker-dialog";
import type { IssueDto } from "@/types/issue";
import type { BranchDto, PullRequestDto } from "@/types/organization";

const isRepoLinkRequiredError = (error: unknown) =>
  String(error).toLowerCase().includes("must be linked to an organization before using issue, pull request, or branch pickers");

const isUnsupportedRemoteError = (error: unknown) =>
  String(error).toLowerCase().includes("repository is not linked to a supported github remote");

export function useThreadSourceActions() {
  const { t } = useI18n();
  const { addThread, setExpandedRepos, sendMessage, selectedModelId, setThreadPrInfo, loadRepositories } = useAgentsStore();
  const setActiveOrganizationId = useNavigationStore((s) => s.setActiveOrganizationId);

  const [sourcePicker, setSourcePicker] = useState<{ kind: ThreadSourceKind; repoId: string; repoName: string } | null>(null);
  const [sourcePickerItems, setSourcePickerItems] = useState<ThreadSourcePickerItem[]>([]);
  const [sourcePickerLoading, setSourcePickerLoading] = useState(false);
  const [creatingSourceThread, setCreatingSourceThread] = useState(false);
  const [linkRepoDialog, setLinkRepoDialog] = useState<{ repoId: string; repoName: string; kind: ThreadSourceKind; requiresRemote: boolean } | null>(null);
  const [linkOrganizationId, setLinkOrganizationId] = useState("");
  const [manualRemoteUrl, setManualRemoteUrl] = useState("");

  const handleOpenSourcePicker = async (kind: ThreadSourceKind, repo: { id: string; name: string }) => {
    setSourcePicker({ kind, repoId: repo.id, repoName: repo.name });
    setSourcePickerItems([]);
    setSourcePickerLoading(true);
    try {
      if (kind === "issue") {
        const issues = await invoke<IssueDto[]>("list_thread_source_issues", { repoId: repo.id });
        setSourcePickerItems(issues.map((issue) => ({
          id: issue.id,
          title: issue.title,
          subtitle: `#${issue.number}${issue.author ? ` - ${issue.author}` : ""}`,
          meta: issue.status,
        })));
        return;
      }
      if (kind === "pr") {
        const prs = await invoke<PullRequestDto[]>("list_thread_source_pull_requests", { repoId: repo.id });
        setSourcePickerItems(prs.map((pr) => ({
          id: pr.head_sha,
          title: pr.title,
          subtitle: `#${pr.number} - ${pr.head} -> ${pr.base}`,
          meta: pr.is_draft ? "draft" : pr.state,
        })));
        return;
      }
      const branches = await invoke<BranchDto[]>("list_thread_source_branches", { repoId: repo.id });
      setSourcePickerItems(branches.map((branch) => ({
        id: branch.sha,
        title: branch.name,
        subtitle: branch.sha.slice(0, 7),
        meta: branch.is_default ? "default" : branch.is_protected ? "protected" : undefined,
      })));
    } catch (error) {
      if (isRepoLinkRequiredError(error) || isUnsupportedRemoteError(error)) {
        setSourcePicker(null);
        setLinkRepoDialog({ repoId: repo.id, repoName: repo.name, kind, requiresRemote: isUnsupportedRemoteError(error) });
        setLinkOrganizationId("");
        setManualRemoteUrl("");
        return;
      }
      toast.error(`${error}`);
    } finally {
      setSourcePickerLoading(false);
    }
  };

  const handleSelectSourceItem = async (item: ThreadSourcePickerItem) => {
    if (!sourcePicker) return;
    try {
      setCreatingSourceThread(true);
      if (sourcePicker.kind === "issue") {
        const issues = await invoke<IssueDto[]>("list_thread_source_issues", { repoId: sourcePicker.repoId });
        const issue = issues.find((entry) => entry.id === item.id);
        if (!issue) throw new Error(t("agents.sourcePicker.issue.notFound"));
        const thread = await invoke<{ id: string; title: string; workspace_path: string }>("create_thread_with_title", { repoId: sourcePicker.repoId, title: issue.title });
        addThread(sourcePicker.repoId, thread);
        setExpandedRepos((prev) => ({ ...prev, [sourcePicker.repoId]: true }));
        setSourcePicker(null);
        if (selectedModelId) {
          await sendMessage(thread.id, `Implement the following issue:\n\n**${issue.title}**\n\n${issue.body ?? ""}`, selectedModelId, false);
        }
        return;
      }
      if (sourcePicker.kind === "pr") {
        const prs = await invoke<PullRequestDto[]>("list_thread_source_pull_requests", { repoId: sourcePicker.repoId });
        const pr = prs.find((entry) => entry.head_sha === item.id);
        if (!pr) throw new Error(t("agents.sourcePicker.pr.notFound"));
        const thread = await invoke<{ id: string; title: string; workspace_path: string }>("create_thread_from_pull_request", { repoId: sourcePicker.repoId, title: pr.title, headSha: pr.head_sha });
        await invoke("set_thread_pr_url", { threadId: thread.id, prUrl: pr.url, prIsDraft: pr.is_draft });
        setThreadPrInfo(thread.id, { url: pr.url, isDraft: pr.is_draft });
        addThread(sourcePicker.repoId, thread);
        await loadRepositories();
        setExpandedRepos((prev) => ({ ...prev, [sourcePicker.repoId]: true }));
        setSourcePicker(null);
        return;
      }
      const thread = await invoke<{ id: string; title: string; workspace_path: string }>("create_thread_from_branch", { repoId: sourcePicker.repoId, title: item.title, sourceCommit: item.id });
      addThread(sourcePicker.repoId, thread);
      setExpandedRepos((prev) => ({ ...prev, [sourcePicker.repoId]: true }));
      setSourcePicker(null);
    } catch (error) {
      toast.error(`${error}`);
    } finally {
      setCreatingSourceThread(false);
    }
  };

  const handleLinkRepo = async () => {
    if (!linkOrganizationId || !linkRepoDialog) return;
    try {
      if (linkRepoDialog.requiresRemote) {
        await invoke("set_local_repository_remote", { repoId: linkRepoDialog.repoId, remoteUrl: manualRemoteUrl.trim() });
      }
      await invoke("link_local_repository_to_organization", { repoId: linkRepoDialog.repoId, organizationId: linkOrganizationId });
      const nextPicker = { kind: linkRepoDialog.kind, repoId: linkRepoDialog.repoId, repoName: linkRepoDialog.repoName };
      setActiveOrganizationId(linkOrganizationId);
      setLinkRepoDialog(null);
      setManualRemoteUrl("");
      setLinkOrganizationId("");
      await handleOpenSourcePicker(nextPicker.kind, { id: nextPicker.repoId, name: nextPicker.repoName });
    } catch (error) {
      toast.error(`${error}`);
    }
  };

  return {
    sourcePicker,
    setSourcePicker,
    sourcePickerItems,
    sourcePickerLoading,
    creatingSourceThread,
    linkRepoDialog,
    setLinkRepoDialog,
    linkOrganizationId,
    setLinkOrganizationId,
    manualRemoteUrl,
    setManualRemoteUrl,
    handleOpenSourcePicker,
    handleSelectSourceItem,
    handleLinkRepo,
  };
}
