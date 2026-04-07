import { useState, useMemo } from "react";
import { Check, ChevronDown, Search } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { DropdownMenu as DropdownMenuPrimitive } from "radix-ui";

interface ModelPickerProps {
  value: string | null;
  onChange: (modelId: string | null) => void;
  noneLabel?: string;
  variant?: "pill" | "text";
  emptyLabel?: string;
  align?: "start" | "center" | "end";
  className?: string;
}

export function ModelPicker({
  value,
  onChange,
  noneLabel,
  variant = "pill",
  emptyLabel,
  align = "end",
  className,
}: ModelPickerProps) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const { aiProviders } = useAgentsStore();

  const allModels = aiProviders.flatMap((p) => p.models);
  const selectedModel = allModels.find((m) => m.id === value);
  const selectedProvider = aiProviders.find((p) => p.models.some((m) => m.id === value));

  const displayLabel = selectedModel?.label ?? emptyLabel ?? noneLabel ?? "Select model";

  const filtered = useMemo(() => {
    const q = search.toLowerCase();
    if (!q) return aiProviders;
    return aiProviders
      .map((p) => ({
        ...p,
        models: p.models.filter(
          (m) =>
            m.label.toLowerCase().includes(q) ||
            p.name.toLowerCase().includes(q),
        ),
      }))
      .filter((p) => p.models.length > 0);
  }, [search, aiProviders]);

  function handleSelect(modelId: string | null) {
    onChange(modelId);
    setOpen(false);
    setSearch("");
  }

  return (
    <DropdownMenu open={open} onOpenChange={(v) => { setOpen(v); if (!v) setSearch(""); }}>
      <DropdownMenuTrigger asChild>
        {variant === "text" ? (
          <button className={cn("flex items-center gap-2 hover:text-foreground transition-colors group outline-none", className)}>
            <span className="text-[13px] font-medium">{displayLabel}</span>
            {selectedProvider && (
              <span className="text-[11px] text-muted-foreground font-normal">
                {selectedProvider.name}
              </span>
            )}
            <ChevronDown className="h-3 w-3 opacity-50 group-hover:opacity-100 transition-opacity" />
          </button>
        ) : (
          <button
            className={cn(
              "flex items-center gap-1.5 h-8 rounded-md border border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300 shrink-0 outline-none hover:bg-zinc-200 dark:hover:bg-zinc-700 transition-colors",
              className,
            )}
          >
            <span className="truncate max-w-[120px]">{displayLabel}</span>
            {selectedModel && selectedProvider && (
              <span className="text-[10px] text-zinc-400 dark:text-zinc-500 font-normal shrink-0 hidden sm:inline">
                {selectedProvider.name}
              </span>
            )}
            <ChevronDown className="h-3 w-3 opacity-50 shrink-0" />
          </button>
        )}
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align={align}
        className="w-56 p-0"
      >
        <div className="flex items-center gap-2 px-3 border-b dark:border-white/[0.05] border-border sticky top-0 bg-popover z-10">
          <Search className="h-3.5 w-3.5 text-zinc-500 shrink-0" />
          <input
            autoFocus
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            onKeyDown={(e) => e.stopPropagation()}
            placeholder="Search models..."
            className="h-9 w-full bg-transparent text-[13px] text-foreground placeholder:text-zinc-500 outline-none border-0"
          />
        </div>

        <div className="p-1">
          {noneLabel && (
            <DropdownMenuPrimitive.Item
              onSelect={() => handleSelect(null)}
              className={cn(
                "flex w-full items-center gap-2 px-2 py-1.5 rounded-md text-[13px] font-medium cursor-pointer transition-colors outline-none select-none",
                !value
                  ? "bg-purple-500/10 text-purple-400"
                  : "text-foreground/70 focus:bg-white/5",
              )}
            >
              <div className={cn("h-1.5 w-1.5 rounded-full shrink-0", !value ? "bg-purple-400" : "bg-zinc-500")} />
              <span>{noneLabel}</span>
              {!value && <Check className="ml-auto h-3.5 w-3.5 text-purple-400 shrink-0" />}
            </DropdownMenuPrimitive.Item>
          )}

          {filtered.length === 0 && (
            <p className="py-6 text-center text-[12px] text-zinc-500">No models found.</p>
          )}
          {filtered.map((provider) => (
            <div key={provider.name}>
              {filtered.length > 1 && (
                <p className="px-2 pt-2 pb-1 text-[9px] font-bold uppercase tracking-widest text-zinc-500">
                  {provider.name}
                </p>
              )}
              {provider.models.map((model) => (
                <DropdownMenuPrimitive.Item
                  key={model.id}
                  onSelect={() => handleSelect(model.id)}
                  className={cn(
                    "flex w-full items-center gap-2 px-2 py-1.5 rounded-md text-[13px] font-medium cursor-pointer transition-colors outline-none select-none",
                    value === model.id
                      ? "bg-purple-500/10 text-purple-400"
                      : "text-foreground/70 focus:bg-white/5",
                  )}
                >
                  <div className={cn("h-1.5 w-1.5 rounded-full shrink-0", value === model.id ? "bg-purple-400" : "bg-zinc-500")} />
                  <span>{model.label}</span>
                  <span className="text-[11px] text-muted-foreground font-normal">{provider.name}</span>
                  {value === model.id && <Check className="ml-auto h-3.5 w-3.5 text-purple-400 shrink-0" />}
                </DropdownMenuPrimitive.Item>
              ))}
            </div>
          ))}
        </div>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
