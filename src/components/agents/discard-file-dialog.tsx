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

interface DiscardFileDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onDiscard: () => void;
  filename: string;
  isDiscarding?: boolean;
}

export function DiscardFileDialog({
  open,
  onOpenChange,
  onDiscard,
  filename,
  isDiscarding,
}: DiscardFileDialogProps) {
  const { t } = useI18n();
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{t("dialogs.discardFile.title")}</DialogTitle>
          <DialogDescription>
            {t("dialogs.discardFile.description").replace("{filename}", filename)}
          </DialogDescription>
        </DialogHeader>

        <DialogFooter className="mt-6">
          <Button
            variant="ghost"
            onClick={() => onOpenChange(false)}
            disabled={isDiscarding}
          >
            {t("common.cancel")}
          </Button>
          <Button
            onClick={onDiscard}
            className="px-8 bg-red-500 hover:bg-red-600 text-white"
            disabled={isDiscarding}
          >
            {isDiscarding ? (
              <span className="flex items-center gap-2">
                <Loader2 className="w-4 h-4 animate-spin" />
                {t("dialogs.discardFile.discarding")}
              </span>
            ) : t("dialogs.discardFile.discard")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
