import { useState } from "react";

import type { ProviderSummary } from "../../types/provider";
import { Button } from "../ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../ui/dialog";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";

interface AddOrganizationDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  providers: ProviderSummary[];
  onSubmit: (payload: { name: string; provider_id: string }) => Promise<void> | void;
}

export function AddOrganizationDialog({ open, onOpenChange, providers, onSubmit }: AddOrganizationDialogProps) {
  const [name, setName] = useState("");
  const [providerId, setProviderId] = useState<string>("");
  const [isSaving, setIsSaving] = useState(false);

  const handleSubmit = async () => {
    if (!name.trim() || !providerId) {
      return;
    }
    setIsSaving(true);
    try {
      await onSubmit({ name: name.trim(), provider_id: providerId });
      setName("");
      setProviderId("");
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
          <DialogDescription>Link an organization to an existing provider.</DialogDescription>
        </DialogHeader>
        <div className="mt-4 flex flex-col gap-4">
          <label className="flex flex-col gap-2 text-sm text-gray-700 dark:text-gray-300">
            Organization name
            <Input value={name} onChange={(event) => setName(event.target.value)} placeholder="Acme Inc" />
          </label>
          <label className="flex flex-col gap-2 text-sm text-gray-700 dark:text-gray-300">
            Provider
            <Select value={providerId} onValueChange={setProviderId}>
              <SelectTrigger>
                <SelectValue placeholder="Select provider" />
              </SelectTrigger>
              <SelectContent>
                {providers.map((provider) => (
                  <SelectItem key={provider.id} value={provider.id}>
                    {provider.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
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
