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
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{t("dialogs.removeRepository.title")}</DialogTitle>
          <DialogDescription>
            {t("dialogs.removeRepository.description").replace("{name}", repoName)}
          </DialogDescription>
        </DialogHeader>

        {!localOnly && (
          <div className="flex items-center gap-3 py-2">
            <Switch
              id="delete-remote"
              checked={deleteRemote}
              onCheckedChange={setDeleteRemote}
              disabled={isRemoving}
            />
            <label htmlFor="delete-remote" className="text-sm cursor-pointer select-none">
              {t("dialogs.removeRepository.deleteRemote")}
            </label>
          </div>
        )}
        {!localOnly && deleteRemote && (
          <p className="text-xs text-red-400">
            {t("dialogs.removeRepository.deleteRemoteWarning").replace("{name}", repoName)}
          </p>
        )}

        <DialogFooter className="mt-2">
          <Button
            variant="ghost"
            onClick={() => handleOpenChange(false)}
            disabled={isRemoving}
          >
            {t("common.cancel")}
          </Button>
          <Button
            onClick={() => onRemove(deleteRemote)}
            className="px-8 bg-red-500 hover:bg-red-600 text-white"
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
