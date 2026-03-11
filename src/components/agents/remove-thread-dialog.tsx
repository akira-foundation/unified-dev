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
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Remove Thread</DialogTitle>
          <DialogDescription>
            Are you sure you want to remove the thread <strong className="text-foreground">{threadTitle}</strong>? This will delete all associated workspace files. This action cannot be undone.
          </DialogDescription>
        </DialogHeader>

        <DialogFooter className="mt-6">
          <Button
            variant="ghost"
            onClick={() => onOpenChange(false)}
            disabled={isRemoving}
          >
            Cancel
          </Button>
          <Button
            onClick={onRemove}
            className="px-8 bg-red-500 hover:bg-red-600 text-white"
            disabled={isRemoving}
          >
            {isRemoving ? (
              <span className="flex items-center gap-2">
                <Loader2 className="w-4 h-4 animate-spin" />
                Removing...
              </span>
            ) : "Remove"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
