import { Loader2, XCircle } from "lucide-react";

import { useI18n } from "@/i18n/i18n";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";

interface PrCloseDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  comment: string;
  onCommentChange: (comment: string) => void;
  isClosing: boolean;
  onConfirm: () => void;
}

export function PrCloseDialog({ open, onOpenChange, comment, onCommentChange, isClosing, onConfirm }: PrCloseDialogProps) {
  const { t } = useI18n();

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("components.prDetail.close.confirmTitle")}</DialogTitle>
          <DialogDescription>{t("components.prDetail.close.confirmDescription")}</DialogDescription>
        </DialogHeader>
        <Textarea
          value={comment}
          onChange={(e) => onCommentChange(e.target.value)}
          placeholder={t("components.prDetail.close.commentPlaceholder")}
          rows={3}
        />
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={isClosing}>
            {t("common.cancel")}
          </Button>
          <Button
            variant="ghost"
            className="border border-red-500/20 text-red-600 hover:bg-red-500/10 dark:text-red-400 dark:hover:bg-red-500/10"
            onClick={onConfirm}
            disabled={isClosing}
          >
            {isClosing ? <Loader2 className="h-4 w-4 animate-spin" /> : <XCircle className="h-4 w-4" />}
            {t("components.prDetail.close.action")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
