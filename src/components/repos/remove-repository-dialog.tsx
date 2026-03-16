import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Loader2 } from "lucide-react";
import { useI18n } from "@/i18n/i18n";

interface RemoveRepositoryDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onRemove: () => void;
  repoName: string;
  isRemoving?: boolean;
}

export function RemoveRepositoryDialog({
  open,
  onOpenChange,
  onRemove,
  repoName,
  isRemoving
}: RemoveRepositoryDialogProps) {
  const { t } = useI18n();
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{t("dialogs.removeRepository.title")}</DialogTitle>
          <DialogDescription>
            {t("dialogs.removeRepository.description").replace("{name}", repoName)}
          </DialogDescription>
        </DialogHeader>

        <DialogFooter className="mt-6">
          <Button
            variant="ghost"
            onClick={() => onOpenChange(false)}
            disabled={isRemoving}
          >
            {t("common.cancel")}
          </Button>
          <Button
            onClick={onRemove}
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

