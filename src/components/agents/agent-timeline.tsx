import { CheckCircle2, Loader2, AlertCircle, Info, User, Bot, Copy, Check as CheckIcon, ChevronDown, ChevronRight } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import { oneDark } from "react-syntax-highlighter/dist/esm/styles/prism";
import { cn } from "@/lib/utils";
import type { AgentTimelineStep } from "@/types/agents";
import { parseContent } from "@/types/agents";
import type { ChatMessage, ToolCallEvent } from "@/stores/useAgentsStore";
import { useI18n } from "@/i18n/i18n";
import { elapsedSecondsSince } from "@/lib/elapsed";
import { useToggle } from "@uidotdev/usehooks";

interface AgentTimelineProps {
  steps: AgentTimelineStep[];
  messages: ChatMessage[];
  streamingContent: string;
  isStreaming: boolean;
  toolCalls: ToolCallEvent[];
  isLoadingMessages?: boolean;
  streamStartedAt?: number;
}

function CodeBlock({ language, children }: { language: string; children: string }) {
  const { t } = useI18n();
  const [copied, setCopied] = useState(false);

  function handleCopy() {
    navigator.clipboard.writeText(children).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }

  return (
    <div className="relative my-3 rounded-xl overflow-hidden dark:border-white/[0.06] border-border border w-full">
      <div className="flex items-center justify-between px-4 py-1.5 dark:bg-zinc-800/80 bg-zinc-100 dark:border-white/[0.06] border-b border-zinc-200">
        <span className="text-[11px] font-mono text-zinc-400">{language || "text"}</span>
        <button
          onClick={handleCopy}
          className="flex items-center gap-1.5 text-[11px] text-zinc-500 hover:text-zinc-300 transition-colors"
        >
          {copied
            ? <><CheckIcon className="h-3 w-3 text-emerald-400" /> {t("common.copied")}</>
            : <><Copy className="h-3 w-3" /> {t("common.copy")}</>
          }
        </button>
      </div>
      <SyntaxHighlighter
        language={language || "text"}
        style={oneDark}
        customStyle={{
          margin: 0,
          borderRadius: 0,
          background: "#18181b",
          padding: "1rem",
          fontSize: "13px",
          lineHeight: "1.6",
        }}
        codeTagProps={{ style: { fontFamily: "ui-monospace, monospace" } }}
      >
        {children}
      </SyntaxHighlighter>
    </div>
  );
}

function ToolCallBlock({ toolCall }: { toolCall: ToolCallEvent }) {
  const [expanded, toggleExpanded] = useToggle(false);
  const hasOutput = !!toolCall.output;

  return (
    <div className="flex items-start gap-2 text-[12px]">
      <div className="mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center">
        {toolCall.status === "running" && (
          <Loader2 className="h-3 w-3 text-blue-400 animate-spin" />
        )}
        {toolCall.status === "done" && (
          <CheckIcon className="h-3 w-3 text-emerald-400" />
        )}
        {toolCall.status === "error" && (
          <AlertCircle className="h-3 w-3 text-red-400" />
        )}
      </div>
      <div className="min-w-0 flex-1">
        <button
          className="flex items-center gap-1 font-mono text-zinc-500 dark:text-zinc-400 dark:hover:text-zinc-300 hover:text-zinc-600 transition-colors"
          onClick={() => hasOutput && toggleExpanded()}
        >
          <span className="truncate">{toolCall.label}</span>
          {hasOutput && (
            expanded
              ? <ChevronDown className="h-3 w-3 shrink-0" />
              : <ChevronRight className="h-3 w-3 shrink-0" />
          )}
        </button>
        {expanded && toolCall.output && (
          <pre className="mt-1.5 max-h-48 overflow-auto rounded-lg dark:bg-zinc-900 bg-zinc-100 px-3 py-2 text-[11px] dark:text-zinc-300 text-zinc-700 leading-relaxed whitespace-pre-wrap break-words dark:border-white/[0.05] border border-zinc-200">
            {toolCall.output}
          </pre>
        )}
      </div>
    </div>
  );
}

