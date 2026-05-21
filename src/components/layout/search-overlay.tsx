import { useEffect, useState, type ReactNode } from "react";
import { SearchX } from "lucide-react";

import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import { useSearchStore } from "@/stores/search-store";

function isTyping(): boolean {
  const el = document.activeElement;
  return (
    el instanceof HTMLElement &&
    (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable)
  );
}

function highlight(text: string, query: string): ReactNode {
  const q = query.trim();
  if (!q) return text;
  const i = text.toLowerCase().indexOf(q.toLowerCase());
  if (i === -1) return text;
  return (
    <>
      {text.slice(0, i)}
      <mark className="rounded-sm bg-purple-500/30 text-foreground">{text.slice(i, i + q.length)}</mark>
      {text.slice(i + q.length)}
    </>
  );
}

export function SearchOverlay() {
  const open = useSearchStore((s) => s.open);
  const setOpen = useSearchStore((s) => s.setOpen);
  const provider = useSearchStore((s) => s.provider);
  const [query, setQuery] = useState("");

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "/" || isTyping()) return;
      if (!useSearchStore.getState().provider) return;
      e.preventDefault();
      setOpen(true);
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [setOpen]);

  useEffect(() => {
    if (!open) setQuery("");
  }, [open]);

  if (!provider) return null;

  return (
    <CommandDialog open={open} onOpenChange={setOpen}>
      <CommandInput
        placeholder={provider.placeholder}
        value={query}
        onValueChange={setQuery}
        className="h-11"
      />
      <CommandList className="h-[400px] custom-scrollbar">
        <CommandEmpty className="flex flex-col items-center justify-center gap-2 py-12 text-center">
          <SearchX className="h-5 w-5 text-zinc-600" />
          <span className="text-[13px] font-medium text-zinc-400">No results</span>
          <span className="text-[11px] text-zinc-600">Try a different search</span>
        </CommandEmpty>
        <CommandGroup>
          {provider.items.map((item) => (
            <CommandItem
              key={item.id}
              value={`${item.title} ${item.subtitle ?? ""}`}
              onSelect={() => {
                item.onSelect();
                setOpen(false);
              }}
            >
              <span className="truncate">{highlight(item.title, query)}</span>
              {item.subtitle && (
                <span className="ml-auto shrink-0 text-xs text-muted-foreground">{item.subtitle}</span>
              )}
            </CommandItem>
          ))}
        </CommandGroup>
      </CommandList>
    </CommandDialog>
  );
}
