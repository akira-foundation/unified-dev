import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { useAgentsStore } from "../stores/useAgentsStore";
import { useNavigationStore } from "../stores/navigation-store";
import { useIssueKanbanStore } from "../stores/useIssueKanbanStore";
import { useI18n } from "../i18n/i18n";
import type { IssueDto } from "../types/issue";

interface DelegateResponse {
  repository: { id: string; name: string };
  thread: { id: string; title: string; workspace_path: string };
}

export function useDelegateIssue() {
  const { t } = useI18n();
  const { loadRepositories, setSelectedIssueId, sendMessage, selectedModelId } = useAgentsStore();
  const { navigateTo, setIsAgentMode } = useNavigationStore();
  const setIssueColumn = useIssueKanbanStore((s) => s.setOverride);

  const delegateIssue = async (issue: IssueDto) => {
    const loadingToast = toast.loading(t("issues.detail.delegating"));
    try {
      const response = await invoke<DelegateResponse>("delegate_issue_to_agent", {
        orgId: issue.orgId,
        repoName: issue.repoName,
        issueTitle: issue.title,
        issueIdentifier: issue.externalId ?? null,
      });

      const { thread } = response;

      await loadRepositories();
      setSelectedIssueId(thread.id);
      setIssueColumn(issue.id, "in_progress");
      setIsAgentMode(true);

      toast.success(t("issues.detail.delegate"), { id: loadingToast });

      const model = selectedModelId ?? "";
      const message = `Implement the following issue:\n\n**${issue.title}**\n\n${issue.body ?? ""}`;

      if (model) {
        const sendPromise = sendMessage(thread.id, message, model, false);
        navigateTo("agents");
        await sendPromise;
      } else {
        navigateTo("agents");
      }
    } catch (error) {
      toast.error(`${error}`, { id: loadingToast });
    }
  };

  return { delegateIssue };
}
