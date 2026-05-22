import { Check, MoreHorizontal, Paperclip, Tag, UserCircle2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { useI18n } from "@/i18n/i18n";

interface LabelInfo {
  name: string;
  color: string;
}

interface CreateIssueFooterProps {
  availableLabels: LabelInfo[];
  availableAssignees: string[];
  watchedLabels: string[];
  watchedAssignees: string[];
  labelsOpen: boolean;
  setLabelsOpen: (open: boolean) => void;
  assigneesOpen: boolean;
  setAssigneesOpen: (open: boolean) => void;
  toggleLabel: (name: string) => void;
  toggleAssignee: (name: string) => void;
  syncWithProvider: boolean;
  setSyncWithProvider: (value: boolean) => void;
  syncLabel: string;
  currentUserLogin: string | null;
  assignToMyself: boolean;
  setAssignToMyself: (value: boolean) => void;
  createMore: boolean;
  setCreateMore: (value: boolean) => void;
  submitting: boolean;
  canSubmit: boolean;
}

export function CreateIssueFooter({
  availableLabels,
  availableAssignees,
  watchedLabels,
  watchedAssignees,
  labelsOpen,
  setLabelsOpen,
  assigneesOpen,
  setAssigneesOpen,
  toggleLabel,
  toggleAssignee,
  syncWithProvider,
  setSyncWithProvider,
  syncLabel,
  currentUserLogin,
  assignToMyself,
  setAssignToMyself,
  createMore,
  setCreateMore,
  submitting,
  canSubmit,
}: CreateIssueFooterProps) {
  const { t } = useI18n();

  return (
    <div className="shrink-0 border-t border-border bg-background">
      <div className="flex items-center gap-1 px-3 py-2">
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
              <div className="px-3 py-6 text-center text-xs text-muted-foreground">{t("issues.create.noLabels")}</div>
            ) : (
              <div className="max-h-64 overflow-y-auto py-1">
                {availableLabels.map((label) => (
                  <button
                    key={label.name}
                    type="button"
                    onClick={() => toggleLabel(label.name)}
                    className="flex w-full items-center gap-2.5 px-3 py-1.5 text-sm hover:bg-accent transition-colors"
                  >
                    <span className="inline-block size-2.5 rounded-full shrink-0" style={{ backgroundColor: `#${label.color}` }} />
                    <span className="flex-1 text-left">{label.name}</span>
                    {watchedLabels.includes(label.name) && <Check className="size-3.5 text-muted-foreground" />}
                  </button>
                ))}
              </div>
            )}
          </PopoverContent>
        </Popover>

        <Popover open={assigneesOpen} onOpenChange={setAssigneesOpen}>
          <PopoverTrigger asChild>
            <button
              type="button"
              className="flex items-center gap-1.5 rounded-md px-2 py-1 text-xs text-muted-foreground hover:bg-accent hover:text-foreground transition-colors"
            >
              <UserCircle2 className="size-3.5 shrink-0" />
              {watchedAssignees.length > 0 ? watchedAssignees.join(", ") : t("issues.create.assigneesLabel")}
            </button>
          </PopoverTrigger>
          <PopoverContent className="w-56 p-0" align="start" side="top">
            <div className="px-3 py-2 border-b border-border">
              <p className="text-xs font-medium text-muted-foreground">{t("issues.create.assigneesLabel")}</p>
            </div>
            {availableAssignees.length === 0 ? (
              <div className="px-3 py-6 text-center text-xs text-muted-foreground">{t("issues.create.noAssignees")}</div>
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
          <Button type="submit" size="sm" disabled={!canSubmit || submitting}>
            {submitting ? t("issues.create.submitting") : t("issues.create.submit")}
          </Button>
        </div>
      </div>
    </div>
  );
}
