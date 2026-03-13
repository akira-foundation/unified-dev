import { useEffect } from "react";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";

import type { ProviderKind } from "../../types/provider";
import { Button } from "../ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../ui/dialog";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "../ui/form";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";

interface AddProviderDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSubmit: (payload: { name: string; kind: ProviderKind; token: string }) => Promise<void> | void;
  defaultKind?: ProviderKind;
}

const providerSchema = z.object({
  kind: z.enum(["github", "gitlab", "bitbucket"]),
  name: z.string().trim().min(2, "Display name is required"),
  token: z.string().trim().min(10, "Token is required"),
});

export const TOKEN_META: Record<string, { label: string; placeholder: string; hint: string }> = {
  github: {
    label: "Personal access token",
    placeholder: "ghp_...",
    hint: "Ensure the token has read:org (and repo for private repos), otherwise organization import will fail.",
  },
  gitlab: {
    label: "Personal access token",
    placeholder: "glpat-...",
    hint: "Ensure the token has read_api and read_user scopes, otherwise project import will fail.",
  },
  bitbucket: {
    label: "App password",
    placeholder: "ATB...",
    hint: "Create an App Password in Bitbucket Settings with Repositories: Read and Account: Read permissions.",
  },
};

export function AddProviderDialog({ open, onOpenChange, onSubmit, defaultKind }: AddProviderDialogProps) {
  const form = useForm<z.infer<typeof providerSchema>>({
    // @ts-expect-error - version mismatch between zod and hook-form resolver
    resolver: zodResolver(providerSchema),
    mode: "onChange",
    defaultValues: {
      kind: defaultKind ?? "github",
      name: "",
      token: "",
    },
  });

  useEffect(() => {
    if (!open) {
      form.reset({ kind: defaultKind ?? "github", name: "", token: "" });
    }
  }, [open, form, defaultKind]);

  const handleSubmit = form.handleSubmit(async (values) => {
    try {
      await onSubmit({
        name: values.name.trim(),
        kind: values.kind as ProviderKind,
        token: values.token.trim(),
      });
      onOpenChange(false);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Failed to save provider";
      form.setError("root", { message });
    }
  });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add provider</DialogTitle>
          <DialogDescription>Create a reusable provider configuration.</DialogDescription>
        </DialogHeader>
        <Form {...form}>
          <form className="mt-4 flex flex-col gap-4" onSubmit={handleSubmit}>
            <FormField
              control={form.control}
              name="kind"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Provider kind</FormLabel>
                  <FormControl>
                    <Select value={field.value} onValueChange={field.onChange}>
                      <SelectTrigger>
                        <SelectValue placeholder="Select provider" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="github">GitHub</SelectItem>
                        <SelectItem value="gitlab">GitLab</SelectItem>
                        <SelectItem value="bitbucket">Bitbucket</SelectItem>
                      </SelectContent>
                    </Select>
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="name"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Display name</FormLabel>
                  <FormControl>
                    <Input placeholder="e.g. Personal" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="token"
              render={({ field }) => {
                const meta = TOKEN_META[form.watch("kind")] ?? TOKEN_META.github;
                return (
                  <FormItem>
                    <FormLabel>{meta.label}</FormLabel>
                    <FormControl>
                      <Input type="password" placeholder={meta.placeholder} {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                );
              }}
            />
            <div className="rounded-lg border border-amber-200/60 bg-amber-50/60 p-3 text-xs text-amber-900 dark:border-amber-500/20 dark:bg-amber-500/10 dark:text-amber-200">
              {TOKEN_META[form.watch("kind")]?.hint ?? TOKEN_META.github.hint}
            </div>
            <DialogFooter>
              <Button variant="ghost" type="button" onClick={() => onOpenChange(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={!form.formState.isValid || form.formState.isSubmitting}>
                {form.formState.isSubmitting ? "Saving..." : "Save provider"}
              </Button>
            </DialogFooter>
            {form.formState.errors.root?.message && (
              <div className="text-sm text-destructive">{form.formState.errors.root.message}</div>
            )}
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
