import { useState, useEffect, useActionState } from "react";
import { FileText } from "lucide-react";
import { useI18n } from "@/i18n/i18n";
import { useSettingsStore } from "@/stores/settings-store";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { SettingsSection } from "./settings-section";

type PromptAction = "merge_local" | "merge_push" | "draft_pr" | "create_pr";

const PROMPT_ITEMS: { action: PromptAction; labelKey: string; descKey: string }[] = [
  { action: "merge_local", labelKey: "settings.prompts.mergeLocal.label", descKey: "settings.prompts.mergeLocal.description" },
  { action: "merge_push",  labelKey: "settings.prompts.mergePush.label",  descKey: "settings.prompts.mergePush.description" },
  { action: "draft_pr",    labelKey: "settings.prompts.draftPr.label",    descKey: "settings.prompts.draftPr.description" },
  { action: "create_pr",   labelKey: "settings.prompts.createPr.label",   descKey: "settings.prompts.createPr.description" },
];

const PROMPT_PLACEHOLDERS: Record<PromptAction, string> = {
  merge_local: "Commits any uncommitted changes and merges the branch into the base branch locally.",
  merge_push:  "Commits any uncommitted changes, merges the branch locally, and pushes to the remote.",
  draft_pr:    "Commits any uncommitted changes, pushes the branch, and opens a draft pull request on GitHub.",
  create_pr:   "Commits any uncommitted changes, pushes the branch, and opens a pull request on GitHub.",
};

interface PromptRowProps {
  action: PromptAction;
  labelKey: string;
  descKey: string;
  storedValue: string;
  isCustomized: boolean;
}

function PromptRow({ action, labelKey, descKey, storedValue, isCustomized }: PromptRowProps) {
  const { t } = useI18n();
  const { savePrompt, resetPrompt } = useSettingsStore();
  const [draft, setDraft] = useState(storedValue);

  useEffect(() => {
    setDraft(storedValue);
  }, [storedValue]);

  const isDirty = draft !== storedValue;

  const [, dispatchSave, isSavePending] = useActionState(
    async (_prev: null, value: string) => {
      if (value.trim() === "") {
        await resetPrompt(action);
      } else {
        await savePrompt(action, value);
      }
      return null;
    },
    null,
  );

  const [, dispatchReset, isResetPending] = useActionState(
    async (_prev: null) => {
      await resetPrompt(action);
      setDraft("");
      return null;
    },
    null,
  );

  const isBusy = isSavePending || isResetPending;

  return (
    <div className="flex flex-col gap-3 px-4 py-6 border-b border-zinc-100 dark:border-zinc-800/50 last:border-0">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <p className="text-sm font-medium text-zinc-900 dark:text-white">{t(labelKey)}</p>
          <span className={cn(
            "text-[9px] font-bold uppercase tracking-wider px-1.5 py-0.5 rounded",
            isCustomized
              ? "bg-purple-500/10 text-purple-400 border border-purple-500/20"
              : "bg-zinc-100 dark:bg-zinc-800 text-zinc-400 border border-zinc-200 dark:border-zinc-700"
          )}>
            {isCustomized ? t("settings.prompts.badge.custom") : t("settings.prompts.badge.default")}
          </span>
        </div>
        <div className="flex items-center gap-2">
          {isCustomized && !isDirty && (
            <Button
              variant="ghost"
              size="sm"
              disabled={isBusy}
              onClick={() => dispatchReset()}
              className="h-7 px-2.5 text-[11px] text-zinc-400 hover:text-white"
            >
              {t("settings.prompts.resetToDefault")}
            </Button>
          )}
          {isDirty && (
            <Button
              size="sm"
              disabled={isBusy}
              onClick={() => dispatchSave(draft)}
              className="h-7 px-3 text-[11px] bg-purple-600 hover:bg-purple-700 text-white"
            >
              {isSavePending ? t("common.saving") : t("common.save")}
            </Button>
          )}
        </div>
      </div>
      <textarea
        className="w-full h-36 bg-zinc-50 dark:bg-black/20 border border-zinc-200 dark:border-white/5 rounded-md text-zinc-600 dark:text-zinc-400 font-mono text-[13px] p-4 focus:outline-none focus:border-purple-500 transition-colors custom-scrollbar resize-none placeholder:text-zinc-400 dark:placeholder:text-zinc-600 placeholder:font-sans placeholder:not-italic"
        placeholder={PROMPT_PLACEHOLDERS[action]}
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
      />
      <p className="text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed">{t(descKey)}</p>
    </div>
  );
}

export function PromptsTab() {
  const { t } = useI18n();
  const { promptOverrides, loadPrompts } = useSettingsStore();

  useEffect(() => {
    void loadPrompts();
  }, [loadPrompts]);

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection
        title={t("settings.prompts.title")}
        description={t("settings.prompts.description")}
        icon={FileText}
      >
        {PROMPT_ITEMS.map(({ action, labelKey, descKey }) => {
          const isCustomized = action in promptOverrides;
          const storedValue = isCustomized ? promptOverrides[action] : "";
          return (
            <PromptRow
              key={action}
              action={action}
              labelKey={labelKey}
              descKey={descKey}
              storedValue={storedValue}
              isCustomized={isCustomized}
            />
          );
        })}
      </SettingsSection>
    </div>
  );
}
