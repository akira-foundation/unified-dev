import { invoke } from "@tauri-apps/api/core";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { useAgentsStore } from "../stores/useAgentsStore";
import { useNavigationStore } from "../stores/navigation-store";
import { useI18n } from "../i18n/i18n";
import { queryKeys } from "../lib/query-keys";
import { resolveCurrentLogin } from "../lib/work-visibility";
import type { IssueDto } from "../types/issue";
import type { OrganizationSummary } from "../types/organization";
import type { ProviderSummary } from "../types/provider";

interface DelegateResponse {
  repository: { id: string; name: string };
  thread: { id: string; title: string; workspace_path: string };
}

export function useDelegateIssue() {
  const { t } = useI18n();
  const { repositoryGroups, addThread, addRepository, setSelectedIssueId, sendMessage, selectedModelId } = useAgentsStore();
  const { navigateTo } = useNavigationStore();
  const queryClient = useQueryClient();

  const moveIssueToInProgress = async (issue: IssueDto) => {
    const organizations = queryClient.getQueryData<OrganizationSummary[]>(queryKeys.organizations()) ?? [];
    const providers = queryClient.getQueryData<ProviderSummary[]>(queryKeys.providers()) ?? [];
    const currentLogin = resolveCurrentLogin(issue.orgId, organizations, providers);
    if (!currentLogin || (issue.assignees ?? []).includes(currentLogin)) return;

    try {
      await invoke("update_issue", {
        orgId: issue.orgId,
        repoName: issue.repoName,
        number: issue.number,
        issueId: issue.id,
        input: { assignees: Array.from(new Set([...(issue.assignees ?? []), currentLogin])) },
      });
      queryClient.invalidateQueries({ queryKey: queryKeys.issues(issue.orgId, issue.repoName) });
    } catch (assignError) {
      console.warn("delegate: failed to move issue to in progress", assignError);
    }
  };

  const delegateIssue = async (issue: IssueDto) => {
    const loadingToast = toast.loading(t("issues.detail.delegating"));
    try {
      const response = await invoke<DelegateResponse>("delegate_issue_to_agent", {
        orgId: issue.orgId,
        repoName: issue.repoName,
        issueTitle: issue.title,
        issueIdentifier: issue.externalId ?? null,
      });

      const { repository, thread } = response;

      const allRepos = repositoryGroups.flatMap((g) => g.repositories);
      const existing = allRepos.find((r) => r.id === repository.id);

      if (existing) {
        addThread(repository.id, thread);
      } else {
        addRepository(repository, thread);
      }

      setSelectedIssueId(thread.id);

      await moveIssueToInProgress(issue);

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
