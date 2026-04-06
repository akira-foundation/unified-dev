import { useEffect } from "react";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";

import type { BranchDto } from "../../types/organization";
import { Button } from "../ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../ui/dialog";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "../ui/form";
import { Input } from "../ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";
import { useI18n } from "../../i18n/i18n";

interface CreateBranchDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  branches: BranchDto[];
  defaultBranch: string;
  onSubmit: (branchName: string, fromSha: string) => Promise<void>;
}

const schema = z.object({
  branchName: z
    .string()
    .trim()
    .min(1)
    .regex(/^[^\s~^:?*\[\\]+$/, "Invalid branch name"),
  fromBranch: z.string().min(1),
});

type FormValues = z.infer<typeof schema>;

export function CreateBranchDialog({
  open,
  onOpenChange,
  branches,
  defaultBranch,
  onSubmit,
}: CreateBranchDialogProps) {
  const { t } = useI18n();

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    mode: "onChange",
    defaultValues: { branchName: "", fromBranch: defaultBranch },
  });

  useEffect(() => {
    if (!open) {
      form.reset({ branchName: "", fromBranch: defaultBranch });
    }
  }, [open, form, defaultBranch]);

  const handleSubmit = form.handleSubmit(async (values) => {
    const from = branches.find((b) => b.name === values.fromBranch);
    if (!from) return;
    try {
      await onSubmit(values.branchName.trim(), from.sha);
      onOpenChange(false);
    } catch (error) {
      form.setError("root", {
        message: error instanceof Error ? error.message : "Failed to create branch",
      });
    }
  });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("pages.repositoryBranches.dialog.title")}</DialogTitle>
          <DialogDescription>
            {t("pages.repositoryBranches.dialog.description")}
          </DialogDescription>
        </DialogHeader>
        <Form {...form}>
          <form className="mt-2 flex flex-col gap-4" onSubmit={handleSubmit}>
            <FormField
              control={form.control}
              name="fromBranch"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>{t("pages.repositoryBranches.dialog.fromLabel")}</FormLabel>
                  <FormControl>
                    <Select value={field.value} onValueChange={field.onChange}>
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {branches.map((b) => (
                          <SelectItem key={b.name} value={b.name}>
                            {b.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="branchName"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>{t("pages.repositoryBranches.dialog.nameLabel")}</FormLabel>
                  <FormControl>
                    <Input
                      placeholder={t("pages.repositoryBranches.dialog.namePlaceholder")}
                      {...field}
                    />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            {form.formState.errors.root?.message && (
              <p className="text-sm text-destructive">{form.formState.errors.root.message}</p>
            )}
            <DialogFooter>
              <Button variant="ghost" type="button" onClick={() => onOpenChange(false)}>
                {t("common.cancel")}
              </Button>
              <Button
                type="submit"
                disabled={!form.formState.isValid || form.formState.isSubmitting}
              >
                {form.formState.isSubmitting
                  ? t("pages.repositoryBranches.dialog.creating")
                  : t("pages.repositoryBranches.dialog.create")}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