function MessageMarkdown({ content }: { content: string }) {
  return (
    <ReactMarkdown
      remarkPlugins={[remarkGfm]}
      components={{
        p: ({ children }) => (
          <p className="mb-2 last:mb-0 leading-relaxed">{children}</p>
        ),
        code: ({ children, className }) => {
          const match = /language-(\w+)/.exec(className || "");
          const language = match?.[1] ?? "";
          const isBlock = !!match;
          if (isBlock) {
            return (
              <CodeBlock language={language}>
                {String(children).replace(/\n$/, "")}
              </CodeBlock>
            );
          }
          return (
            <code className="rounded px-1.5 py-0.5 text-[13px] dark:bg-white/[0.08] bg-black/[0.08] dark:text-purple-300 text-purple-600 font-mono">
              {children}
            </code>
          );
        },
        pre: ({ children }) => <>{children}</>,
        ul: ({ children }) => (
          <ul className="my-2 ml-4 list-disc space-y-1">{children}</ul>
        ),
        ol: ({ children }) => (
          <ol className="my-2 ml-4 list-decimal space-y-1">{children}</ol>
        ),
        li: ({ children }) => (
          <li className="leading-relaxed">{children}</li>
        ),
        strong: ({ children }) => (
          <strong className="font-semibold text-foreground/95">{children}</strong>
        ),
        em: ({ children }) => (
          <em className="italic text-foreground/70">{children}</em>
        ),
        blockquote: ({ children }) => (
          <blockquote className="my-2 border-l-2 border-purple-400/40 pl-3 text-foreground/50 italic">
            {children}
          </blockquote>
        ),
        h1: ({ children }) => (
          <h1 className="mt-4 mb-2 text-[15px] font-bold text-foreground/95">{children}</h1>
        ),
        h2: ({ children }) => (
          <h2 className="mt-3 mb-1.5 text-[14px] font-semibold text-foreground/90">{children}</h2>
        ),
        h3: ({ children }) => (
          <h3 className="mt-2 mb-1 text-[13px] font-semibold text-foreground/85">{children}</h3>
        ),
        a: ({ href, children }) => (
          <a href={href} target="_blank" rel="noopener noreferrer" className="text-purple-400 underline underline-offset-2 hover:text-purple-300">
            {children}
          </a>
        ),
        table: ({ children }) => (
          <div className="my-3 w-full overflow-x-auto rounded-xl dark:border-white/[0.06] border border-zinc-200">
            <table className="w-full text-[13px] border-collapse">{children}</table>
          </div>
        ),
        thead: ({ children }) => (
          <thead className="dark:bg-zinc-800/60 bg-zinc-100">{children}</thead>
        ),
        tbody: ({ children }) => (
          <tbody className="divide-y dark:divide-white/[0.04] divide-zinc-200">{children}</tbody>
        ),
        tr: ({ children }) => (
          <tr className="dark:hover:bg-white/[0.02] hover:bg-black/[0.02] transition-colors">{children}</tr>
        ),
        th: ({ children }) => (
          <th className="px-3 py-2 text-left text-[11px] font-semibold uppercase tracking-wide text-zinc-500 dark:text-zinc-400 whitespace-nowrap">
            {children}
          </th>
        ),
        td: ({ children }) => (
          <td className="px-3 py-2 text-foreground/75 align-top">{children}</td>
        ),
      }}
    >
      {content}
    </ReactMarkdown>
  );
}

function MessageContent({ content }: { content: ChatMessage["content"] }) {
  const parts = typeof content === "string" ? parseContent(content) : content;

  if (typeof parts === "string") {
    return <MessageMarkdown content={parts} />;
  }

  return (
    <div className="flex flex-col gap-2">
      {parts.map((part, i) => {
        if (part.type === "image") {
          return (
            <img
              key={i}
              src={`data:${part.mediaType};base64,${part.data}`}
              alt=""
              className="max-h-64 max-w-full rounded-lg object-contain border border-border/20"
            />
          );
        }
        return <MessageMarkdown key={i} content={part.text} />;
      })}
    </div>
  );
}

