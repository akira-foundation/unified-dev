import { useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useQueryClient } from "@tanstack/react-query";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  Combobox,
  ComboboxContent,
  ComboboxEmpty,
  ComboboxInput,
  ComboboxItem,
  ComboboxList,
} from "@/components/ui/combobox";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { useI18n } from "@/i18n/i18n";
import { queryKeys } from "@/lib/query-keys";
import { useMutationWithToast } from "@/hooks/use-mutation-with-toast";
import type { IssueDto } from "@/types/issue";
import type { OrganizationRepoWithOrg } from "@/types/organization";

interface CreateIssueDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  repos: OrganizationRepoWithOrg[];
  orgId?: string;
  repoName?: string;
}

const schema = z.object({
  repoName: z.string().min(1, "Repository is required"),
  title: z.string().trim().min(1, "Title is required"),
  body: z.string().optional(),
  labelsRaw: z.string().optional(),
});

type FormValues = z.infer<typeof schema>;

export function CreateIssueDialog({
  open,
  onOpenChange,
  repos,
  orgId,
  repoName,
}: CreateIssueDialogProps) {
  const { t } = useI18n();
  const queryClient = useQueryClient();

  const defaultRepoName =
    orgId && repoName ? repoName : repos.length > 0 ? repos[0].repo_name : "";

  const form = useForm<FormValues>({
    // @ts-expect-error - version mismatch between zod and hook-form resolver
    resolver: zodResolver(schema),
    mode: "onChange",
    defaultValues: { repoName: defaultRepoName, title: "", body: "", labelsRaw: "" },
  });

  useEffect(() => {
    if (!open) {
      form.reset({
        repoName: orgId && repoName ? repoName : repos.length > 0 ? repos[0].repo_name : "",
        title: "",
        body: "",
        labelsRaw: "",
      });
    }
  }, [open, form, orgId, repoName, repos]);

  const createMutation = useMutationWithToast<IssueDto, FormValues>({
    mutationFn: (values) => {
      const repo = repos.find((r) => r.repo_name === values.repoName);
      const labels = (values.labelsRaw ?? "")
        .split(",")
        .map((l) => l.trim())
        .filter(Boolean);
      return invoke<IssueDto>("create_issue", {
        input: {
          org_id: repo?.organization_id ?? orgId ?? "",
          repo_name: values.repoName,
          title: values.title,
          body: values.body || null,
          labels,
          assignees: [],
        },
      });
    },
    loadingMessage: t("issues.create.toast.creating"),
    successMessage: t("issues.create.toast.created"),
    onSuccess: (_, values) => {
      const repo = repos.find((r) => r.repo_name === values.repoName);
      if (repo) {
        queryClient.invalidateQueries({ queryKey: queryKeys.issues(repo.organization_id, repo.repo_name) });
      }
      onOpenChange(false);
    },
    onError: (err) => {
      form.setError("root", {
        message: err instanceof Error ? err.message : String(err),
      });
    },
  });

  const handleSubmit = form.handleSubmit((values) => {
    createMutation.mutate(values);
  });

  const repoNames = repos.map((r) => r.repo_name);

  return (
    <Dialog open={open} onOpenChange={onOpenChange} modal={false}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("issues.create.title")}</DialogTitle>
          <DialogDescription>{t("issues.create.titleLabel")}</DialogDescription>
        </DialogHeader>

        <Form {...form}>
          <form className="mt-4 flex flex-col gap-4" onSubmit={handleSubmit}>
            <FormField
              control={form.control}
              name="repoName"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>{t("issues.create.repoLabel")}</FormLabel>
                  <Combobox
                    items={repoNames}
                    value={field.value}
                    onValueChange={(v) => field.onChange(v ?? "")}
                  >
                    <ComboboxInput placeholder={t("issues.create.repoPlaceholder")} className="w-full" />
                    <ComboboxContent>
                      <ComboboxEmpty>{t("issues.create.repoPlaceholder")}</ComboboxEmpty>
                      <ComboboxList>
                        {(item: string) => (
                          <ComboboxItem key={item} value={item}>
                            {item}
                          </ComboboxItem>
                        )}
                      </ComboboxList>
                    </ComboboxContent>
                  </Combobox>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="title"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>{t("issues.create.titleLabel")}</FormLabel>
                  <FormControl>
                    <Input placeholder={t("issues.create.titlePlaceholder")} {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="body"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>{t("issues.create.bodyLabel")}</FormLabel>
                  <FormControl>
                    <Textarea
                      placeholder={t("issues.create.bodyPlaceholder")}
                      rows={4}
                      className="resize-y"
                      {...field}
                    />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="labelsRaw"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>{t("issues.create.labelsLabel")}</FormLabel>
                  <FormControl>
                    <Input placeholder={t("issues.create.labelsPlaceholder")} {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            {form.formState.errors.root?.message && (
              <p className="rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">
                {form.formState.errors.root.message}
              </p>
            )}

            <DialogFooter>
              <Button variant="ghost" type="button" onClick={() => onOpenChange(false)}>
                {t("common.cancel")}
              </Button>
              <Button
                type="submit"
                disabled={!form.formState.isValid || createMutation.isPending}
              >
                {createMutation.isPending ? t("issues.create.submitting") : t("issues.create.submit")}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
