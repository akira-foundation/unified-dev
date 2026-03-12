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
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Discard Changes</DialogTitle>
          <DialogDescription>
            Are you sure you want to discard all changes to{" "}
            <strong className="text-foreground font-mono">{filename}</strong>?
            This will restore the file to its last committed state. This action cannot be undone.
          </DialogDescription>
        </DialogHeader>

        <DialogFooter className="mt-6">
          <Button
            variant="ghost"
            onClick={() => onOpenChange(false)}
            disabled={isDiscarding}
          >
            Cancel
          </Button>
          <Button
            onClick={onDiscard}
            className="px-8 bg-red-500 hover:bg-red-600 text-white"
            disabled={isDiscarding}
          >
            {isDiscarding ? (
              <span className="flex items-center gap-2">
                <Loader2 className="w-4 h-4 animate-spin" />
                Discarding...
              </span>
            ) : "Discard"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
