import { useEffect, useState, useMemo } from "react";
import { invoke } from "@tauri-apps/api/core";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useQueryClient } from "@tanstack/react-query";
import { ChevronDown, Tag, UserCircle2, X, Check, Maximize2, Minimize2, MoreHorizontal, Paperclip } from "lucide-react";
import { useEditor, EditorContent, ReactRenderer } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import Placeholder from "@tiptap/extension-placeholder";
import TaskList from "@tiptap/extension-task-list";
import TaskItem from "@tiptap/extension-task-item";
import { Markdown } from "tiptap-markdown";
import tippy, { type Instance as TippyInstance } from "tippy.js";
import { SlashCommandExtension, SLASH_COMMANDS } from "./slash-command-extension";
import { SlashCommandMenu, type SlashCommandMenuRef } from "./slash-command-menu";
import { useToggle } from "@uidotdev/usehooks";

import {
  Dialog,
  DialogContent,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
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

function matchesIssueScope(issue: IssueDto, scope: string, currentLogin: string | null): boolean {
  switch (scope) {
    case "all":
      return true;
    case "all_open":
      return issue.status === "open";
    case "my_queue":
    default:
      if (issue.status !== "open") return false;
      if (!issue.syncWithProvider) return true;
      if (issue.assignees.length === 0) return true;
      return currentLogin ? issue.assignees.some((assignee) => assignee.toLowerCase() === currentLogin.toLowerCase()) : false;
  }
}

function incrementRepoIssueCount<T extends { organization_id: string; repo_name: string; open_issues_count?: number }>(
  repos: T[] | undefined,
  orgId: string,
  repoName: string,
): T[] | undefined {
  if (!repos) return repos;
  return repos.map((repo) => (
    repo.organization_id === orgId && repo.repo_name === repoName
      ? { ...repo, open_issues_count: (repo.open_issues_count ?? 0) + 1 }
      : repo
  ));
}

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
  providerName?: string;
  currentUserLoginByOrg?: Record<string, string>;
  assignToSelfByDefault?: boolean;
  onCreated?: (issue: IssueDto, repo: OrganizationRepoWithOrg | undefined) => void;
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
  providerName,
  currentUserLoginByOrg = {},
  assignToSelfByDefault = true,
  onCreated,
}: CreateIssueDialogProps) {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const [repoOpen, setRepoOpen] = useState(false);
  const [labelsOpen, setLabelsOpen] = useState(false);
  const [assigneesOpen, setAssigneesOpen] = useState(false);
  const [expanded, toggleExpanded] = useToggle(false);
  const [syncWithProvider, setSyncWithProvider] = useState(true);
  const [createMore, setCreateMore] = useState(false);
  const [assignToMyself, setAssignToMyself] = useState(assignToSelfByDefault);

  const defaultRepoName =
    orgId && repoName ? repoName : repos.length > 0 ? repos[0].repo_name : "";

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    mode: "onChange",
    defaultValues: { repoName: defaultRepoName, title: "", body: "", labels: [], assignees: [] },
  });

  useEffect(() => {
    if (!open) {
      setSyncWithProvider(true);
      setCreateMore(false);
      setAssignToMyself(assignToSelfByDefault);
      form.reset({
        repoName: orgId && repoName ? repoName : repos.length > 0 ? repos[0].repo_name : "",
        title: "",
        body: "",
        labels: [],
        assignees: [],
      });
    }
  }, [open, form, orgId, repoName, repos, assignToSelfByDefault]);

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

  const createMutation = useMutationWithToast<IssueDto, FormValues>({
    mutationFn: (values) => {
      const repo = repos.find((r) =>
        r.repo_name === values.repoName && (orgId ? r.organization_id === orgId : true),
      );
      const currentUserLogin = repo?.organization_id ? currentUserLoginByOrg[repo.organization_id] ?? null : null;
      const assignees = assignToMyself && currentUserLogin
        ? Array.from(new Set([...(values.assignees ?? []), currentUserLogin]))
        : (values.assignees ?? []);
      return invoke<IssueDto>("create_issue", {
        input: {
          org_id: repo?.organization_id ?? orgId ?? "",
          repo_name: values.repoName,
          title: values.title,
          body: values.body || null,
          labels: values.labels ?? [],
          assignees,
          sync_with_provider: syncWithProvider,
        },
      });
    },
    loadingMessage: t("issues.create.toast.creating"),
    successMessage: t("issues.create.toast.created"),
    onSuccess: (createdIssue, values) => {
      const repo = repos.find((r) =>
        r.repo_name === values.repoName && (orgId ? r.organization_id === orgId : true),
      );
      if (repo) {
        const currentLogin = currentUserLoginByOrg[repo.organization_id] ?? null;
        const matches = queryClient.getQueriesData<IssueDto[]>({ queryKey: queryKeys.issues(repo.organization_id, repo.repo_name) });
        matches.forEach(([key, current]) => {
          if (!current) return;
          const scope = typeof key[3] === "string" ? key[3] : "my_queue";
          if (!matchesIssueScope(createdIssue, scope, currentLogin)) {
            return;
          }
          queryClient.setQueryData<IssueDto[]>(
            key,
            [createdIssue, ...current.filter((entry: IssueDto) => entry.id !== createdIssue.id)],
          );
        });
        queryClient.setQueryData<OrganizationRepoWithOrg[]>(queryKeys.selectedRepositories(repo.organization_id), (current) =>
          incrementRepoIssueCount(current, repo.organization_id, repo.repo_name),
        );
        queryClient.setQueryData<OrganizationRepoWithOrg[]>(queryKeys.allRepositories(), (current) =>
          incrementRepoIssueCount(current, repo.organization_id, repo.repo_name),
        );
        queryClient.invalidateQueries({ queryKey: queryKeys.issues(repo.organization_id, repo.repo_name) });
        queryClient.invalidateQueries({ queryKey: queryKeys.selectedRepositories(repo.organization_id) });
        queryClient.invalidateQueries({ queryKey: queryKeys.allRepositories() });
        onCreated?.(createdIssue, repo);
      }
      if (createMore) {
        form.reset({
          repoName: values.repoName,
          title: "",
          body: "",
          labels: [],
          assignees: [],
        });
        editor?.commands.clearContent();
        return;
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

  const bodyPlaceholder = t("issues.create.bodyPlaceholderWithCommands");

  const editor = useEditor({
    extensions: [
      StarterKit,
      Placeholder.configure({ placeholder: bodyPlaceholder }),
      TaskList.configure({
        HTMLAttributes: {
          class: "issue-task-list",
        },
      }),
      TaskItem.configure({
        nested: true,
        HTMLAttributes: {
          class: "issue-task-item",
        },
      }),
      Markdown.configure({ transformPastedText: true }),
      SlashCommandExtension.configure({
        suggestion: {
          items: ({ query }: { query: string }) =>
            SLASH_COMMANDS.filter((item) =>
              item.title.toLowerCase().includes(query.toLowerCase()),
            ),
          render() {
            let renderer: ReactRenderer<any>;
            let popup: TippyInstance | null = null;

            return {
              onStart(props: any) {
                renderer = new ReactRenderer(SlashCommandMenu, {
                  props,
                  editor: props.editor,
                });

                if (!props.clientRect) {
                  return;
                }

                popup = tippy(document.body, {
                  getReferenceClientRect: () => props.clientRect?.() ?? new DOMRect(),
                  appendTo: () => document.body,
                  content: renderer.element,
                  showOnCreate: true,
                  interactive: true,
                  trigger: "manual",
                  placement: "bottom-start",
                  offset: [0, 8],
                  maxWidth: 280,
                });
              },

              onUpdate(props: any) {
                renderer.updateProps(props);

                if (!props.clientRect) {
                  return;
                }

                popup?.setProps({
                  getReferenceClientRect: () => props.clientRect?.() ?? new DOMRect(),
                });
              },

              onKeyDown(props: { event: KeyboardEvent }) {
                if (props.event.key === "Escape") {
                  popup?.hide();
                  return true;
                }

                return ((renderer.ref as SlashCommandMenuRef | null)?.onKeyDown(props.event)) ?? false;
              },

              onExit() {
                popup?.destroy();
                popup = null;
                renderer.destroy();
              },
            };
          },
        },
      }),
    ],
    editorProps: {
      attributes: {
        class: "outline-none",
      },
    },
    onUpdate({ editor: e }) {
      // @ts-expect-error - tiptap-markdown adds getMarkdown to editor storage
      const md: string = e.storage.markdown?.getMarkdown?.() ?? e.getText();
      form.setValue("body", md, { shouldValidate: false });
    },
  }, [createMore]);

  // Reset editor content when dialog closes
  useEffect(() => {
    if (!open && editor) {
      editor.commands.clearContent();
    }
  }, [open, editor]);

  const repoNames = repos.map((r) => r.repo_name);
  const syncLabel = providerName
    ? t("issues.create.syncWithNamedProvider").replace("{provider}", providerName)
    : t("issues.create.syncWithProvider");
  const watchedLabels = form.watch("labels") ?? [];
  const watchedAssignees = form.watch("assignees") ?? [];
  const selectedRepoName = form.watch("repoName");
  const selectedRepo = repos.find((repo) => repo.repo_name === selectedRepoName);
  const currentUserLogin = selectedRepo?.organization_id ? currentUserLoginByOrg[selectedRepo.organization_id] ?? null : null;

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
      {open && (
        <div
          className="fixed inset-0 z-40 bg-black/60"
          onClick={() => onOpenChange(false)}
        />
      )}
      <DialogContent
        className={
          expanded
            ? "p-0 gap-0 overflow-hidden sm:max-w-none w-[calc(100vw-2rem)] h-[calc(100vh-2rem)] max-h-[calc(100vh-2rem)] flex flex-col shadow-2xl"
            : "p-0 gap-0 overflow-hidden sm:max-w-none w-[720px] max-w-[calc(100vw-2rem)] max-h-[calc(100vh-2rem)] flex flex-col shadow-2xl"
        }
        showCloseButton={false}
      >
        <Form {...form}>
          <form onSubmit={handleSubmit} className="flex h-full min-h-0 flex-col">

            <div className="shrink-0 bg-background">
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
                              <span className="flex-1 truncate text-left">{name}</span>
                              {field.value === name && <Check className="size-3.5 shrink-0 text-muted-foreground" />}
                            </button>
                          ))}
                        </div>
                      </PopoverContent>
                    </Popover>
                  )}
                />
                <span className="text-muted-foreground/40">›</span>
                <span>{t("issues.create.title")}</span>
                <div className="ml-auto flex items-center gap-2">
                  <button
                    type="button"
                    className="rounded-full bg-muted px-3 py-1 text-[11px] font-medium text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
                  >
                    {t("issues.create.saveDraft")}
                  </button>
                  <button
                    type="button"
                    onClick={() => toggleExpanded()}
                    className="flex size-5 items-center justify-center rounded-sm text-muted-foreground hover:bg-accent hover:text-foreground transition-colors"
                  >
                    {expanded ? <Minimize2 className="size-3.5" /> : <Maximize2 className="size-3.5" />}
                  </button>
                  <button
                    type="button"
                    onClick={() => onOpenChange(false)}
                    className="flex size-5 items-center justify-center rounded-sm text-muted-foreground hover:bg-accent hover:text-foreground transition-colors"
                  >
                    <X className="size-3.5" />
                  </button>
                </div>
              </div>

              <FormField
                control={form.control}
                name="title"
                render={({ field }) => (
                  <input
                    {...field}
                    autoFocus
                    placeholder={t("issues.create.titlePlaceholder")}
                    className="block h-[52px] w-full bg-transparent px-5 py-2 font-sans text-[2rem] leading-[1.05] font-[620] tracking-[-0.03em] text-foreground placeholder:text-muted-foreground/30 focus:outline-none"
                  />
                )}
              />
            </div>

            <div className="min-h-0 flex-1 overflow-y-auto">
              <FormField
                control={form.control}
                name="body"
                render={() => (
                  <div
                    className="w-full px-5 pt-2 pb-6 font-sans text-[15px] leading-7 text-foreground/85"
                    onClick={() => editor?.commands.focus()}
                  >
                    <EditorContent
                      editor={editor}
                      className="issue-editor [&_.ProseMirror]:min-h-[280px] [&_.ProseMirror]:max-w-none [&_.ProseMirror]:outline-none [&_.ProseMirror_h1]:mt-8 [&_.ProseMirror_h1]:mb-2 [&_.ProseMirror_h1]:text-[2rem] [&_.ProseMirror_h1]:font-[650] [&_.ProseMirror_h1]:tracking-[-0.03em] [&_.ProseMirror_h1]:text-foreground [&_.ProseMirror_h2]:mt-7 [&_.ProseMirror_h2]:mb-2 [&_.ProseMirror_h2]:text-[1.5rem] [&_.ProseMirror_h2]:font-[620] [&_.ProseMirror_h2]:tracking-[-0.025em] [&_.ProseMirror_h2]:text-foreground [&_.ProseMirror_h3]:mt-6 [&_.ProseMirror_h3]:mb-2 [&_.ProseMirror_h3]:text-[1.125rem] [&_.ProseMirror_h3]:font-[620] [&_.ProseMirror_h3]:tracking-[-0.02em] [&_.ProseMirror_h3]:text-foreground [&_.ProseMirror_p]:my-0 [&_.ProseMirror_p]:leading-7 [&_.ProseMirror_ul]:my-2 [&_.ProseMirror_ul]:list-disc [&_.ProseMirror_ul]:pl-6 [&_.ProseMirror_ol]:my-2 [&_.ProseMirror_ol]:list-decimal [&_.ProseMirror_ol]:pl-6 [&_.ProseMirror_li]:my-1 [&_.ProseMirror_p.is-editor-empty:first-child::before]:pointer-events-none [&_.ProseMirror_p.is-editor-empty:first-child::before]:float-left [&_.ProseMirror_p.is-editor-empty:first-child::before]:h-0 [&_.ProseMirror_p.is-editor-empty:first-child::before]:text-[15px] [&_.ProseMirror_p.is-editor-empty:first-child::before]:leading-7 [&_.ProseMirror_p.is-editor-empty:first-child::before]:text-muted-foreground/35 [&_.ProseMirror_p.is-editor-empty:first-child::before]:content-[attr(data-placeholder)]"
                    />
                  </div>
                )}
              />

              {form.formState.errors.root?.message && (
                <p className="mx-5 mb-3 rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">
                  {form.formState.errors.root.message}
                </p>
              )}
            </div>

            <div className="shrink-0 border-t border-border bg-background">
              <div className="flex items-center gap-1 px-3 py-2">

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
                      : t("issues.create.assigneesLabel")}
                  </button>
                </PopoverTrigger>
                <PopoverContent className="w-56 p-0" align="start" side="top">
                  <div className="px-3 py-2 border-b border-border">
                    <p className="text-xs font-medium text-muted-foreground">
                      {t("issues.create.assigneesLabel")}
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

              <button
                type="button"
                className="flex items-center gap-1.5 rounded-md px-2 py-1 text-xs text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
              >
                <MoreHorizontal className="size-3.5 shrink-0" />
              </button>

              </div>

              <div className="flex items-center justify-between px-3 pb-3 pt-1">
                <button
                  type="button"
                  className="flex size-8 items-center justify-center rounded-full bg-muted text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
                >
                  <Paperclip className="size-4" />
                </button>

                <div className="ml-auto flex items-center gap-2.5">
                  <label className="flex items-center gap-1.5 text-xs text-muted-foreground">
                    <Switch checked={syncWithProvider} onCheckedChange={setSyncWithProvider} />
                    <span>{syncLabel}</span>
                  </label>
                  {currentUserLogin ? (
                    <label className="flex items-center gap-1.5 text-xs text-muted-foreground">
                      <Switch checked={assignToMyself} onCheckedChange={setAssignToMyself} />
                      <span>{t("issues.create.assignToMyselfLabel").replace("{login}", currentUserLogin)}</span>
                    </label>
                  ) : null}
                  <label className="flex items-center gap-1.5 text-xs text-muted-foreground">
                    <Switch checked={createMore} onCheckedChange={setCreateMore} />
                    <span>{t("issues.create.createMore")}</span>
                  </label>
                  <Button
                    type="submit"
                    size="sm"
                    disabled={!form.formState.isValid || createMutation.isPending}
                  >
                    {createMutation.isPending ? t("issues.create.submitting") : t("issues.create.submit")}
                  </Button>
                </div>
              </div>
            </div>

          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
