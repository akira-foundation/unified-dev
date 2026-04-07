import { Mic, ArrowUp, AlertCircle, Zap, Terminal, Square, X, ImageIcon } from "lucide-react";
import { useState, useEffect, useRef, useMemo, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useQuery } from "@tanstack/react-query";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { useToggle } from "@uidotdev/usehooks";
import { useAgentsStore } from "@/stores/useAgentsStore";
import type { SendMessageOptions, InstalledSkill, ChatMessage } from "@/stores/useAgentsStore";
import type { ImagePart, ImageMediaType } from "@/types/agents";
import { IMAGE_SIZE_LIMIT, contentToText } from "@/types/agents";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Card, CardContent } from "@/components/ui/card";
import { slashCommands } from "@/lib/skills-data";
import { queryKeys } from "@/lib/query-keys";
import { ModelPicker } from "@/components/agents/model-picker";


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



export function AgentChatInput() {
  const { t } = useI18n();
  const [message, setMessage] = useState("");
  const [slashOpen, setSlashOpen] = useState(false);
  const [slashQuery, setSlashQuery] = useState("");
  const [focusedIndex, setFocusedIndex] = useState(0);
  const [planMode, togglePlanMode] = useToggle(false);
  const [thinkingOpen, setThinkingOpen] = useState(false);
  const [thinkingBudget, setThinkingBudget] = useState<"x-high" | "high" | "medium" | "low">("medium");
  const [fastMode, toggleFastMode] = useToggle(false);
  const [attachedImages, setAttachedImages] = useState<ImagePart[]>([]);
  const [isDragOver, setIsDragOver] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const {
    aiProviders,
    setThreadModelId,
    loadAiProviders,
    sendMessage,
    streamingThreadIds,
    selectedIssueId,
    repositoryGroups,
    getEffectiveModelId,
    messagesByThread,
  } = useAgentsStore();

  const { data: installedSkills = [] } = useQuery({
    queryKey: queryKeys.skills(),
    queryFn: () => invoke<InstalledSkill[]>("sync_skills", { workspacePath: null }),
  });

  useEffect(() => {
    loadAiProviders();
  }, [loadAiProviders]);

  const selectedRepoId = repositoryGroups
    .flatMap((g) => g.repositories)
    .find((r) => r.issues.some((i) => i.id === selectedIssueId))?.id ?? "";

  const effectiveModelId = getEffectiveModelId(selectedRepoId, selectedIssueId ?? "");

  const selectedModel = aiProviders
    .flatMap((p) => p.models)
    .find((m) => m.id === effectiveModelId);

  const contextWindow = selectedModel?.context_window ?? 0;
  const messages = messagesByThread[selectedIssueId ?? ""] ?? [];
  const usedTokens = useMemo(
    () => Math.round(messages.reduce((sum: number, m: { content: ChatMessage["content"] }) => sum + contentToText(m.content).length, 0) / 4),
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

  const readFileAsImagePart = useCallback((file: File): Promise<ImagePart | null> => {
    return new Promise((resolve) => {
      if (!file.type.startsWith("image/")) { resolve(null); return; }
      if (file.size > IMAGE_SIZE_LIMIT) {
        toast(`Image "${file.name}" exceeds the 5MB limit.`);
        resolve(null);
        return;
      }
      const reader = new FileReader();
      reader.onload = (e) => {
        const dataUrl = e.target?.result as string;
        const base64 = dataUrl.split(",")[1];
        resolve({ type: "image", data: base64, mediaType: file.type as ImageMediaType });
      };
      reader.onerror = () => resolve(null);
      reader.readAsDataURL(file);
    });
  }, []);

  const addImages = useCallback(async (files: FileList | File[]) => {
    const results = await Promise.all(Array.from(files).map(readFileAsImagePart));
    const valid = results.filter((p): p is ImagePart => p !== null);
    setAttachedImages((prev) => [...prev, ...valid]);
  }, [readFileAsImagePart]);

  const handlePaste = useCallback(async (e: React.ClipboardEvent<HTMLTextAreaElement>) => {
    const imageFiles = Array.from(e.clipboardData.items)
      .filter((item) => item.kind === "file" && item.type.startsWith("image/"))
      .map((item) => item.getAsFile())
      .filter((f): f is File => f !== null);
    if (imageFiles.length > 0) {
      e.preventDefault();
      await addImages(imageFiles);
    }
  }, [addImages]);

  const handleDrop = useCallback(async (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setIsDragOver(false);
    const files = Array.from(e.dataTransfer.files).filter((f) => f.type.startsWith("image/"));
    if (files.length > 0) await addImages(files);
  }, [addImages]);

  const removeImage = useCallback((index: number) => {
    setAttachedImages((prev) => prev.filter((_, i) => i !== index));
  }, []);
  const isCurrentThreadStreaming = !!streamingThreadIds[selectedIssueId ?? ""];
  const canSend = (message.trim().length > 0 || attachedImages.length > 0) && hasProviders && !!selectedIssueId;

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
          s.enabled &&
          (s.name.toLowerCase().includes(lowerQuery) ||
            s.description.toLowerCase().includes(lowerQuery)),
      )
      .map((s) => ({
        type: "skill",
        id: s.id,
        label: s.name,
        description: s.description,
        icon: undefined,
        textIcon: undefined,
        insertValue: `/${s.id} `,
      }));

    return [...commands, ...skills];
  }, [slashQuery]);

  // Reset focus when item list changes
  useEffect(() => {
    setFocusedIndex(0);
  }, [slashItems.length]);


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
    const text = message.trim();
    setMessage("");
    setAttachedImages([]);
    setSlashOpen(false);
    if (textareaRef.current) {
      textareaRef.current.style.height = "24px";
    }
    const opts: SendMessageOptions = {
      planMode,
      thinkingBudget: hasReasoning ? thinkingBudget : "not-available",
      fastMode,
    };

    if (attachedImages.length > 0) {
      const parts: import("@/types/agents").ContentPart[] = [];
      if (text) parts.push({ type: "text", text });
      parts.push(...attachedImages);
      await sendMessage(selectedIssueId!, parts, effectiveModelId!, undefined, opts);
    } else {
      await sendMessage(selectedIssueId!, text, effectiveModelId!, undefined, opts);
    }
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
    <div
      className="relative"
      onDragOver={(e) => { e.preventDefault(); setIsDragOver(true); }}
      onDragLeave={() => setIsDragOver(false)}
      onDrop={handleDrop}
    >
      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        multiple
        className="hidden"
        onChange={async (e) => {
          if (e.target.files) await addImages(e.target.files);
          e.target.value = "";
        }}
      />
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

      {isDragOver && (
        <div className="absolute inset-0 z-10 flex items-center justify-center rounded-xl border-2 border-dashed border-primary/50 bg-background/80 backdrop-blur-sm pointer-events-none">
          <div className="flex flex-col items-center gap-2 text-primary/70">
            <ImageIcon className="h-6 w-6" />
            <span className="text-[13px] font-medium">Drop image to attach</span>
          </div>
        </div>
      )}

      <Card className={cn("gap-0 p-0 transition-colors", isDragOver && "border-primary/50 dark:border-primary/40")}>
        <CardContent className="flex flex-col p-3 border-0">

          {attachedImages.length > 0 && (
            <div className="flex flex-wrap gap-2 px-1 pb-2">
              {attachedImages.map((img, i) => (
                <div key={i} className="relative group">
                  <img
                    src={`data:${img.mediaType};base64,${img.data}`}
                    alt=""
                    className="h-16 w-16 rounded-lg object-cover border border-border/40"
                  />
                  <button
                    type="button"
                    onClick={() => removeImage(i)}
                    className="absolute -top-1.5 -right-1.5 flex h-4 w-4 items-center justify-center rounded-full bg-zinc-800 border border-zinc-600 text-zinc-300 opacity-0 group-hover:opacity-100 transition-opacity"
                  >
                    <X className="h-2.5 w-2.5" />
                  </button>
                </div>
              ))}
            </div>
          )}

          <div className="flex items-center justify-between px-1">
            <div className="flex items-center gap-2 text-zinc-400">
              <button
                type="button"
                className="hover:text-foreground transition-colors p-1"
                onClick={() => fileInputRef.current?.click()}
                title="Attach image"
              >
                <ImageIcon className="h-4 w-4" />
              </button>

              {hasProviders ? (
                <ModelPicker
                  value={effectiveModelId}
                  onChange={(modelId) => {
                    if (selectedIssueId && modelId) {
                      setThreadModelId(selectedIssueId, modelId);
                    }
                  }}
                  variant="text"
                  emptyLabel={t("agents.chatInput.selectModel")}
                  align="start"
                />
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
              onPaste={handlePaste}
              placeholder={
                isCurrentThreadStreaming
                  ? t("agents.chatInput.placeholder.responding")
                  : hasProviders
                  ? t("agents.chatInput.placeholder.ready")
                  : t("agents.chatInput.placeholder.noProvider")
              }
              disabled={!hasProviders}
              className="w-full bg-transparent border-none outline-none focus:ring-0 text-[14px] font-medium text-foreground/90 placeholder:text-zinc-600 resize-none h-[24px] max-h-[160px] overflow-y-auto custom-scrollbar p-0 disabled:opacity-50"
              rows={1}
              onInput={(e) => {
                const target = e.target as HTMLTextAreaElement;
                target.style.height = "24px";
                target.style.height = `${Math.min(target.scrollHeight, 160)}px`;
              }}
            />
          </div>

        </CardContent>
      </Card>
    </div>
  );
}
