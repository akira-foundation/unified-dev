import { useState, type ReactNode } from "react";
import {
  Calendar,
  CheckCircle2,
  ChevronDown,
  Clock,
  GitBranch,
  GitMerge,
  GitPullRequest,
  GitPullRequestDraft,
  UserCircle2,
  Users,
  XCircle,
} from "lucide-react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import type { PullRequestDto } from "@/types/organization";
import { PrLabelsEditor } from "./pr-labels-editor";

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

function stateMeta(pr: PullRequestDto) {
  if (pr.merged_at !== null) return { icon: <GitMerge className="h-3.5 w-3.5 text-purple-500" />, key: "prs.filter.merged" };
  if (pr.is_draft) return { icon: <GitPullRequestDraft className="h-3.5 w-3.5 text-zinc-400" />, key: "components.prItem.draft" };
  return { icon: <GitPullRequest className="h-3.5 w-3.5 text-emerald-500" />, key: "prs.filter.open" };
}

function CiRow({ status }: { status: string }) {
  const map = {
    success: { icon: <CheckCircle2 className="h-3.5 w-3.5 text-emerald-500" /> },
    failure: { icon: <XCircle className="h-3.5 w-3.5 text-red-500" /> },
    pending: { icon: <Clock className="h-3.5 w-3.5 text-amber-500" /> },
  } as const;
  const meta = map[status as keyof typeof map] ?? { icon: <Clock className="h-3.5 w-3.5 text-zinc-400" /> };
  return <Row icon={meta.icon}>{status}</Row>;
}

export function PrProperties({ pr, organizationId, repoName }: { pr: PullRequestDto; organizationId: string; repoName: string }) {
  const { t } = useI18n();
  const state = stateMeta(pr);

  return (
    <div className="flex flex-col gap-3">
      <Section title={t("issues.detail.properties")}>
        <Row icon={state.icon}>{t(state.key)}</Row>
        <Row icon={<GitBranch className="h-3.5 w-3.5" />}>
          <span className="font-mono text-[12px]">{pr.head} &rarr; {pr.base}</span>
        </Row>
        {pr.author && <Row icon={<UserCircle2 className="h-3.5 w-3.5" />}>{pr.author}</Row>}
        {pr.ci_status && <CiRow status={pr.ci_status} />}
        <Row icon={<Calendar className="h-3.5 w-3.5" />}>{new Date(pr.created_at).toLocaleDateString()}</Row>
        <Row icon={<Clock className="h-3.5 w-3.5" />}>{new Date(pr.updated_at).toLocaleDateString()}</Row>
      </Section>

      {pr.reviewers.length > 0 && (
        <Section title={t("components.prDetail.labelReviewers")}>
          {pr.reviewers.map((r) => (
            <Row key={r} icon={<Users className="h-3.5 w-3.5" />}>{r}</Row>
          ))}
        </Section>
      )}

      <Section title={t("issues.detail.labelLabels")}>
        <PrLabelsEditor
          organizationId={organizationId}
          repoName={repoName}
          prNumber={pr.number}
          labels={pr.labels}
        />
      </Section>
    </div>
  );
}
