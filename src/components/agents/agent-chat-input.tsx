import { Mic, ArrowUp, AlertCircle, Square, X, ImageIcon } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Card, CardContent } from "@/components/ui/card";
import { ModelPicker } from "@/components/agents/model-picker";
import { AgentChangesBar } from "@/components/agents/agent-changes-bar";
import { SlashMenu } from "@/components/agents/slash-menu";
import { useChatComposer } from "@/hooks/use-chat-composer";
import { useAgentsStore } from "@/stores/useAgentsStore";

const thinkingLabels: Record<string, string> = {
  "x-high": "X-High",
  high: "High",
  medium: "Medium",
  low: "Low",
};

export function AgentChatInput() {
  const { t } = useI18n();
  const {
    message,
    handleChange,
    handleKeyDown,
    handlePaste,
    textareaRef,
    fileInputRef,
    slashOpen,
    slashQuery,
    focusedIndex,
    slashItems,
    handleSlashSelect,
    attachedImages,
    addImages,
    removeImage,
    isDragOver,
    setIsDragOver,
    handleDrop,
    planMode,
    togglePlanMode,
    supportsPlanMode,
    thinkingOpen,
    setThinkingOpen,
    thinkingBudget,
    setThinkingBudget,
    hasReasoning,
    fastMode,
    toggleFastMode,
    hasProviders,
    contextWindow,
    usedTokens,
    effectiveModelId,
    setThreadModelId,
    selectedIssueId,
    isCurrentThreadStreaming,
    canSend,
    handleSend,
  } = useChatComposer();
  const showChangesBar = useAgentsStore(
    (s) => s.fileChanges.length > 0 && !(s.isRightSidebarOpen && s.islandPanel === "diff"),
  );

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

      <AgentChangesBar />

      <Card className={cn("relative z-10 gap-0 bg-white p-0 transition-colors dark:bg-[#1c1c1c]", showChangesBar && "-mt-5", isDragOver && "border-primary/50 dark:border-primary/40")}>
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

          <div className="px-1 pt-1">
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

          <div className="flex items-center justify-between px-1 mt-2.5">
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
              <button
                type="button"
                onClick={() => toast.info(t("agents.chat.voiceComingSoon"))}
                className="hover:text-foreground text-zinc-400 transition-colors p-1"
              >
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

        </CardContent>
      </Card>
    </div>
  );
}
