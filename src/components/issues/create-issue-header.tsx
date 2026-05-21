import { Check, ChevronDown, Maximize2, Minimize2, X } from "lucide-react";
import type { UseFormReturn } from "react-hook-form";

import { FormField } from "@/components/ui/form";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { useI18n } from "@/i18n/i18n";
import type { CreateIssueValues } from "@/hooks/useCreateIssueMutation";

interface CreateIssueHeaderProps {
  form: UseFormReturn<CreateIssueValues>;
  repoNames: string[];
  repoOpen: boolean;
  setRepoOpen: (open: boolean) => void;
  expanded: boolean;
  onToggleExpand: () => void;
  onClose: () => void;
}

export function CreateIssueHeader({ form, repoNames, repoOpen, setRepoOpen, expanded, onToggleExpand, onClose }: CreateIssueHeaderProps) {
  const { t } = useI18n();

  return (
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
            onClick={onToggleExpand}
            className="flex size-5 items-center justify-center rounded-sm text-muted-foreground hover:bg-accent hover:text-foreground transition-colors"
          >
            {expanded ? <Minimize2 className="size-3.5" /> : <Maximize2 className="size-3.5" />}
          </button>
          <button
            type="button"
            onClick={onClose}
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
  );
}
