import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Bot, Loader2 } from "lucide-react";

import { useNavigationStore } from "@/stores/navigation-store";
import { useDelegateIssue } from "@/hooks/useDelegateIssue";
import { useIssueBodyEditor } from "@/hooks/useIssueBodyEditor";
import { useI18n } from "@/i18n/i18n";
import { queryKeys } from "@/lib/query-keys";
import { StatusIcon } from "@/components/issues/issue-status";
import { IssueDescription } from "@/components/issues/issue-description";
import { IssueProperties } from "@/components/issues/issue-properties";
import { IssueActivity } from "@/components/issues/issue-activity";
import { IssueDetailActions } from "@/components/issues/issue-detail-actions";
import { issueToColumn } from "@/types/issue";

export function IssueDetailPage() {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const issue = useNavigationStore((s) => s.activeIssue);
  const issueList = useNavigationStore((s) => s.issueList);
  const setActiveIssue = useNavigationStore((s) => s.setActiveIssue);
  const goBack = useNavigationStore((s) => s.goBack);
  const navigateTo = useNavigationStore((s) => s.navigateTo);
  const { delegateIssue } = useDelegateIssue();
  const [resolving, setResolving] = useState(false);
  const editor = useIssueBodyEditor(issue);

  useEffect(() => {
    if (!issue) navigateTo("issues");
  }, [issue, navigateTo]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!(e.metaKey || e.ctrlKey) || (e.key !== "ArrowUp" && e.key !== "ArrowDown")) return;
      if (!issue) return;
      const idx = issueList.findIndex((i) => i.id === issue.id);
      if (idx < 0) return;
      const next = issueList[idx + (e.key === "ArrowUp" ? -1 : 1)];
      if (next) {
        e.preventDefault();
        setActiveIssue(next);
      }
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [issue, issueList, setActiveIssue]);

  const closeMutation = useMutation({
    mutationFn: async () => {
      if (!issue) return;
      await invoke("close_issue", {
        orgId: issue.orgId,
        repoName: issue.repoName,
        number: issue.number,
        reason: "completed",
      });
    },
    onSuccess: () => {
      if (!issue) return;
      queryClient.invalidateQueries({ queryKey: queryKeys.issues(issue.orgId, issue.repoName) });
      toast.success(t("issues.detail.toastClosed"));
      goBack();
    },
    onError: (err: unknown) => toast.error(err instanceof Error ? err.message : String(err)),
  });

  if (!issue) return null;

  const handleResolve = async () => {
    setResolving(true);
    try {
      await delegateIssue(issue);
      goBack();
    } finally {
      setResolving(false);
    }
  };

  return (
    <div className="flex h-[calc(100vh-4rem)]">
      <IssueDetailActions issue={issue} />
      <div className="min-w-0 flex-1 overflow-y-auto custom-scrollbar">
        <div className="mx-auto max-w-3xl px-6 py-8 md:px-10">
          <div className="flex items-start gap-3">
            <StatusIcon column={issueToColumn(issue)} className="mt-1.5 h-4 w-4" />
            <h1 className="text-2xl font-bold leading-snug text-zinc-900 dark:text-white">{issue.title}</h1>
          </div>
          <div className="ml-7 mt-1 flex items-center gap-1.5 text-xs text-zinc-500">
            <span>{issue.repoName}</span>
            <span>·</span>
            <span>#{issue.number}</span>
          </div>

          <div className="mt-8">
            <IssueDescription editor={editor} />
          </div>

          <IssueActivity issue={issue} />
        </div>
      </div>

      <aside className="flex w-80 shrink-0 flex-col gap-3 overflow-y-auto p-4">
        <button
          onClick={handleResolve}
          disabled={resolving}
          className="flex items-center justify-center gap-2 rounded-lg border border-emerald-500/20 bg-emerald-500/5 px-3 py-2.5 text-[13px] font-medium text-emerald-500 transition-colors hover:border-emerald-500/40 hover:bg-emerald-500/10 disabled:opacity-50"
        >
          {resolving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Bot className="h-4 w-4" />}
          {resolving ? t("issues.detail.delegating") : t("issues.detail.delegate")}
        </button>

        <IssueProperties
          issue={issue}
          onClose={() => closeMutation.mutate()}
          closing={closeMutation.isPending}
        />
      </aside>
    </div>
  );
}
