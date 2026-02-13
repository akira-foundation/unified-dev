import { useState } from "react";

import { Button } from "../ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../ui/dialog";
import { Input } from "../ui/input";

interface AddOrganizationDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSubmit: (payload: { name: string; token: string }) => Promise<void> | void;
}

export function AddOrganizationDialog({ open, onOpenChange, onSubmit }: AddOrganizationDialogProps) {
  const [name, setName] = useState("");
  const [token, setToken] = useState("");
  const [isSaving, setIsSaving] = useState(false);

  const handleSubmit = async () => {
    if (!name.trim() || !token.trim()) {
      return;
    }
    setIsSaving(true);
    try {
      await onSubmit({ name: name.trim(), token: token.trim() });
      setName("");
      setToken("");
      onOpenChange(false);
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add organization</DialogTitle>
          <DialogDescription>Store a GitHub organization token securely for sync access.</DialogDescription>
        </DialogHeader>
        <div className="mt-4 flex flex-col gap-4">
          <label className="flex flex-col gap-2 text-sm text-gray-700 dark:text-gray-300">
            Organization name
            <Input value={name} onChange={(event) => setName(event.target.value)} placeholder="Acme Inc" />
          </label>
          <label className="flex flex-col gap-2 text-sm text-gray-700 dark:text-gray-300">
            GitHub token
            <Input
              type="password"
              value={token}
              onChange={(event) => setToken(event.target.value)}
              placeholder="ghp_..."
            />
          </label>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={isSaving}>
            Cancel
          </Button>
          <Button onClick={handleSubmit} disabled={isSaving}>
            {isSaving ? "Saving..." : "Save organization"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
