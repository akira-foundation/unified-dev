import { Plus, Mic, ArrowUp, ChevronDown, AlertCircle, Check, Zap, Terminal } from "lucide-react";
import { useState, useEffect, useRef, useMemo, useCallback } from "react";
import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Card, CardContent } from "@/components/ui/card";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import { installedSkills, slashCommands } from "@/lib/skills-data";

// ─── Slash menu ──────────────────────────────────────────────────────────────

interface SlashItem {
  type: "command" | "skill";
  id: string;
  label: string;
  description: string;
  icon?: string;
  textIcon?: string;
  insertValue: string;
}

interface SlashMenuProps {
  query: string;
  focusedIndex: number;
  onSelect: (value: string) => void;
  items: SlashItem[];
}

function SlashMenu({ query, focusedIndex, onSelect, items }: SlashMenuProps) {
  const itemRefs = useRef<(HTMLButtonElement | null)[]>([]);

  // Scroll focused item into view
  useEffect(() => {
    itemRefs.current[focusedIndex]?.scrollIntoView({ block: "nearest" });
  }, [focusedIndex]);

  if (items.length === 0) {
    return (
      <div className="rounded-xl border border-white/[0.06] bg-zinc-900 shadow-2xl p-3 text-[12px] text-zinc-500">
        No commands or skills match <span className="text-white/60">/{query}</span>
      </div>
    );
  }

  const commands = items.filter((i) => i.type === "command");
  const skills = items.filter((i) => i.type === "skill");

  let globalIndex = 0;

  return (
    <div className="rounded-xl border border-white/[0.06] bg-zinc-900 shadow-2xl overflow-hidden max-h-72 overflow-y-auto">
      {commands.length > 0 && (
        <div>
          <div className="flex items-center gap-2 px-3 pt-3 pb-1.5">
            <Terminal className="h-3 w-3 text-zinc-500" />
            <span className="text-[10px] font-black uppercase tracking-[0.15em] text-zinc-500">Commands</span>
          </div>
          {commands.map((cmd) => {
            const idx = globalIndex++;
            const focused = idx === focusedIndex;
            return (
              <button
                key={cmd.id}
                ref={(el) => { itemRefs.current[idx] = el; }}
                onMouseDown={(e) => {
                  e.preventDefault();
                  onSelect(cmd.insertValue);
                }}
                className={cn(
                  "w-full flex items-center gap-3 px-3 py-2 transition-colors text-left",
                  focused ? "bg-white/[0.07]" : "hover:bg-white/[0.04]",
                )}
              >
                <span className="text-[13px] font-mono font-medium text-purple-400 w-24 shrink-0">{cmd.label}</span>
                <span className="text-[12px] text-zinc-400 truncate">{cmd.description}</span>
              </button>
            );
          })}
        </div>
      )}

      {skills.length > 0 && (
        <div>
          <div className="flex items-center gap-2 px-3 pt-3 pb-1.5">
            <Zap className="h-3 w-3 text-zinc-500" />
            <span className="text-[10px] font-black uppercase tracking-[0.15em] text-zinc-500">Skills</span>
          </div>
          {skills.map((skill) => {
            const idx = globalIndex++;
            const focused = idx === focusedIndex;
            return (
              <button
                key={skill.id}
                ref={(el) => { itemRefs.current[idx] = el; }}
                onMouseDown={(e) => {
                  e.preventDefault();
                  onSelect(skill.insertValue);
                }}
                className={cn(
                  "w-full flex items-center gap-3 px-3 py-2 transition-colors text-left",
                  focused ? "bg-white/[0.07]" : "hover:bg-white/[0.04]",
                )}
              >
                <div className={cn("h-6 w-6 shrink-0 rounded-md flex items-center justify-center text-[9px] font-bold border border-white/5", skill.icon)}>
                  {skill.textIcon
                    ? skill.textIcon
                    : <div className="h-2.5 w-2.5 rounded-full bg-current opacity-80" />}
                </div>
                <div className="flex flex-col min-w-0">
                  <span className="text-[13px] font-medium text-white/80 truncate">{skill.label}</span>
                  <span className="text-[11px] text-zinc-500 truncate">{skill.description}</span>
                </div>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ─── Main input ───────────────────────────────────────────────────────────────

export function AgentChatInput() {
  const [message, setMessage] = useState("");
  const [open, setOpen] = useState(false);
  const [slashOpen, setSlashOpen] = useState(false);
  const [slashQuery, setSlashQuery] = useState("");
  const [focusedIndex, setFocusedIndex] = useState(0);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const {
    aiProviders,
    selectedModelId,
    setSelectedModelId,
    loadAiProviders,
    sendMessage,
    isStreaming,
    selectedIssueId,
  } = useAgentsStore();

  useEffect(() => {
    loadAiProviders();
  }, [loadAiProviders]);

  const selectedModel = aiProviders
    .flatMap((p) => p.models)
    .find((m) => m.id === selectedModelId);

  const hasProviders = aiProviders.length > 0;
  const canSend = message.trim().length > 0 && hasProviders && !!selectedIssueId && !isStreaming;

  // Build flat list of slash items from the current query
  const slashItems = useMemo<SlashItem[]>(() => {
    const lowerQuery = slashQuery.toLowerCase();

    const commands: SlashItem[] = slashCommands
      .filter((c) => c.id.includes(lowerQuery) || c.description.toLowerCase().includes(lowerQuery))
      .map((c) => ({
        type: "command",
        id: c.id,
        label: c.label,
        description: c.description,
        insertValue: c.label + " ",
      }));

    const skills: SlashItem[] = installedSkills
      .filter(
        (s) =>
          s.active &&
          (s.id.includes(lowerQuery) ||
            s.title.toLowerCase().includes(lowerQuery) ||
            s.description.toLowerCase().includes(lowerQuery)),
      )
      .map((s) => ({
        type: "skill",
        id: s.id,
        label: s.title,
        description: s.description,
        icon: s.icon,
        textIcon: s.textIcon,
        insertValue: `/${s.id} `,
      }));

    return [...commands, ...skills];
  }, [slashQuery]);

  // Reset focus when item list changes
  useEffect(() => {
    setFocusedIndex(0);
  }, [slashItems.length]);

  // Detect slash at the start of the message
  function handleChange(value: string) {
    setMessage(value);

    if (value.startsWith("/")) {
      const query = value.slice(1);
      if (!query.includes(" ")) {
        setSlashQuery(query);
        setSlashOpen(true);
        return;
      }
    }
    setSlashOpen(false);
    setSlashQuery("");
  }

  const handleSlashSelect = useCallback((value: string) => {
    setMessage(value);
    setSlashOpen(false);
    setSlashQuery("");
    setFocusedIndex(0);
    textareaRef.current?.focus();
  }, []);

  const handleSend = async () => {
    if (!canSend) return;
    const content = message.trim();
    setMessage("");
    setSlashOpen(false);
    if (textareaRef.current) {
      textareaRef.current.style.height = "24px";
    }
    await sendMessage(selectedIssueId!, content, selectedModelId!);
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (slashOpen && slashItems.length > 0) {
      if (e.key === "ArrowDown") {
        e.preventDefault();
        setFocusedIndex((i) => (i + 1) % slashItems.length);
        return;
      }
      if (e.key === "ArrowUp") {
        e.preventDefault();
        setFocusedIndex((i) => (i - 1 + slashItems.length) % slashItems.length);
        return;
      }
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        handleSlashSelect(slashItems[focusedIndex].insertValue);
        return;
      }
      if (e.key === "Tab") {
        e.preventDefault();
        handleSlashSelect(slashItems[focusedIndex].insertValue);
        return;
      }
    }

    if (e.key === "Escape" && slashOpen) {
      e.preventDefault();
      setSlashOpen(false);
      return;
    }
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  return (
    <div className="relative">
      {/* Slash command menu — rendered above the card */}
      {slashOpen && (
        <div className="absolute bottom-full mb-2 left-0 right-0 z-50">
          <SlashMenu
            query={slashQuery}
            focusedIndex={focusedIndex}
            onSelect={handleSlashSelect}
            items={slashItems}
          />
        </div>
      )}

      {!hasProviders && (
        <div className="flex items-center gap-3 mb-3 px-4 py-3 rounded-xl bg-amber-500/5 border border-amber-500/10">
          <AlertCircle className="h-4 w-4 text-amber-500 shrink-0" />
          <div className="flex flex-col gap-0.5">
            <span className="text-[13px] font-semibold text-amber-400">No AI providers detected</span>
            <span className="text-[11px] text-zinc-500">
              Set ANTHROPIC_API_KEY or OPENAI_API_KEY to enable agents.
            </span>
          </div>
        </div>
      )}

      <Card className="gap-0 p-0">
        <CardContent className="flex flex-col p-3 border-0">

          <div className="flex items-center justify-between px-1">
            <div className="flex items-center gap-4 text-zinc-400">
              <button className="hover:text-white transition-colors p-1">
                <Plus className="h-4 w-4" />
              </button>

              {hasProviders ? (
                <Popover open={open} onOpenChange={setOpen}>
                  <PopoverTrigger asChild>
                    <button className="flex items-center gap-2 hover:text-white transition-colors group outline-none">
                      <span className="text-[13px] font-medium">
                        {selectedModel?.label ?? "Select model"}
                      </span>
                      <ChevronDown className="h-3 w-3 opacity-50 group-hover:opacity-100 transition-opacity" />
                    </button>
                  </PopoverTrigger>
                  <PopoverContent
                    align="start"
                    className="w-64 bg-background border-white/[0.05] p-0 shadow-2xl rounded-md"
                  >
                    <Command className="bg-transparent">
                      <CommandInput
                        placeholder="Search models..."
                        className="text-[13px] text-white/90 placeholder:text-zinc-600 border-white/[0.04]"
                      />
                      <CommandList className="max-h-[280px]">
                        <CommandEmpty className="py-6 text-center text-[12px] text-zinc-500">
                          No models found
                        </CommandEmpty>
                        {aiProviders.map((provider) => (
                          <CommandGroup
                            key={provider.name}
                            heading={provider.name}
                            className="[&_[cmdk-group-heading]]:text-[10px] [&_[cmdk-group-heading]]:font-black [&_[cmdk-group-heading]]:uppercase [&_[cmdk-group-heading]]:tracking-[0.15em] [&_[cmdk-group-heading]]:text-zinc-500"
                          >
                            {provider.models.map((model) => (
                              <CommandItem
                                key={model.id}
                                value={model.label}
                                onSelect={() => {
                                  setSelectedModelId(model.id);
                                  setOpen(false);
                                }}
                                className={cn(
                                  "flex items-center gap-3 px-3 py-2 rounded-md cursor-pointer text-[13px] font-medium",
                                  selectedModelId === model.id
                                    ? "bg-purple-500/10 text-purple-400"
                                    : "text-zinc-300"
                                )}
                              >
                                <div className={cn(
                                  "h-1.5 w-1.5 rounded-full shrink-0",
                                  selectedModelId === model.id ? "bg-purple-400" : "bg-zinc-600"
                                )} />
                                {model.label}
                                {selectedModelId === model.id && (
                                  <Check className="ml-auto h-3.5 w-3.5 text-purple-400" />
                                )}
                              </CommandItem>
                            ))}
                          </CommandGroup>
                        ))}
                      </CommandList>
                    </Command>
                  </PopoverContent>
                </Popover>
              ) : (
                <span className="text-[13px] font-medium text-zinc-600">No models available</span>
              )}

              <button className="hover:text-white transition-colors p-1">
                <Mic className="h-4 w-4" />
              </button>
              <span className="text-[12.5px] font-medium tracking-wide">
                2842k
              </span>
            </div>

            <button
              onClick={handleSend}
              disabled={!canSend}
              className={cn(
                "flex h-8 w-8 items-center justify-center rounded-lg transition-all duration-300 shrink-0",
                canSend
                  ? "bg-white/10 text-white hover:bg-white/20 cursor-pointer"
                  : "bg-white/[0.03] text-zinc-500 cursor-not-allowed"
              )}
            >
              <ArrowUp className="h-4 w-4" />
            </button>
          </div>

          <div className="mt-2.5 px-1 pb-1">
            <textarea
              ref={textareaRef}
              value={message}
              onChange={(e) => handleChange(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder={
                isStreaming
                  ? "Agent is responding..."
                  : hasProviders
                  ? "Ask to make changes... (/ for commands)"
                  : "Configure an AI provider to start..."
              }
              disabled={!hasProviders || isStreaming}
              className="w-full bg-transparent border-none outline-none focus:ring-0 text-[14px] font-medium text-white/90 placeholder:text-zinc-500 resize-none h-[24px] custom-scrollbar p-0 disabled:opacity-50"
              rows={1}
              onInput={(e) => {
                const target = e.target as HTMLTextAreaElement;
                target.style.height = "24px";
                target.style.height = `${target.scrollHeight}px`;
              }}
            />
          </div>

        </CardContent>
      </Card>
    </div>
  );
}
