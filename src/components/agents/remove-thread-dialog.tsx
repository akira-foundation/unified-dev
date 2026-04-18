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

interface RemoveThreadDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onRemove: () => void;
  threadTitle: string;
  isRemoving?: boolean;
}

export function RemoveThreadDialog({
  open,
  onOpenChange,
  onRemove,
  threadTitle,
  isRemoving
}: RemoveThreadDialogProps) {
  const { t } = useI18n();
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-[420px]">
        <DialogHeader>
          <DialogTitle>{t("dialogs.removeThread.title")}</DialogTitle>
          <DialogDescription>
            {t("dialogs.removeThread.description").replace("{title}", threadTitle)}
          </DialogDescription>
        </DialogHeader>

        <DialogFooter>
          <Button
            variant="outline"
            size="sm"
            onClick={() => onOpenChange(false)}
            disabled={isRemoving}
          >
            {t("common.cancel")}
          </Button>
          <Button
            onClick={onRemove}
            size="sm"
            className="flex-1 bg-red-500 text-white hover:bg-red-600"
            disabled={isRemoving}
          >
            {isRemoving ? (
              <span className="flex items-center gap-2">
                <Loader2 className="w-4 h-4 animate-spin" />
                {t("dialogs.removeThread.removing")}
              </span>
            ) : t("dialogs.removeThread.remove")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
