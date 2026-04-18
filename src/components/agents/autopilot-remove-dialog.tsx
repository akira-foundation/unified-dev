import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { useI18n } from "@/i18n/i18n";

interface AutopilotRemoveDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  repoName: string;
  onConfirm: (options: { removeThreads: boolean }) => void | Promise<void>;
}

export function AutopilotRemoveDialog({ open, onOpenChange, repoName, onConfirm }: AutopilotRemoveDialogProps) {
  const { t } = useI18n();
  const [removeThreads, setRemoveThreads] = useState(false);

  function handleOpenChange(nextOpen: boolean) {
    if (!nextOpen) {
      setRemoveThreads(false);
    }

    onOpenChange(nextOpen);
  }

  async function handleConfirm() {
    await onConfirm({ removeThreads });
    setRemoveThreads(false);
    onOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="max-w-[420px]">
        <DialogHeader>
          <DialogTitle>{t("autopilot.remove.title")}</DialogTitle>
          <DialogDescription>
            {t("autopilot.remove.description").replace("{repo}", repoName)}
          </DialogDescription>
        </DialogHeader>

        <div className="px-5 py-4">
          <div className="flex items-center gap-3 rounded-md border border-border bg-zinc-100/60 px-3 py-3 dark:bg-zinc-800/60">
            <Switch
              id="delete-autopilot-threads"
              checked={removeThreads}
              onCheckedChange={setRemoveThreads}
            />
            <label htmlFor="delete-autopilot-threads" className="cursor-pointer select-none text-sm">
              {t("autopilot.remove.deleteThreads")}
            </label>
          </div>

          {removeThreads && (
            <p className="mt-3 text-xs text-red-400">
              {t("autopilot.remove.deleteThreadsWarning")}
            </p>
          )}
        </div>

        <DialogFooter className="border-t border-border pt-4">
          <Button variant="outline" size="sm" onClick={() => handleOpenChange(false)}>
            {t("common.cancel")}
          </Button>
          <Button
            size="sm"
            className="flex-1 bg-red-500 text-white hover:bg-red-600"
            onClick={() => void handleConfirm()}
          >
            {t("autopilot.remove.action")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
