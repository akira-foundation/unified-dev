import { useState } from "react";

import type { ProviderKind } from "../../types/provider";
import { Button } from "../ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../ui/dialog";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";

interface AddProviderDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSubmit: (payload: { name: string; kind: ProviderKind; token: string }) => Promise<void> | void;
}

export function AddProviderDialog({ open, onOpenChange, onSubmit }: AddProviderDialogProps) {
  const [name, setName] = useState("");
  const [kind, setKind] = useState<ProviderKind>("github");
  const [token, setToken] = useState("");
  const [isSaving, setIsSaving] = useState(false);

  const handleSubmit = async () => {
    if (!name.trim() || !token.trim()) {
      return;
    }
    setIsSaving(true);
    try {
      await onSubmit({ name: name.trim(), kind, token: token.trim() });
      setName("");
      setKind("github");
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
          <DialogTitle>Add provider</DialogTitle>
          <DialogDescription>Create a reusable provider configuration.</DialogDescription>
        </DialogHeader>
        <div className="mt-4 flex flex-col gap-4">
          <label className="flex flex-col gap-2 text-sm text-gray-700 dark:text-gray-300">
            Provider kind
            <Select value={kind} onValueChange={(value) => setKind(value as ProviderKind)}>
              <SelectTrigger>
                <SelectValue placeholder="Select provider" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="github">GitHub</SelectItem>
                <SelectItem value="gitlab">GitLab</SelectItem>
                <SelectItem value="bitbucket">Bitbucket</SelectItem>
              </SelectContent>
            </Select>
          </label>
          <label className="flex flex-col gap-2 text-sm text-gray-700 dark:text-gray-300">
            Display name
            <Input value={name} onChange={(event) => setName(event.target.value)} placeholder="GitHub Personal" />
          </label>
          <label className="flex flex-col gap-2 text-sm text-gray-700 dark:text-gray-300">
            Personal access token
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
            {isSaving ? "Saving..." : "Save provider"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
