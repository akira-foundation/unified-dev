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
import { Loader2 } from "lucide-react";
import { useI18n } from "@/i18n/i18n";

interface RemoveRepositoryDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onRemove: (deleteRemote: boolean) => void;
  repoName: string;
  isRemoving?: boolean;
  localOnly?: boolean;
}

export function RemoveRepositoryDialog({
  open,
  onOpenChange,
  onRemove,
  repoName,
  isRemoving,
  localOnly = false,
}: RemoveRepositoryDialogProps) {
  const { t } = useI18n();
  const [deleteRemote, setDeleteRemote] = useState(false);

  function handleOpenChange(value: boolean) {
    if (!value) setDeleteRemote(false);
    onOpenChange(value);
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="max-w-[420px]">
        <DialogHeader>
          <DialogTitle>{t("dialogs.removeRepository.title")}</DialogTitle>
          <DialogDescription>
            {t("dialogs.removeRepository.description").replace("{name}", repoName)}
          </DialogDescription>
        </DialogHeader>

        {!localOnly && (
          <div className="px-5 py-4">
            <div className="flex items-center gap-3 rounded-md border border-border bg-zinc-100/60 px-3 py-3 dark:bg-zinc-800/60">
              <Switch
                id="delete-remote"
                checked={deleteRemote}
                onCheckedChange={setDeleteRemote}
                disabled={isRemoving}
              />
              <label htmlFor="delete-remote" className="cursor-pointer select-none text-sm">
                {t("dialogs.removeRepository.deleteRemote")}
              </label>
            </div>
            {deleteRemote && (
              <p className="mt-3 text-xs text-red-400">
                {t("dialogs.removeRepository.deleteRemoteWarning").replace("{name}", repoName)}
              </p>
            )}
          </div>
        )}

        <DialogFooter className="border-t border-border pt-4">
          <Button
            variant="outline"
            size="sm"
            onClick={() => handleOpenChange(false)}
            disabled={isRemoving}
          >
            {t("common.cancel")}
          </Button>
          <Button
            onClick={() => onRemove(deleteRemote)}
            size="sm"
            className="flex-1 bg-red-500 text-white hover:bg-red-600"
            disabled={isRemoving}
          >
            {isRemoving ? (
              <span className="flex items-center gap-2">
                <Loader2 className="w-4 h-4 animate-spin" />
                {t("dialogs.removeRepository.removing")}
              </span>
            ) : t("dialogs.removeRepository.remove")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