function MessageSkeleton({ role }: { role: "user" | "assistant" }) {
  return (
    <div className={cn("flex gap-4 min-w-0", role === "user" ? "flex-row-reverse" : "flex-row")}>
      <div className={cn(
        "flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border border-border/10",
        role === "user" ? "bg-purple-500/10" : "bg-white dark:bg-zinc-900",
        "animate-pulse"
      )} />
      <div className={cn(
        "flex flex-col gap-2 min-w-0",
        role === "user" ? "items-end max-w-[80%]" : "items-start w-full"
      )}>
        <div className={cn(
          "rounded-2xl px-4 py-3 animate-pulse",
          role === "user"
            ? "bg-purple-500/10 rounded-tr-sm"
            : "dark:bg-white/[0.04] bg-black/[0.04] rounded-tl-sm w-full"
        )}>
          <div className="h-3.5 rounded-full bg-current opacity-10 w-48 mb-2" />
          <div className="h-3.5 rounded-full bg-current opacity-10 w-64 mb-2" />
          {role === "assistant" && <div className="h-3.5 rounded-full bg-current opacity-10 w-40" />}
        </div>
        <div className="h-2.5 w-12 rounded-full bg-current opacity-5 mx-1" />
      </div>
    </div>
  );
}

function formatElapsed(seconds: number): string {
  if (seconds < 60) return `${seconds}s`;
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  if (m < 60) return s === 0 ? `${m}m` : `${m}m ${s}s`;
  const h = Math.floor(m / 60);
  const remM = m % 60;
  return `${h}h ${remM}m`;
}

