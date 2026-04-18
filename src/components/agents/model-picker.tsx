import { useState } from "react";
import { Check, ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";

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
  const { aiProviders } = useAgentsStore();

  const allModels = aiProviders.flatMap((p) => p.models);
  const selectedModel = allModels.find((m) => m.id === value);
  const selectedProvider = aiProviders.find((p) => p.models.some((m) => m.id === value));

  const displayLabel = selectedModel?.label ?? emptyLabel ?? noneLabel ?? "Select model";

  function handleSelect(modelId: string | null) {
    onChange(modelId);
    setOpen(false);
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
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
              "flex h-8 shrink-0 items-center justify-between gap-1.5 rounded-md border border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 outline-none transition-colors hover:bg-zinc-200 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300 dark:hover:bg-zinc-700",
              className,
            )}
          >
            <div className="flex items-center gap-2 min-w-0">
              <span className="truncate">{displayLabel}</span>
              {selectedModel && selectedProvider && (
                <span className="shrink-0 text-[11px] font-normal text-zinc-500 dark:text-zinc-400">
                  {selectedProvider.name}
                </span>
              )}
            </div>
            <ChevronDown className="h-3.5 w-3.5 shrink-0 opacity-60" />
          </button>
        )}
      </PopoverTrigger>
      <PopoverContent
        align={align}
        className="w-56 p-0 flex flex-col"
        style={{ maxHeight: "360px" }}
      >
        <Command className="flex flex-col">
          <CommandInput placeholder="Search models..." />
          <CommandList style={{ maxHeight: "310px", overflowY: "scroll" }}>
            <CommandEmpty>No models found.</CommandEmpty>
            {noneLabel && (
              <CommandGroup>
                <CommandItem
                  value={noneLabel}
                  onSelect={() => handleSelect(null)}
                  className={cn(!value && "text-purple-400")}
                >
                  <div className={cn("h-1.5 w-1.5 rounded-full shrink-0", !value ? "bg-purple-400" : "bg-zinc-500")} />
                  <span>{noneLabel}</span>
                  {!value && <Check className="ml-auto h-3.5 w-3.5 text-purple-400 shrink-0" />}
                </CommandItem>
              </CommandGroup>
            )}
            {aiProviders.map((provider) => (
              <CommandGroup key={provider.name} heading={provider.name}>
                {provider.models.map((model) => (
                  <CommandItem
                    key={model.id}
                    value={`${model.label} ${provider.name}`}
                    onSelect={() => handleSelect(model.id)}
                    className={cn(value === model.id && "text-purple-400")}
                  >
                    <div className={cn("h-1.5 w-1.5 rounded-full shrink-0", value === model.id ? "bg-purple-400" : "bg-zinc-500")} />
                    <span>{model.label}</span>
                    <span className="text-[11px] text-muted-foreground font-normal">{provider.name}</span>
                    {value === model.id && <Check className="ml-auto h-3.5 w-3.5 text-purple-400 shrink-0" />}
                  </CommandItem>
                ))}
              </CommandGroup>
            ))}
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
