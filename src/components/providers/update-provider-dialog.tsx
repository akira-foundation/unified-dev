import { useEffect } from "react";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";

import { toast } from "sonner";

import type { ProviderSummary } from "../../types/provider";
import { TOKEN_META } from "./add-provider-dialog";
import { Button } from "../ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../ui/dialog";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "../ui/form";
import { Input } from "../ui/input";
import { useI18n } from "../../i18n/i18n";

interface UpdateProviderDialogProps {
  provider: ProviderSummary | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSubmit: (payload: { providerId: string; token: string }) => Promise<unknown> | void;
  onDisconnect?: () => Promise<void> | void;
}

const updateSchema = z.object({
  token: z.string().trim().min(10),
});

const KIND_LABEL: Record<string, string> = {
  github: "GitHub",
  gitlab: "GitLab",
  bitbucket: "Bitbucket",
};

export function UpdateProviderDialog({ provider, open, onOpenChange, onSubmit, onDisconnect }: UpdateProviderDialogProps) {
  const { t } = useI18n();
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
    if (!provider) return;
    await onSubmit({ providerId: provider.id, token: values.token.trim() });
    onOpenChange(false);
  });

  const handleDisconnect = async () => {
    if (!onDisconnect) return;
    const toastId = toast.loading(t("pages.providerDetail.toast.disconnecting"));
    try {
      await onDisconnect();
      toast.success(t("pages.providerDetail.toast.disconnected"), { id: toastId });
      onOpenChange(false);
    } catch (error) {
      const message = typeof error === "string" ? error : error instanceof Error ? error.message : t("pages.providerDetail.toast.disconnectFailed");
      toast.error(message, { id: toastId });
    }
  };

  const kindLabel = provider ? (KIND_LABEL[provider.kind] ?? provider.kind) : "";
  const meta = provider ? (TOKEN_META[provider.kind] ?? TOKEN_META.github) : TOKEN_META.github;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("dialogs.updateProvider.title").replace("{kind}", kindLabel)}</DialogTitle>
          <DialogDescription>
            {provider ? t("dialogs.updateProvider.description").replace("{name}", provider.name) : t("dialogs.updateProvider.descriptionFallback")}
          </DialogDescription>
        </DialogHeader>
        <Form {...form}>
          <form className="mt-4 flex flex-col gap-4" onSubmit={handleSubmit}>
            <FormField
              control={form.control}
              name="token"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>{meta.label}</FormLabel>
                  <FormControl>
                    <Input type="password" placeholder={meta.placeholder} {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <DialogFooter className="flex-row justify-between sm:justify-between">
              {onDisconnect && (
                <Button variant="destructive" type="button" onClick={handleDisconnect} disabled={form.formState.isSubmitting}>
                  {t("common.disconnect")}
                </Button>
              )}
              <div className="flex gap-2">
                <Button variant="ghost" type="button" onClick={() => onOpenChange(false)}>
                  {t("common.cancel")}
                </Button>
                <Button type="submit" disabled={!form.formState.isValid || form.formState.isSubmitting}>
                  {form.formState.isSubmitting ? t("common.saving") : t("common.save")}
                </Button>
              </div>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
