import { useEffect, useRef, useState, useMemo } from "react";
import { invoke } from "@tauri-apps/api/core";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useQueryClient } from "@tanstack/react-query";
import { ChevronDown, Tag, UserCircle2, X, Check, Maximize2, Minimize2 } from "lucide-react";

import {
  Dialog,
  DialogContent,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import {
  Form,
  FormField,
} from "@/components/ui/form";
import { useI18n } from "@/i18n/i18n";
import { queryKeys } from "@/lib/query-keys";
import { useMutationWithToast } from "@/hooks/use-mutation-with-toast";
import type { IssueDto } from "@/types/issue";
import type { OrganizationRepoWithOrg } from "@/types/organization";

interface LabelInfo {
  name: string;
  color: string;
}

interface CreateIssueDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  repos: OrganizationRepoWithOrg[];
  issues?: IssueDto[];
  orgId?: string;
  repoName?: string;
}

const schema = z.object({
  repoName: z.string().min(1, "Repository is required"),
  title: z.string().trim().min(1, "Title is required"),
  body: z.string().optional(),
  labels: z.array(z.string()).optional(),
  assignees: z.array(z.string()).optional(),
});

type FormValues = z.infer<typeof schema>;

export function CreateIssueDialog({
  open,
  onOpenChange,
  repos,
  issues = [],
  orgId,
  repoName,
}: CreateIssueDialogProps) {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const [repoOpen, setRepoOpen] = useState(false);
  const [labelsOpen, setLabelsOpen] = useState(false);
  const [assigneesOpen, setAssigneesOpen] = useState(false);
  const [expanded, setExpanded] = useState(false);

  const defaultRepoName =
    orgId && repoName ? repoName : repos.length > 0 ? repos[0].repo_name : "";

  const form = useForm<FormValues>({
    // @ts-expect-error - version mismatch between zod and hook-form resolver
    resolver: zodResolver(schema),
    mode: "onChange",
    defaultValues: { repoName: defaultRepoName, title: "", body: "", labels: [], assignees: [] },
  });

  useEffect(() => {
    if (!open) {
      form.reset({
        repoName: orgId && repoName ? repoName : repos.length > 0 ? repos[0].repo_name : "",
        title: "",
        body: "",
        labels: [],
        assignees: [],
      });
    }
  }, [open, form, orgId, repoName, repos]);

  // Derive available labels with colors from loaded issues
  const availableLabels = useMemo<LabelInfo[]>(() => {
    const map = new Map<string, string>();
    for (const issue of issues) {
      issue.labels.forEach((name, i) => {
        if (!map.has(name)) {
          map.set(name, issue.labelColors[i] ?? "888888");
        }
      });
    }
    return Array.from(map.entries()).map(([name, color]) => ({ name, color }));
  }, [issues]);

  // Derive available assignees from loaded issues
  const availableAssignees = useMemo<string[]>(() => {
    const set = new Set<string>();
    for (const issue of issues) {
      for (const a of issue.assignees) set.add(a);
    }
    return Array.from(set).sort();
  }, [issues]);

  const autoGrow = (el: HTMLTextAreaElement) => {
    el.style.height = "auto";
    el.style.height = `${el.scrollHeight}px`;
  };

  const createMutation = useMutationWithToast<IssueDto, FormValues>({
    mutationFn: (values) => {
      const repo = repos.find((r) => r.repo_name === values.repoName);
      return invoke<IssueDto>("create_issue", {
        input: {
          org_id: repo?.organization_id ?? orgId ?? "",
          repo_name: values.repoName,
          title: values.title,
          body: values.body || null,
          labels: values.labels ?? [],
          assignees: values.assignees ?? [],
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
  const watchedLabels = form.watch("labels") ?? [];
  const watchedAssignees = form.watch("assignees") ?? [];

  const toggleLabel = (name: string) => {
    const current = form.getValues("labels") ?? [];
    form.setValue("labels", current.includes(name)
      ? current.filter((l) => l !== name)
      : [...current, name]
    );
  };

  const toggleAssignee = (name: string) => {
    const current = form.getValues("assignees") ?? [];
    form.setValue("assignees", current.includes(name)
      ? current.filter((a) => a !== name)
      : [...current, name]
    );
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange} modal={false}>
      <DialogContent
        className={
          expanded
            ? "p-0 gap-0 overflow-visible sm:max-w-none w-[calc(100vw-2rem)] h-[calc(100vh-2rem)] flex flex-col"
            : "p-0 gap-0 overflow-visible sm:max-w-none w-[720px] max-w-[calc(100vw-2rem)]"
        }
        showCloseButton={false}
      >
        <Form {...form}>
          <form onSubmit={handleSubmit} className="flex flex-col h-full">

            {/* Header breadcrumb — repo picker lives here */}
            <div className="flex items-center gap-1 px-5 pt-4 pb-1 text-xs text-muted-foreground select-none">
              <FormField
                control={form.control}
                name="repoName"
                render={({ field }) => (
                  <Popover open={repoOpen} onOpenChange={setRepoOpen}>
                    <PopoverTrigger asChild>
                      <button
                        type="button"
                        className="flex items-center gap-1 rounded px-1 py-0.5 font-medium text-muted-foreground hover:bg-accent hover:text-foreground transition-colors"
                      >
                        {field.value || t("issues.create.repoPlaceholder")}
                        <ChevronDown className="size-3 opacity-50" />
                      </button>
                    </PopoverTrigger>
                    <PopoverContent className="w-56 p-1" align="start" side="bottom">
                      <div className="max-h-64 overflow-y-auto">
                        {repoNames.map((name) => (
                          <button
                            key={name}
                            type="button"
                            onClick={() => { field.onChange(name); setRepoOpen(false); }}
                            className="flex w-full items-center gap-2 rounded-sm px-2 py-1.5 text-sm hover:bg-accent transition-colors"
                          >
                            <span className="flex-1 text-left truncate">{name}</span>
                            {field.value === name && <Check className="size-3.5 text-muted-foreground shrink-0" />}
                          </button>
                        ))}
                      </div>
                    </PopoverContent>
                  </Popover>
                )}
              />
              <span className="text-muted-foreground/40">›</span>
              <span>{t("issues.create.title")}</span>
              <div className="ml-auto flex items-center gap-0.5">
                <button
                  type="button"
                  onClick={() => setExpanded((v) => !v)}
                  className="rounded-sm p-0.5 text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
                >
                  {expanded ? <Minimize2 className="size-3.5" /> : <Maximize2 className="size-3.5" />}
                </button>
                <button
                  type="button"
                  onClick={() => onOpenChange(false)}
                  className="rounded-sm p-0.5 text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
                >
                  <X className="size-3.5" />
                </button>
              </div>
            </div>

            {/* Title */}
            <FormField
              control={form.control}
              name="title"
              render={({ field }) => (
                <input
                  {...field}
                  autoFocus
                  placeholder={t("issues.create.titlePlaceholder")}
                  className="w-full bg-transparent px-5 py-3 text-xl font-semibold placeholder:text-muted-foreground/30 focus:outline-none"
                />
              )}
            />

            {/* Description — auto-growing textarea */}
            <FormField
              control={form.control}
              name="body"
              render={({ field }) => (
                <textarea
                  {...field}
                  ref={(el) => {
                    textareaRef.current = el;
                    if (typeof field.ref === "function") field.ref(el);
                  }}
                  placeholder={t("issues.create.bodyPlaceholder")}
                  rows={5}
                  onInput={(e) => { if (!expanded) autoGrow(e.currentTarget); }}
                  className={`w-full resize-none bg-transparent px-5 py-1 pb-6 text-sm text-foreground/80 placeholder:text-muted-foreground/30 focus:outline-none ${expanded ? "flex-1 overflow-y-auto" : "min-h-[160px] overflow-hidden"}`}
                />
              )}
            />

            {form.formState.errors.root?.message && (
              <p className="mx-5 mb-2 rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">
                {form.formState.errors.root.message}
              </p>
            )}

            {/* Footer toolbar */}
            <div className="flex items-center gap-1 border-t border-border px-3 py-2">

              {/* Labels picker */}
              <Popover open={labelsOpen} onOpenChange={setLabelsOpen}>
                <PopoverTrigger asChild>
                  <button
                    type="button"
                    className="flex items-center gap-1.5 rounded-md px-2 py-1 text-xs text-muted-foreground hover:bg-accent hover:text-foreground transition-colors"
                  >
                    {watchedLabels.length > 0 ? (
                      <>
                        {watchedLabels.slice(0, 3).map((name) => {
                          const info = availableLabels.find((l) => l.name === name);
                          return (
                            <span
                              key={name}
                              className="inline-block size-2 rounded-full shrink-0"
                              style={{ backgroundColor: `#${info?.color ?? "888888"}` }}
                            />
                          );
                        })}
                        <span>{watchedLabels.join(", ")}</span>
                      </>
                    ) : (
                      <>
                        <Tag className="size-3.5 shrink-0" />
                        {t("issues.create.labelsLabel")}
                      </>
                    )}
                  </button>
                </PopoverTrigger>
                <PopoverContent className="w-64 p-0" align="start" side="top">
                  <div className="px-3 py-2 border-b border-border">
                    <p className="text-xs font-medium text-muted-foreground">{t("issues.create.labelsLabel")}</p>
                  </div>
                  {availableLabels.length === 0 ? (
                    <div className="px-3 py-6 text-center text-xs text-muted-foreground">
                      No labels found
                    </div>
                  ) : (
                    <div className="max-h-64 overflow-y-auto py-1">
                      {availableLabels.map((label) => (
                        <button
                          key={label.name}
                          type="button"
                          onClick={() => toggleLabel(label.name)}
                          className="flex w-full items-center gap-2.5 px-3 py-1.5 text-sm hover:bg-accent transition-colors"
                        >
                          <span
                            className="inline-block size-2.5 rounded-full shrink-0"
                            style={{ backgroundColor: `#${label.color}` }}
                          />
                          <span className="flex-1 text-left">{label.name}</span>
                          {watchedLabels.includes(label.name) && <Check className="size-3.5 text-muted-foreground" />}
                        </button>
                      ))}
                    </div>
                  )}
                </PopoverContent>
              </Popover>

              {/* Assignees picker */}
              <Popover open={assigneesOpen} onOpenChange={setAssigneesOpen}>
                <PopoverTrigger asChild>
                  <button
                    type="button"
                    className="flex items-center gap-1.5 rounded-md px-2 py-1 text-xs text-muted-foreground hover:bg-accent hover:text-foreground transition-colors"
                  >
                    <UserCircle2 className="size-3.5 shrink-0" />
                    {watchedAssignees.length > 0
                      ? watchedAssignees.join(", ")
                      : t("issues.create.assigneesLabel") || "Assignees"}
                  </button>
                </PopoverTrigger>
                <PopoverContent className="w-56 p-0" align="start" side="top">
                  <div className="px-3 py-2 border-b border-border">
                    <p className="text-xs font-medium text-muted-foreground">
                      {t("issues.create.assigneesLabel") || "Assignees"}
                    </p>
                  </div>
                  {availableAssignees.length === 0 ? (
                    <div className="px-3 py-6 text-center text-xs text-muted-foreground">
                      No assignees found
                    </div>
                  ) : (
                    <div className="max-h-64 overflow-y-auto py-1">
                      {availableAssignees.map((name) => (
                        <button
                          key={name}
                          type="button"
                          onClick={() => toggleAssignee(name)}
                          className="flex w-full items-center gap-2.5 px-3 py-1.5 text-sm hover:bg-accent transition-colors"
                        >
                          <UserCircle2 className="size-3.5 shrink-0 text-muted-foreground" />
                          <span className="flex-1 text-left">@{name}</span>
                          {watchedAssignees.includes(name) && <Check className="size-3.5 text-muted-foreground" />}
                        </button>
                      ))}
                    </div>
                  )}
                </PopoverContent>
              </Popover>

              <div className="ml-auto flex items-center gap-2">
                <Button
                  type="submit"
                  size="sm"
                  disabled={!form.formState.isValid || createMutation.isPending}
                >
                  {createMutation.isPending ? t("issues.create.submitting") : t("issues.create.submit")}
                </Button>
              </div>
            </div>

          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
