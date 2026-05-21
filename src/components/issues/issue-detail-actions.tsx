import { ArrowDown, ArrowUp, ExternalLink, GitBranch, Hash, Link2 } from "lucide-react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { toast } from "sonner";

import { AppbarActions } from "@/components/layout/appbar-actions";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { useNavigationStore } from "@/stores/navigation-store";
import { useI18n } from "@/i18n/i18n";
import type { IssueDto } from "@/types/issue";

function slug(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
}

async function copy(value: string, message: string) {
  try {
    await navigator.clipboard.writeText(value);
    toast.success(message);
  } catch (err) {
    toast.error(err instanceof Error ? err.message : String(err));
  }
}

async function open(url: string) {
  try {
    await openUrl(url);
  } catch {
    window.open(url, "_blank");
  }
}

function IconButton({
  label,
  onClick,
  disabled,
  children,
}: {
  label: string;
  onClick: () => void;
  disabled?: boolean;
  children: React.ReactNode;
}) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button variant="outline" size="icon-sm" onClick={onClick} disabled={disabled}>
          {children}
        </Button>
      </TooltipTrigger>
      <TooltipContent>{label}</TooltipContent>
    </Tooltip>
  );
}

export function IssueDetailActions({ issue }: { issue: IssueDto }) {
  const { t } = useI18n();
  const branchName = `${issue.number}-${slug(issue.title)}`;
  const issueList = useNavigationStore((s) => s.issueList);
  const setActiveIssue = useNavigationStore((s) => s.setActiveIssue);
  const index = issueList.findIndex((i) => i.id === issue.id);
  const total = issueList.length;
  const go = (delta: number) => {
    const next = issueList[index + delta];
    if (next) setActiveIssue(next);
  };

  return (
    <AppbarActions>
      {index >= 0 && total > 1 && (
        <div className="flex items-center gap-1 pr-1">
          <span className="text-[11px] tabular-nums text-zinc-500">{index + 1}/{total}</span>
          <IconButton label={t("issues.detail.prevIssue")} onClick={() => go(-1)} disabled={index <= 0}>
            <ArrowUp className="h-4 w-4" />
          </IconButton>
          <IconButton label={t("issues.detail.nextIssue")} onClick={() => go(1)} disabled={index >= total - 1}>
            <ArrowDown className="h-4 w-4" />
          </IconButton>
        </div>
      )}
      {issue.url && (
        <IconButton label={t("issues.detail.copyLink")} onClick={() => void copy(issue.url, t("issues.detail.linkCopied"))}>
          <Link2 className="h-4 w-4" />
        </IconButton>
      )}
      <IconButton label={t("issues.detail.copyId")} onClick={() => void copy(`${issue.repoName}#${issue.number}`, t("issues.detail.idCopied"))}>
        <Hash className="h-4 w-4" />
      </IconButton>
      <IconButton label={t("issues.detail.copyBranch")} onClick={() => void copy(branchName, t("issues.detail.branchCopied"))}>
        <GitBranch className="h-4 w-4" />
      </IconButton>
      {issue.url && (
        <IconButton label={t("issues.detail.openUrl")} onClick={() => void open(issue.url)}>
          <ExternalLink className="h-4 w-4" />
        </IconButton>
      )}
    </AppbarActions>
  );
}
