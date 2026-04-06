import { useEffect } from "react";
import { z } from "zod";
import { useI18n } from "../../i18n/i18n";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";

import type { OrganizationSummary, UpdateOrganizationInput } from "../../types/organization";
import type { ProviderSummary } from "../../types/provider";
import { Button } from "../ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../ui/dialog";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "../ui/form";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";

interface EditOrganizationDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  organization: OrganizationSummary | null;
  providers: ProviderSummary[];
  onSubmit: (input: UpdateOrganizationInput) => Promise<unknown> | void;
}

const editOrganizationSchema = z.object({
  name: z.string().trim().min(2, "Organization name is required"),
  provider_id: z.string().nullable().optional(),
});

export function EditOrganizationDialog({ open, onOpenChange, organization, providers, onSubmit }: EditOrganizationDialogProps) {
  const { t } = useI18n();
  const form = useForm<z.infer<typeof editOrganizationSchema>>({
    resolver: zodResolver(editOrganizationSchema),
    mode: "onChange",
    defaultValues: {
      name: "",
      provider_id: null,
    },
  });

  useEffect(() => {
    if (open && organization) {
      form.reset({
        name: organization.name,
        provider_id: organization.provider_id ?? null,
      });
    } else if (!open) {
      form.reset({ name: "", provider_id: null });
    }
  }, [open, organization, form]);

  const handleSubmit = form.handleSubmit(async (values) => {
    if (!organization) return;
    try {
      await onSubmit({
        id: organization.id,
        name: values.name.trim(),
        provider_id: values.provider_id ?? null,
      });
      onOpenChange(false);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Failed to update organization";
      form.setError("root", { message });
    }
  });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("dialogs.editOrg.title")}</DialogTitle>
          <DialogDescription>{t("dialogs.editOrg.description")}</DialogDescription>
        </DialogHeader>
        <Form {...form}>
          <form className="mt-4 flex flex-col gap-4" onSubmit={handleSubmit}>
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
                    <Select value={field.value ?? ""} onValueChange={(val) => field.onChange(val || null)}>
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
            <DialogFooter>
              <Button variant="ghost" type="button" onClick={() => onOpenChange(false)}>
                {t("common.cancel")}
              </Button>
              <Button type="submit" disabled={!form.formState.isValid || form.formState.isSubmitting}>
                {form.formState.isSubmitting ? t("common.saving") : t("dialogs.editOrg.save")}
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
