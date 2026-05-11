import { useMemo, useState } from "react";
import { Loader2 } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";

export type ThreadSourceKind = "issue" | "pr" | "branch";

export interface ThreadSourcePickerItem {
  id: string;
  title: string;
  subtitle?: string;
  meta?: string;
}

interface ThreadSourcePickerDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  kind: ThreadSourceKind;
  repoName: string;
  items: ThreadSourcePickerItem[];
  isLoading: boolean;
  isCreating?: boolean;
  onSelect: (item: ThreadSourcePickerItem) => void | Promise<void>;
}

export function ThreadSourcePickerDialog({
  open,
  onOpenChange,
  kind,
  repoName,
  items,
  isLoading,
  isCreating,
  onSelect,
}: ThreadSourcePickerDialogProps) {
  const { t } = useI18n();
  const [query, setQuery] = useState("");

  const filteredItems = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    if (!normalized) {
      return items;
    }

    return items.filter((item) => {
      return [item.title, item.subtitle, item.meta]
        .filter(Boolean)
        .some((value) => value!.toLowerCase().includes(normalized));
    });
  }, [items, query]);

  const titleKey = `agents.sourcePicker.${kind}.title`;
  const descriptionKey = `agents.sourcePicker.${kind}.description`;
  const searchKey = `agents.sourcePicker.${kind}.search`;
  const emptyKey = `agents.sourcePicker.${kind}.empty`;

  return (
    <Dialog
      open={open}
      onOpenChange={(nextOpen) => {
        if (!nextOpen) {
          setQuery("");
        }
        onOpenChange(nextOpen);
      }}
    >
      <DialogContent className="max-w-2xl gap-0 overflow-hidden p-0">
        <DialogHeader className="border-b border-border px-5 pt-5 pb-4">
          <DialogTitle className="text-base">{t(titleKey)}</DialogTitle>
          <DialogDescription className="mt-1.5 text-sm text-muted-foreground">
            {t(descriptionKey).replace("{repo}", repoName)}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 px-5 py-4">
          <Input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder={t(searchKey)}
            className="h-10 border-zinc-200 bg-zinc-100 text-sm text-zinc-700 placeholder:text-zinc-400 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-200 dark:placeholder:text-zinc-500"
          />

          <div className="max-h-[420px] overflow-y-auto rounded-md border border-zinc-200 bg-background/60 dark:border-zinc-800">
            {isLoading ? (
              <div className="flex items-center justify-center gap-2 px-4 py-12 text-sm text-muted-foreground">
                <Loader2 className="h-4 w-4 animate-spin" />
                <span>{t("agents.sourcePicker.loading")}</span>
              </div>
            ) : filteredItems.length === 0 ? (
              <div className="px-4 py-12 text-center text-sm text-muted-foreground">
                {t(emptyKey)}
              </div>
            ) : (
              <div className="p-2">
                {filteredItems.map((item) => (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => onSelect(item)}
                    disabled={isCreating}
                    className={cn(
                      "flex w-full flex-col gap-1 rounded-lg px-3 py-3 text-left transition-colors",
                      "hover:bg-accent hover:text-accent-foreground",
                      "disabled:pointer-events-none disabled:opacity-50",
                    )}
                  >
                    <div className="flex items-center justify-between gap-3">
                      <span className="text-sm font-semibold text-foreground">{item.title}</span>
                      {item.meta ? (
                        <span className="shrink-0 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                          {item.meta}
                        </span>
                      ) : null}
                    </div>
                    {item.subtitle ? (
                      <span className="text-xs text-muted-foreground">{item.subtitle}</span>
                    ) : null}
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
