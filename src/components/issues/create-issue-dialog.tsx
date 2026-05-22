import { useEffect, useMemo, useState } from "react";
import { z } from "zod";
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { EditorContent } from "@tiptap/react";
import { useToggle } from "@uidotdev/usehooks";

import { Dialog, DialogContent } from "@/components/ui/dialog";
import { Form } from "@/components/ui/form";
import { useI18n } from "@/i18n/i18n";
import { useIssueComposerEditor } from "@/hooks/useIssueComposerEditor";
import { useCreateIssueMutation, type CreateIssueValues } from "@/hooks/useCreateIssueMutation";
import { CreateIssueHeader } from "@/components/issues/create-issue-header";
import { CreateIssueFooter } from "@/components/issues/create-issue-footer";
import type { IssueDto } from "@/types/issue";
import type { OrganizationRepoWithOrg } from "@/types/organization";

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

const EDITOR_CLASS =
  "issue-editor [&_.ProseMirror]:min-h-[280px] [&_.ProseMirror]:max-w-none [&_.ProseMirror]:outline-none [&_.ProseMirror_h1]:mt-8 [&_.ProseMirror_h1]:mb-2 [&_.ProseMirror_h1]:text-[2rem] [&_.ProseMirror_h1]:font-[650] [&_.ProseMirror_h1]:tracking-[-0.03em] [&_.ProseMirror_h1]:text-foreground [&_.ProseMirror_h2]:mt-7 [&_.ProseMirror_h2]:mb-2 [&_.ProseMirror_h2]:text-[1.5rem] [&_.ProseMirror_h2]:font-[620] [&_.ProseMirror_h2]:tracking-[-0.025em] [&_.ProseMirror_h2]:text-foreground [&_.ProseMirror_h3]:mt-6 [&_.ProseMirror_h3]:mb-2 [&_.ProseMirror_h3]:text-[1.125rem] [&_.ProseMirror_h3]:font-[620] [&_.ProseMirror_h3]:tracking-[-0.02em] [&_.ProseMirror_h3]:text-foreground [&_.ProseMirror_p]:my-0 [&_.ProseMirror_p]:leading-7 [&_.ProseMirror_ul]:my-2 [&_.ProseMirror_ul]:list-disc [&_.ProseMirror_ul]:pl-6 [&_.ProseMirror_ol]:my-2 [&_.ProseMirror_ol]:list-decimal [&_.ProseMirror_ol]:pl-6 [&_.ProseMirror_li]:my-1 [&_.ProseMirror_p.is-editor-empty:first-child::before]:pointer-events-none [&_.ProseMirror_p.is-editor-empty:first-child::before]:float-left [&_.ProseMirror_p.is-editor-empty:first-child::before]:h-0 [&_.ProseMirror_p.is-editor-empty:first-child::before]:text-[15px] [&_.ProseMirror_p.is-editor-empty:first-child::before]:leading-7 [&_.ProseMirror_p.is-editor-empty:first-child::before]:text-muted-foreground/35 [&_.ProseMirror_p.is-editor-empty:first-child::before]:content-[attr(data-placeholder)]";

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
  const [repoOpen, setRepoOpen] = useState(false);
  const [labelsOpen, setLabelsOpen] = useState(false);
  const [assigneesOpen, setAssigneesOpen] = useState(false);
  const [expanded, toggleExpanded] = useToggle(false);
  const [syncWithProvider, setSyncWithProvider] = useState(true);
  const [createMore, setCreateMore] = useState(false);
  const [assignToMyself, setAssignToMyself] = useState(assignToSelfByDefault);

  const defaultRepoName = orgId && repoName ? repoName : repos.length > 0 ? repos[0].repo_name : "";

  const form = useForm<CreateIssueValues>({
    resolver: zodResolver(schema),
    mode: "onChange",
    defaultValues: { repoName: defaultRepoName, title: "", body: "", labels: [], assignees: [] },
  });

  useEffect(() => {
    if (!open) {
      setSyncWithProvider(true);
      setCreateMore(false);
      setAssignToMyself(assignToSelfByDefault);
      form.reset({ repoName: defaultRepoName, title: "", body: "", labels: [], assignees: [] });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, assignToSelfByDefault, defaultRepoName]);

  const availableLabels = useMemo<Array<{ name: string; color: string }>>(() => {
    const map = new Map<string, string>();
    for (const issue of issues) {
      issue.labels.forEach((name, i) => {
        if (!map.has(name)) map.set(name, issue.labelColors[i] ?? "888888");
      });
    }
    return Array.from(map.entries()).map(([name, color]) => ({ name, color }));
  }, [issues]);

  const availableAssignees = useMemo<string[]>(() => {
    const set = new Set<string>();
    for (const issue of issues) for (const a of issue.assignees) set.add(a);
    return Array.from(set).sort();
  }, [issues]);

  const editor = useIssueComposerEditor({
    placeholder: t("issues.create.bodyPlaceholderWithCommands"),
    open,
    recreateKey: createMore,
    onChange: (md) => form.setValue("body", md, { shouldValidate: false }),
  });

  const createMutation = useCreateIssueMutation({
    form,
    repos,
    orgId,
    currentUserLoginByOrg,
    syncWithProvider,
    assignToMyself,
    createMore,
    editor,
    onCreated,
    onOpenChange,
  });

  const handleSubmit = form.handleSubmit((values) => createMutation.mutate(values));

  const repoNames = repos.map((r) => r.repo_name);
  const syncLabel = providerName
    ? t("issues.create.syncWithNamedProvider").replace("{provider}", providerName)
    : t("issues.create.syncWithProvider");
  const watchedLabels = form.watch("labels") ?? [];
  const watchedAssignees = form.watch("assignees") ?? [];
  const selectedRepo = repos.find((repo) => repo.repo_name === form.watch("repoName"));
  const currentUserLogin = selectedRepo?.organization_id ? currentUserLoginByOrg[selectedRepo.organization_id] ?? null : null;

  const toggleValue = (field: "labels" | "assignees", name: string) => {
    const current = form.getValues(field) ?? [];
    form.setValue(field, current.includes(name) ? current.filter((v) => v !== name) : [...current, name]);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange} modal={false}>
      {open && <div className="fixed inset-0 z-[55] bg-black/60" onClick={() => onOpenChange(false)} />}
      <DialogContent
        variant="bare"
        className={
          expanded
            ? "z-[60] p-0 gap-0 overflow-hidden sm:max-w-none w-[calc(100vw-2rem)] h-[calc(100vh-2rem)] max-h-[calc(100vh-2rem)] flex flex-col shadow-2xl"
            : "z-[60] p-0 gap-0 overflow-hidden sm:max-w-none w-[720px] max-w-[calc(100vw-2rem)] max-h-[calc(100vh-2rem)] flex flex-col shadow-2xl"
        }
        showCloseButton={false}
      >
        <Form {...form}>
          <form onSubmit={handleSubmit} className="flex h-full min-h-0 flex-col">
            <CreateIssueHeader
              form={form}
              repoNames={repoNames}
              repoOpen={repoOpen}
              setRepoOpen={setRepoOpen}
              expanded={expanded}
              onToggleExpand={() => toggleExpanded()}
              onClose={() => onOpenChange(false)}
            />

            <div className="min-h-0 flex-1 overflow-y-auto">
              <div
                className="w-full px-5 pt-2 pb-6 font-sans text-[15px] leading-7 text-foreground/85"
                onClick={() => editor?.commands.focus()}
              >
                <EditorContent editor={editor} className={EDITOR_CLASS} />
              </div>
              {form.formState.errors.root?.message && (
                <p className="mx-5 mb-3 rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">
                  {form.formState.errors.root.message}
                </p>
              )}
            </div>

            <CreateIssueFooter
              availableLabels={availableLabels}
              availableAssignees={availableAssignees}
              watchedLabels={watchedLabels}
              watchedAssignees={watchedAssignees}
              labelsOpen={labelsOpen}
              setLabelsOpen={setLabelsOpen}
              assigneesOpen={assigneesOpen}
              setAssigneesOpen={setAssigneesOpen}
              toggleLabel={(name) => toggleValue("labels", name)}
              toggleAssignee={(name) => toggleValue("assignees", name)}
              syncWithProvider={syncWithProvider}
              setSyncWithProvider={setSyncWithProvider}
              syncLabel={syncLabel}
              currentUserLogin={currentUserLogin}
              assignToMyself={assignToMyself}
              setAssignToMyself={setAssignToMyself}
              createMore={createMore}
              setCreateMore={setCreateMore}
              submitting={createMutation.isPending}
              canSubmit={form.formState.isValid}
            />
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
