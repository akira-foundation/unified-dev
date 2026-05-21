import { useState, type ReactNode } from "react";
import { Calendar, ChevronDown, CircleCheck, Clock, Cloud, FolderGit2, GitPullRequest, Loader2, Tag, UserCircle2 } from "lucide-react";

import { cn } from "@/lib/utils";
import { LabelBadge } from "@/components/issues/label-badge";
import { StatusIcon, COLUMN_LABEL } from "@/components/issues/issue-status";
import { useI18n } from "@/i18n/i18n";
import { issueToColumn, type IssueDto } from "@/types/issue";

function Section({ title, children }: { title: string; children: ReactNode }) {
  const [open, setOpen] = useState(true);
  return (
    <div className="flex flex-col rounded-lg bg-zinc-100/60 px-2 py-1.5 dark:bg-white/[0.03]">
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex items-center gap-1 px-1 py-1 text-[12px] font-medium text-zinc-500 transition-colors hover:text-zinc-700 dark:hover:text-zinc-300"
      >
        {title}
        <ChevronDown className={cn("h-3 w-3 transition-transform", !open && "-rotate-90")} />
      </button>
      {open && <div className="flex flex-col">{children}</div>}
    </div>
  );
}

function Row({ icon, children }: { icon: ReactNode; children: ReactNode }) {
  return (
    <div className="flex items-center gap-2 rounded-md px-1 py-1.5 text-[13px] text-zinc-700 dark:text-zinc-200">
      <span className="flex h-4 w-4 shrink-0 items-center justify-center text-zinc-500">{icon}</span>
      <span className="min-w-0 truncate">{children}</span>
    </div>
  );
}

function Initials({ name }: { name: string }) {
  return (
    <span className="flex h-4 w-4 items-center justify-center rounded-full bg-zinc-300 text-[8px] font-semibold text-zinc-700 dark:bg-zinc-600 dark:text-zinc-200">
      {name.slice(0, 2).toUpperCase()}
    </span>
  );
}

export function IssueProperties({
  issue,
  onClose,
  closing,
}: {
  issue: IssueDto;
  onClose?: () => void;
  closing?: boolean;
}) {
  const { t } = useI18n();
  const column = issueToColumn(issue);
  const assigneeLabel =
    issue.assignees.length > 0
      ? issue.assignees[0] + (issue.assignees.length > 1 ? ` +${issue.assignees.length - 1}` : "")
      : null;

  return (
    <div className="flex flex-col gap-3">
      <Section title={t("issues.detail.properties")}>
        <Row icon={<StatusIcon column={column} />}>{COLUMN_LABEL[column]}</Row>
        <Row icon={<Cloud className="h-3.5 w-3.5" />}>{issue.syncWithProvider ? t("issues.detail.synced") : t("issues.detail.local")}</Row>
        {issue.author && <Row icon={<UserCircle2 className="h-3.5 w-3.5" />}>{issue.author}</Row>}
        {assigneeLabel && <Row icon={<Initials name={issue.assignees[0]} />}>{assigneeLabel}</Row>}
        {issue.linkedPrNumbers.map((n) => (
          <Row key={n} icon={<GitPullRequest className="h-3.5 w-3.5" />}>
            <span className="text-purple-500">#{n}</span>
          </Row>
        ))}
        <Row icon={<Calendar className="h-3.5 w-3.5" />}>{new Date(issue.createdAt).toLocaleDateString()}</Row>
        <Row icon={<Clock className="h-3.5 w-3.5" />}>{new Date(issue.updatedAt).toLocaleDateString()}</Row>
      </Section>

      <Section title={t("issues.detail.labelLabels")}>
        {issue.labels.length > 0 ? (
          <div className="flex flex-wrap gap-1.5 px-1 py-1">
            {issue.labels.map((label) => (
              <LabelBadge key={label} name={label} />
            ))}
          </div>
        ) : (
          <Row icon={<Tag className="h-3.5 w-3.5" />}>
            <span className="text-zinc-500">{t("issues.detail.addLabel")}</span>
          </Row>
        )}
      </Section>

      <Section title={t("issues.detail.project")}>
        <Row icon={<FolderGit2 className="h-3.5 w-3.5" />}>{issue.repoName}</Row>
      </Section>

      {issue.status === "open" && onClose && (
        <button
          onClick={onClose}
          disabled={closing}
          className="flex items-center justify-center gap-2 rounded-lg border border-red-500/20 bg-red-500/5 px-3 py-2.5 text-[13px] font-medium text-red-500 transition-colors hover:border-red-500/40 hover:bg-red-500/10 disabled:opacity-50"
        >
          {closing ? <Loader2 className="h-4 w-4 animate-spin" /> : <CircleCheck className="h-4 w-4" />}
          {closing ? t("issues.detail.closing") : t("issues.detail.close")}
        </button>
      )}
    </div>
  );
}
