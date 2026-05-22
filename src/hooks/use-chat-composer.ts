import { useState, useEffect, useRef, useMemo, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useQuery } from "@tanstack/react-query";

import { useChatHistory } from "@/hooks/useChatHistory";
import { useImageAttachments } from "@/hooks/use-image-attachments";
import { useToggle } from "@uidotdev/usehooks";
import { useAgentsStore } from "@/stores/useAgentsStore";
import type { SendMessageOptions, InstalledSkill, ChatMessage } from "@/stores/useAgentsStore";
import type { ContentPart } from "@/types/agents";
import { contentToText } from "@/types/agents";
import { slashCommands } from "@/lib/skills-data";
import { queryKeys } from "@/lib/query-keys";
import type { SlashItem } from "@/components/agents/slash-menu";

type ThinkingBudget = "x-high" | "high" | "medium" | "low";

export function useChatComposer() {
  const [message, setMessage] = useState("");
  const [slashOpen, setSlashOpen] = useState(false);
  const [slashQuery, setSlashQuery] = useState("");
  const [focusedIndex, setFocusedIndex] = useState(0);
  const [planMode, togglePlanMode] = useToggle(false);
  const [thinkingOpen, setThinkingOpen] = useState(false);
  const [thinkingBudget, setThinkingBudget] = useState<ThinkingBudget>("medium");
  const [fastMode, toggleFastMode] = useToggle(false);
  const {
    attachedImages,
    addImages,
    handlePaste,
    handleDrop,
    removeImage,
    clearImages,
    isDragOver,
    setIsDragOver,
  } = useImageAttachments();
  const history = useChatHistory();
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

  useEffect(() => {
    setFocusedIndex(0);
  }, [slashItems.length]);

  const handleChange = useCallback((value: string) => {
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
  }, []);

  const handleSlashSelect = useCallback((value: string) => {
    setMessage(value);
    setSlashOpen(false);
    setSlashQuery("");
    setFocusedIndex(0);
    textareaRef.current?.focus();
  }, []);

  const handleSend = useCallback(async () => {
    if (!canSend) return;
    const text = message.trim();
    if (text) {
      history.pushEntry(text);
    }
    setMessage("");
    clearImages();
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
      const parts: ContentPart[] = [];
      if (text) parts.push({ type: "text", text });
      parts.push(...attachedImages);
      await sendMessage(selectedIssueId!, parts, effectiveModelId!, undefined, opts);
    } else {
      await sendMessage(selectedIssueId!, text, effectiveModelId!, undefined, opts);
    }
  }, [canSend, message, history, planMode, hasReasoning, thinkingBudget, fastMode, attachedImages, clearImages, sendMessage, selectedIssueId, effectiveModelId]);

  const handleKeyDown = useCallback((e: React.KeyboardEvent<HTMLTextAreaElement>) => {
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

    const target = e.currentTarget;
    const cursorAtStart = target.selectionStart === 0 && target.selectionEnd === 0;
    const onFirstLine = !target.value.slice(0, target.selectionStart).includes("\n");
    const onLastLine = !target.value.slice(target.selectionEnd).includes("\n");

    if (e.key === "ArrowUp" && cursorAtStart && onFirstLine) {
      const prev = history.navigatePrev(message);
      if (prev !== null) {
        e.preventDefault();
        setMessage(prev);
        requestAnimationFrame(() => {
          if (textareaRef.current) {
            textareaRef.current.selectionStart = prev.length;
            textareaRef.current.selectionEnd = prev.length;
          }
        });
      }
      return;
    }

    if (e.key === "ArrowDown" && history.isNavigating && onLastLine) {
      const next = history.navigateNext();
      if (next !== null) {
        e.preventDefault();
        setMessage(next);
        requestAnimationFrame(() => {
          if (textareaRef.current) {
            textareaRef.current.selectionStart = next.length;
            textareaRef.current.selectionEnd = next.length;
          }
        });
      }
      return;
    }

    if (e.key === "Escape" && history.isNavigating) {
      e.preventDefault();
      history.reset();
      setMessage("");
      return;
    }

    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  }, [slashOpen, slashItems, focusedIndex, handleSlashSelect, history, message, handleSend]);

  return {
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
  };
}
