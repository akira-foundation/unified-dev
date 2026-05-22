import { ExternalLink, GitBranch, Link2, MessageSquare } from "lucide-react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { toast } from "sonner";

import { AppbarActions } from "@/components/layout/appbar-actions";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { useI18n } from "@/i18n/i18n";
import type { PullRequestDto } from "@/types/organization";

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

function IconButton({ label, onClick, children }: { label: string; onClick: () => void; children: React.ReactNode }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button variant="outline" size="icon-sm" onClick={onClick}>
          {children}
        </Button>
      </TooltipTrigger>
      <TooltipContent>{label}</TooltipContent>
    </Tooltip>
  );
}

export function PrDetailActions({
  pr,
  onFinishReview,
}: {
  pr: PullRequestDto;
  onFinishReview: () => void;
}) {
  const { t } = useI18n();

  return (
    <AppbarActions>
      <Button onClick={onFinishReview} title={t("components.prReview.finishButton")}>
        <MessageSquare className="h-4 w-4 shrink-0" />
        <span className="hidden xl:inline">{t("components.prReview.finishButton")}</span>
      </Button>
      {pr.url && (
        <Button variant="outline" onClick={() => void open(pr.url)} title={t("components.prReview.viewPrButton")}>
          <ExternalLink className="h-4 w-4 shrink-0" />
          <span className="hidden xl:inline">{t("components.prReview.viewPrButton")}</span>
        </Button>
      )}
      {pr.url && (
        <IconButton label={t("issues.detail.copyLink")} onClick={() => void copy(pr.url, t("issues.detail.linkCopied"))}>
          <Link2 className="h-4 w-4" />
        </IconButton>
      )}
      <IconButton label={t("issues.detail.copyBranch")} onClick={() => void copy(pr.head, t("issues.detail.branchCopied"))}>
        <GitBranch className="h-4 w-4" />
      </IconButton>
    </AppbarActions>
  );
}
