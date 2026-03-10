import { useEffect } from "react";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";

import type { ProviderSummary } from "../../types/provider";
import { Button } from "../ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../ui/dialog";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "../ui/form";
import { Input } from "../ui/input";

interface UpdateProviderDialogProps {
  provider: ProviderSummary | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSubmit: (payload: { providerId: string; token: string }) => Promise<void> | void;
}

const updateSchema = z.object({
  token: z.string().trim().min(10, "Token is required"),
});

export function UpdateProviderDialog({ provider, open, onOpenChange, onSubmit }: UpdateProviderDialogProps) {
  const form = useForm<z.infer<typeof updateSchema>>({
    resolver: zodResolver(updateSchema),
    mode: "onChange",
    defaultValues: {
      token: "",
    },
  });

  useEffect(() => {
    if (!open) {
      form.reset({ token: "" });
    }
  }, [open, form]);

  const handleSubmit = form.handleSubmit(async (values) => {
    if (!provider) {
      return;
    }
    await onSubmit({ providerId: provider.id, token: values.token.trim() });
    onOpenChange(false);
  });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Update token</DialogTitle>
          <DialogDescription>
            {provider ? `Update token for ${provider.name}.` : "Update provider token."}
          </DialogDescription>
        </DialogHeader>
        <Form {...form}>
          <form className="mt-4 flex flex-col gap-4" onSubmit={handleSubmit}>
            <FormField
              control={form.control}
              name="token"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Personal access token</FormLabel>
                  <FormControl>
                    <Input type="password" placeholder="ghp_..." {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <DialogFooter>
              <Button variant="ghost" type="button" onClick={() => onOpenChange(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={!form.formState.isValid || form.formState.isSubmitting}>
                {form.formState.isSubmitting ? "Saving..." : "Update token"}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
