import { Plus, Mic, ArrowUp, ChevronDown, AlertCircle, Check, Zap, Terminal, Square, Search } from "lucide-react";
import { useState, useEffect, useRef, useMemo, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { useToggle } from "@uidotdev/usehooks";
import { useAgentsStore } from "@/stores/useAgentsStore";
import type { SendMessageOptions } from "@/stores/useAgentsStore";
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
  const { t } = useI18n();
  const itemRefs = useRef<(HTMLButtonElement | null)[]>([]);

  // Scroll focused item into view
  useEffect(() => {
    itemRefs.current[focusedIndex]?.scrollIntoView({ block: "nearest" });
  }, [focusedIndex]);

  if (items.length === 0) {
    return (
      <div className="rounded-xl dark:border-white/[0.06] border-border border dark:bg-zinc-900 bg-popover shadow-2xl p-3 text-[12px] text-zinc-500">
        {t("agents.chatInput.slash.noMatch")} <span className="text-foreground/60">/{query}</span>
      </div>
    );
  }

  const commands = items.filter((i) => i.type === "command");
  const skills = items.filter((i) => i.type === "skill");

  let globalIndex = 0;

  return (
    <div className="rounded-xl dark:border-white/[0.06] border-border border dark:bg-zinc-900 bg-popover shadow-2xl overflow-hidden max-h-72 overflow-y-auto">
      {commands.length > 0 && (
        <div>
          <div className="flex items-center gap-2 px-3 pt-3 pb-1.5">
            <Terminal className="h-3 w-3 text-zinc-500" />
            <span className="text-[10px] font-black uppercase tracking-[0.15em] text-zinc-500">{t("agents.chatInput.slash.commands")}</span>
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
                  focused ? "dark:bg-white/[0.07] bg-black/[0.07]" : "dark:hover:bg-white/[0.04] hover:bg-black/[0.04]",
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
            <span className="text-[10px] font-black uppercase tracking-[0.15em] text-zinc-500">{t("agents.chatInput.slash.skills")}</span>
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
                  focused ? "dark:bg-white/[0.07] bg-black/[0.07]" : "dark:hover:bg-white/[0.04] hover:bg-black/[0.04]",
                )}
              >
                <div className={cn("h-6 w-6 shrink-0 rounded-md flex items-center justify-center text-[9px] font-bold dark:border-white/5 border-border border", skill.icon)}>
                  {skill.textIcon
                    ? skill.textIcon
                    : <div className="h-2.5 w-2.5 rounded-full bg-current opacity-80" />}
                </div>
                <div className="flex flex-col min-w-0">
                  <span className="text-[13px] font-medium text-foreground/80 truncate">{skill.label}</span>
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
  const { t } = useI18n();
  const [message, setMessage] = useState("");
  const [open, setOpen] = useState(false);
  const [slashOpen, setSlashOpen] = useState(false);
  const [slashQuery, setSlashQuery] = useState("");
  const [focusedIndex, setFocusedIndex] = useState(0);
  const [planMode, togglePlanMode] = useToggle(false);
  const [thinkingOpen, setThinkingOpen] = useState(false);
  const [thinkingBudget, setThinkingBudget] = useState<"x-high" | "high" | "medium" | "low">("medium");
  const [fastMode, toggleFastMode] = useToggle(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const {
    aiProviders,
    selectedModelId,
    selectedModelByThread,
    setThreadModelId,
    loadAiProviders,
    sendMessage,
    streamingThreadIds,
    selectedIssueId,
    messages,
  } = useAgentsStore();

  useEffect(() => {
    loadAiProviders();
  }, [loadAiProviders]);

  // Effective model for this thread: per-thread override → global default.
  const effectiveModelId = (selectedIssueId && selectedModelByThread[selectedIssueId]) || selectedModelId;

  const selectedModel = aiProviders
    .flatMap((p) => p.models)
    .find((m) => m.id === effectiveModelId);

  const selectedProvider = aiProviders.find((p) =>
    p.models.some((m) => m.id === effectiveModelId),
  );

  const contextWindow = selectedModel?.context_window ?? 0;
  const usedTokens = useMemo(
    () => Math.round(messages.reduce((sum, m) => sum + m.content.length, 0) / 4),
    [messages],
  );

  const hasReasoning = selectedModel?.capabilities.includes("reasoning") ?? false;
  const supportsPlanMode = selectedModel !== undefined;
  const hasProviders = aiProviders.length > 0;

  useEffect(() => {
    if (!hasReasoning) {
      setThinkingBudget("medium");
    }

    if (!supportsPlanMode) {
      togglePlanMode(false);
    }
  }, [hasReasoning, supportsPlanMode]);

  const thinkingLabels: Record<string, string> = {
    "x-high": "X-High",
    high: "High",
    medium: "Medium",
    low: "Low",
  };
  const isCurrentThreadStreaming = !!streamingThreadIds[selectedIssueId ?? ""];
  const canSend = message.trim().length > 0 && hasProviders && !!selectedIssueId;
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
    const opts: SendMessageOptions = {
      planMode,
      thinkingBudget: hasReasoning ? thinkingBudget : "not-available",
      fastMode,
    };
    await sendMessage(selectedIssueId!, content, effectiveModelId!, undefined, opts);
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
            <span className="text-[13px] font-semibold text-amber-400">{t("agents.chatInput.noProviders.title")}</span>
            <span className="text-[11px] text-zinc-500">
              {t("agents.chatInput.noProviders.description")}
            </span>
          </div>
        </div>
      )}

      <Card className="gap-0 p-0">
        <CardContent className="flex flex-col p-3 border-0">

          <div className="flex items-center justify-between px-1">
            <div className="flex items-center gap-2 text-zinc-400">
              <button className="hover:text-foreground transition-colors p-1">
                <Plus className="h-4 w-4" />
              </button>

              {hasProviders ? (
                <Popover open={open} onOpenChange={setOpen}>
                  <PopoverTrigger asChild>
                    <button className="flex items-center gap-2 hover:text-foreground transition-colors group outline-none">
                      <span className="text-[13px] font-medium">
                        {selectedModel?.label ?? t("agents.chatInput.selectModel")}
                      </span>
                      {selectedProvider && (
                        <span className="text-[11px] text-muted-foreground font-normal">
                          {selectedProvider.name}
                        </span>
                      )}
                      <ChevronDown className="h-3 w-3 opacity-50 group-hover:opacity-100 transition-opacity" />
                    </button>
                  </PopoverTrigger>
                  <PopoverContent
                    align="start"
                    className="w-56 bg-popover dark:border-white/[0.05] border-border p-0 shadow-2xl rounded-md overflow-hidden"
                  >
                    <Command className="bg-transparent">
                      <div className="flex items-center px-3 border-b dark:border-white/[0.05] border-border">
                        <Search className="h-3.5 w-3.5 text-zinc-500 shrink-0 mr-2" />
                        <CommandInput
                          placeholder={t("agents.chatInput.searchModels")}
                          className="h-9 text-[13px] border-0 outline-none ring-0 focus:ring-0 px-0"
                        />
                      </div>
                      <CommandList className="max-h-[260px] p-1">
                        <CommandEmpty className="py-6 text-center text-[12px] text-zinc-500">
                          {t("agents.chatInput.noModels")}
                        </CommandEmpty>
                        {aiProviders.map((provider) => (
                          <CommandGroup key={provider.name}>
                            {provider.models.map((model) => (
                              <CommandItem
                                key={model.id}
                                value={model.label}
                                onSelect={() => {
                                  if (selectedIssueId) {
                                    setThreadModelId(selectedIssueId, model.id);
                                  }
                                  setOpen(false);
                                }}
                                className={cn(
                                  "flex items-center gap-2 px-2 py-1.5 rounded-md cursor-pointer text-[13px] font-medium",
                                  effectiveModelId === model.id
                                    ? "bg-purple-500/10 text-purple-400"
                                    : "text-foreground/70"
                                )}
                              >
                                <div className={cn(
                                  "h-1.5 w-1.5 rounded-full shrink-0",
                                  effectiveModelId === model.id ? "bg-purple-400" : "bg-zinc-500"
                                )} />
                                <span>{model.label}</span>
                                <span className="text-[11px] text-muted-foreground font-normal">
                                  {provider.name}
                                </span>
                                {effectiveModelId === model.id && (
                                  <Check className="ml-auto h-3.5 w-3.5 text-purple-400 shrink-0" />
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
                <span className="text-[13px] font-medium text-zinc-500">{t("agents.chatInput.noModelsAvailable")}</span>
              )}

              {supportsPlanMode && (
                <button
                  onClick={() => togglePlanMode()}
                  className={cn(
                    "text-[12px] font-medium px-2 py-0.5 rounded transition-colors",
                    planMode
                      ? "bg-purple-500/20 text-purple-400"
                      : "hover:text-foreground",
                  )}
                >
                  Plan mode
                </button>
              )}

              {hasReasoning && (
                <Popover open={thinkingOpen} onOpenChange={setThinkingOpen}>
                  <PopoverTrigger asChild>
                    <button
                      className={cn(
                        "text-[12px] font-medium px-2 py-0.5 rounded transition-colors",
                        thinkingBudget !== "medium"
                          ? "bg-purple-500/20 text-purple-400"
                          : "hover:text-foreground",
                      )}
                    >
                      {thinkingLabels[thinkingBudget]}
                    </button>
                  </PopoverTrigger>
                  <PopoverContent align="start" className="w-32 p-1 bg-popover dark:border-white/[0.05] border-border shadow-2xl rounded-md">
                    {(["x-high", "high", "medium", "low"] as const).map((level) => (
                      <button
                        key={level}
                        onClick={() => { setThinkingBudget(level); setThinkingOpen(false); }}
                        className={cn(
                          "w-full text-left px-3 py-1.5 text-[13px] font-medium rounded transition-colors",
                          thinkingBudget === level
                            ? "text-purple-400 bg-purple-500/10"
                            : "text-foreground/70 hover:bg-white/[0.04]",
                        )}
                      >
                        {thinkingLabels[level]}
                      </button>
                    ))}
                  </PopoverContent>
                </Popover>
              )}

              <button
                title="Toggle fast mode"
                onClick={() => toggleFastMode()}
                className={cn(
                  "text-[12px] font-medium px-2 py-0.5 rounded transition-colors",
                  fastMode
                    ? "bg-emerald-500/20 text-emerald-400"
                    : "hover:text-foreground",
                )}
              >
                {fastMode ? "Fast" : "Standard"}
              </button>

              <span className="text-[12.5px] font-medium tracking-wide tabular-nums">
                {usedTokens > 0 ? `${(usedTokens / 1000).toFixed(0)}k / ` : ""}{(contextWindow / 1000).toFixed(0)}k
              </span>
            </div>

            <div className="flex items-center gap-2">
              <button className="hover:text-foreground text-zinc-400 transition-colors p-1">
                <Mic className="h-4 w-4" />
              </button>
              <button
              onClick={
                isCurrentThreadStreaming
                  ? () => { invoke("abort_agent", { threadId: selectedIssueId }); }
                  : handleSend
              }
              disabled={!isCurrentThreadStreaming && !canSend}
              className={cn(
                "flex h-8 w-8 items-center justify-center rounded-lg transition-all duration-300 shrink-0",
                isCurrentThreadStreaming
                  ? "dark:bg-white/10 bg-black/10 text-foreground dark:hover:bg-white/20 hover:bg-black/20 cursor-pointer"
                  : canSend
                  ? "dark:bg-white/10 bg-black/10 text-foreground dark:hover:bg-white/20 hover:bg-black/20 cursor-pointer"
                  : "dark:bg-white/[0.03] bg-black/[0.03] text-zinc-400 cursor-not-allowed"
              )}
            >
              {isCurrentThreadStreaming ? (
                <Square className="h-3.5 w-3.5 fill-current" />
              ) : (
                <ArrowUp className="h-4 w-4" />
              )}
            </button>
            </div>
          </div>

          <div className="mt-2.5 px-1 pb-1">
            <textarea
              ref={textareaRef}
              value={message}
              onChange={(e) => handleChange(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder={
                isCurrentThreadStreaming
                  ? t("agents.chatInput.placeholder.responding")
                  : hasProviders
                  ? t("agents.chatInput.placeholder.ready")
                  : t("agents.chatInput.placeholder.noProvider")
              }
              disabled={!hasProviders}
              className="w-full bg-transparent border-none outline-none focus:ring-0 text-[14px] font-medium text-foreground/90 placeholder:text-zinc-600 resize-none h-[24px] custom-scrollbar p-0 disabled:opacity-50"
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
