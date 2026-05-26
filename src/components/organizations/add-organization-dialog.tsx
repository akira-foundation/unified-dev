import { useEffect } from "react";
import { z } from "zod";
import { useI18n } from "../../i18n/i18n";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";

import type { ProviderSummary } from "../../types/provider";
import { Button } from "../ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "../ui/dialog";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "../ui/form";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";

interface AddOrganizationDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  providers: ProviderSummary[];
  onSubmit: (payload: { name: string; provider_id: string }) => Promise<unknown> | void;
}

const organizationSchema = z.object({
  name: z.string().trim().min(2, "Organization name is required"),
  provider_id: z.string().min(1, "Provider is required"),
});

export function AddOrganizationDialog({ open, onOpenChange, providers, onSubmit }: AddOrganizationDialogProps) {
  const { t } = useI18n();
  const form = useForm<z.infer<typeof organizationSchema>>({
    resolver: zodResolver(organizationSchema),
    mode: "onChange",
    defaultValues: {
      name: "",
      provider_id: "",
    },
  });

  useEffect(() => {
    if (!open) {
      form.reset({ name: "", provider_id: "" });
    }
  }, [open, form]);

  const handleSubmit = form.handleSubmit(async (values) => {
    try {
      await onSubmit({
        name: values.name.trim(),
        provider_id: values.provider_id,
      });
      onOpenChange(false);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Failed to save organization";
      form.setError("root", { message });
    }
  });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-[420px] gap-0 overflow-hidden p-0">
        <DialogHeader className="border-b border-border px-5 pt-5 pb-4">
          <DialogTitle className="text-base">{t("dialogs.addOrg.title")}</DialogTitle>
          <p className="mt-1.5 text-sm text-muted-foreground">{t("dialogs.addOrg.description")}</p>
        </DialogHeader>
        <Form {...form}>
          <form className="flex flex-col gap-4 px-5 py-4" onSubmit={handleSubmit}>
            <FormField
              control={form.control}
              name="name"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>{t("dialogs.addOrg.nameLabel")}</FormLabel>
                  <FormControl>
                    <Input placeholder={t("dialogs.addOrg.namePlaceholder")} {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="provider_id"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>{t("dialogs.addOrg.providerLabel")}</FormLabel>
                  <FormControl>
                    <Select value={field.value} onValueChange={field.onChange}>
                      <SelectTrigger>
                        <SelectValue placeholder={t("dialogs.addOrg.providerPlaceholder")} />
                      </SelectTrigger>
                      <SelectContent>
                        {providers.map((provider) => (
                          <SelectItem key={provider.id} value={provider.id}>
                            {provider.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <DialogFooter className="flex gap-2 px-0 pb-0 pt-0">
              <Button variant="outline" size="sm" type="button" onClick={() => onOpenChange(false)}>
                {t("common.cancel")}
              </Button>
              <Button
                type="submit"
                size="sm"
                className="flex-1 bg-purple-600 text-white hover:bg-purple-700"
                disabled={!form.formState.isValid || form.formState.isSubmitting}
              >
                {form.formState.isSubmitting ? t("common.saving") : t("dialogs.addOrg.save")}
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
