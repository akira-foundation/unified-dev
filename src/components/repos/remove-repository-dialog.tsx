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
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Remove Repository</DialogTitle>
          <DialogDescription>
            Are you sure you want to completely remove <strong className="text-foreground">{repoName}</strong> and all of its threads? This action cannot be undone.
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

