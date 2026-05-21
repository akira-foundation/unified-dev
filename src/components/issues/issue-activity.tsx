import { CommentThread } from "@/components/shared/comment-thread";
import { useI18n } from "@/i18n/i18n";
import type { IssueDto } from "@/types/issue";

export function IssueActivity({ issue }: { issue: IssueDto }) {
  const { t } = useI18n();
  return (
    <CommentThread
      organizationId={issue.orgId}
      repoName={issue.repoName}
      number={issue.number}
      heading={t("issues.detail.activity")}
    />
  );
}