export function AgentTimeline({ steps, messages, streamingContent, isStreaming, toolCalls, isLoadingMessages = false, streamStartedAt }: AgentTimelineProps) {
  const { t } = useI18n();
  const bottomRef = useRef<HTMLDivElement>(null);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "auto" });
  }, [streamingContent]);

  useEffect(() => {
    if (!isStreaming || !streamStartedAt) {
      setElapsedSeconds(0);
      return;
    }
    const tick = () => setElapsedSeconds(elapsedSecondsSince(streamStartedAt, Date.now()));
    tick();
    const interval = setInterval(tick, 1000);
    return () => clearInterval(interval);
  }, [isStreaming, streamStartedAt]);

  const hasContent = messages.length > 0 || isStreaming;

  if (isLoadingMessages && messages.length === 0) {
    return (
      <div className="flex flex-col gap-6">
        <MessageSkeleton role="user" />
        <MessageSkeleton role="assistant" />
        <MessageSkeleton role="user" />
        <MessageSkeleton role="assistant" />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      {!hasContent && steps.length === 0 && (
        <div className="flex flex-col items-center justify-center gap-4 py-32 text-center select-none">
          <div className="flex h-20 w-20 items-center justify-center rounded-3xl dark:bg-white/[0.04] bg-black/[0.04] dark:border-white/[0.06] border-black/[0.06] border">
            <Bot className="h-10 w-10 text-zinc-500" />
          </div>
          <div className="flex flex-col gap-1.5">
            <p className="text-[17px] font-semibold text-zinc-300 dark:text-zinc-300 text-foreground/70">{t("agents.timeline.ready")}</p>
            <p className="text-[14px] text-zinc-500">{t("agents.timeline.readyDescription")}</p>
          </div>
        </div>
      )}

      {!hasContent && steps.length > 0 && (
        <>
          <div className="absolute left-[56px] top-12 bottom-12 w-px bg-gradient-to-b from-zinc-200 via-zinc-200 to-transparent dark:from-zinc-800 dark:via-zinc-800 dark:to-transparent" />
          {steps.map((step) => (
            <div key={step.id} className="flex gap-6 group">
              <div className="relative z-10 flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-white dark:bg-zinc-900 border border-border/10 shadow-sm group-hover:scale-105 transition-transform duration-300">
                {step.status === "completed" && <CheckCircle2 className="h-5 w-5 text-emerald-500" />}
                {step.status === "running" && <Loader2 className="h-5 w-5 text-blue-500 animate-spin" />}
                {step.status === "warning" && <AlertCircle className="h-5 w-5 text-amber-500" />}
                {step.status === "error" && <AlertCircle className="h-5 w-5 text-destructive" />}
                {step.status === "info" && <Info className="h-5 w-5 text-zinc-400" />}
              </div>
              <div className="flex flex-col gap-1.5 flex-1 pt-1.5">
                <div className="flex items-center justify-between gap-4">
                  <span className={cn(
                    "text-sm font-bold tracking-tight",
                    step.status === "running" ? "text-foreground" : "text-foreground/80"
                  )}>
                    {step.message}
                  </span>
                  <span className="text-[10px] font-medium text-muted-foreground/40 tabular-nums uppercase tracking-widest">
                    {step.timestamp}
                  </span>
                </div>
                {step.details && (
                  <div className="rounded-xl bg-zinc-50 dark:bg-zinc-900/50 p-3 border border-border/5 text-xs text-muted-foreground leading-relaxed">
                    {step.details}
                  </div>
                )}
              </div>
            </div>
          ))}
        </>
      )}

      {messages.map((msg) => {
        if (msg.role === "tool") {
          return (
            <div key={msg.id} className="flex flex-col gap-1">
              <div className="rounded-xl overflow-hidden dark:border-white/[0.06] border border-zinc-200 w-full">
                <div className="flex items-center gap-2 px-3 py-1.5 dark:bg-zinc-800/80 bg-zinc-100 dark:border-white/[0.06] border-b border-zinc-200">
                  <span className="text-[11px] font-mono text-zinc-400">{t("agents.timeline.output")}</span>
                </div>
                <pre className="p-3 text-[12px] font-mono dark:text-zinc-300 text-zinc-700 leading-relaxed overflow-x-auto whitespace-pre-wrap break-words dark:bg-[#18181b] bg-zinc-50">
                  {typeof msg.content === "string" ? msg.content : JSON.stringify(msg.content)}
                </pre>
              </div>
              <span className="text-[10px] text-muted-foreground/30 px-1">
                {new Date(msg.created_at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
              </span>
            </div>
          );
        }

        return (
        <div
          key={msg.id}
          className={cn(
            "flex gap-4 min-w-0",
            msg.role === "user" ? "flex-row-reverse" : "flex-row"
          )}
        >
          <div className={cn(
            "flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border border-border/10 shadow-sm",
            msg.role === "user"
              ? "bg-purple-500/10 text-purple-400"
              : "bg-white dark:bg-zinc-900 text-zinc-400"
          )}>
            {msg.role === "user"
              ? <User className="h-4 w-4" />
              : <Bot className="h-4 w-4" />
            }
          </div>

          <div className={cn(
            "flex flex-col gap-1 min-w-0",
            msg.role === "user" ? "items-end max-w-[80%]" : "items-start w-full"
          )}>
            <div className={cn(
              "rounded-2xl px-4 py-3 text-[14px] min-w-0 w-full overflow-hidden",
              msg.role === "user"
                ? "bg-purple-500/10 text-foreground/90 rounded-tr-sm"
                : "dark:bg-white/[0.04] bg-black/[0.04] text-foreground/80 rounded-tl-sm"
            )}>
              <MessageContent content={msg.content} />
            </div>
            <span className="text-[10px] text-muted-foreground/30 px-1">
              {new Date(msg.created_at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
              {msg.model && msg.role === "assistant" && (
                <> · {msg.model}</>
              )}
            </span>
          </div>
        </div>
        );
      })}

      {isStreaming && (
        <div className="flex gap-4 flex-row">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border border-border/10 shadow-sm bg-white dark:bg-zinc-900 text-zinc-400 animate-pulse">
            <Bot className="h-4 w-4" />
          </div>
          <div className="flex flex-col gap-2 items-start w-full min-w-0">
            {toolCalls.length > 0 && (
              <div className="w-full rounded-xl dark:border-white/[0.05] border border-zinc-200 dark:bg-zinc-900/60 bg-zinc-100 px-3 py-2.5 flex flex-col gap-1.5">
                {toolCalls.map((tc) => (
                  <ToolCallBlock key={tc.id} toolCall={tc} />
                ))}
              </div>
            )}
            {streamingContent && (
              <div className="rounded-2xl rounded-tl-sm px-4 py-3 text-[14px] dark:bg-white/[0.04] bg-black/[0.04] text-foreground/80 w-full overflow-hidden">
                <MessageMarkdown content={streamingContent} />
              </div>
            )}
            <span className="flex items-center gap-2 px-1 text-[12px] text-zinc-500">
              <span className="relative flex h-1.5 w-1.5">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-blue-400 opacity-75" />
                <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-blue-500" />
              </span>
              {t("agents.timeline.working")} {formatElapsed(elapsedSeconds)}
            </span>
          </div>
        </div>
      )}

      <div ref={bottomRef} />
    </div>
  );
}
