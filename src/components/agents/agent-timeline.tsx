import { CheckCircle2, Loader2, AlertCircle, Info, User, Bot, Copy, Check as CheckIcon, ChevronDown, ChevronRight } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import { oneDark } from "react-syntax-highlighter/dist/esm/styles/prism";
import { cn } from "@/lib/utils";
import type { AgentTimelineStep } from "@/types/agents";
import type { ChatMessage, ToolCallEvent } from "@/stores/useAgentsStore";

interface AgentTimelineProps {
  steps: AgentTimelineStep[];
  messages: ChatMessage[];
  streamingContent: string;
  isStreaming: boolean;
  toolCalls: ToolCallEvent[];
}

function CodeBlock({ language, children }: { language: string; children: string }) {
  const [copied, setCopied] = useState(false);

  function handleCopy() {
    navigator.clipboard.writeText(children).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }

  return (
    <div className="relative my-3 rounded-xl overflow-hidden border border-white/[0.06] w-full">
      <div className="flex items-center justify-between px-4 py-1.5 bg-zinc-800/80 border-b border-white/[0.06]">
        <span className="text-[11px] font-mono text-zinc-400">{language || "text"}</span>
        <button
          onClick={handleCopy}
          className="flex items-center gap-1.5 text-[11px] text-zinc-500 hover:text-zinc-300 transition-colors"
        >
          {copied
            ? <><CheckIcon className="h-3 w-3 text-emerald-400" /> Copied</>
            : <><Copy className="h-3 w-3" /> Copy</>
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
  const [expanded, setExpanded] = useState(false);
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
          className="flex items-center gap-1 font-mono text-zinc-400 hover:text-zinc-300 transition-colors"
          onClick={() => hasOutput && setExpanded((v) => !v)}
        >
          <span className="truncate">{toolCall.label}</span>
          {hasOutput && (
            expanded
              ? <ChevronDown className="h-3 w-3 shrink-0" />
              : <ChevronRight className="h-3 w-3 shrink-0" />
          )}
        </button>
        {expanded && toolCall.output && (
          <pre className="mt-1.5 max-h-48 overflow-auto rounded-lg bg-zinc-900 px-3 py-2 text-[11px] text-zinc-300 leading-relaxed whitespace-pre-wrap break-words border border-white/[0.05]">
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
            <code className="rounded px-1.5 py-0.5 text-[13px] bg-white/[0.08] text-purple-300 font-mono">
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
          <strong className="font-semibold text-white/95">{children}</strong>
        ),
        em: ({ children }) => (
          <em className="italic text-white/70">{children}</em>
        ),
        blockquote: ({ children }) => (
          <blockquote className="my-2 border-l-2 border-purple-400/40 pl-3 text-white/50 italic">
            {children}
          </blockquote>
        ),
        h1: ({ children }) => (
          <h1 className="mt-4 mb-2 text-[15px] font-bold text-white/95">{children}</h1>
        ),
        h2: ({ children }) => (
          <h2 className="mt-3 mb-1.5 text-[14px] font-bold text-white/90">{children}</h2>
        ),
        h3: ({ children }) => (
          <h3 className="mt-2 mb-1 text-[13px] font-semibold text-white/85">{children}</h3>
        ),
        a: ({ href, children }) => (
          <a href={href} target="_blank" rel="noopener noreferrer" className="text-purple-400 underline underline-offset-2 hover:text-purple-300">
            {children}
          </a>
        ),
      }}
    >
      {content}
    </ReactMarkdown>
  );
}

export function AgentTimeline({ steps, messages, streamingContent, isStreaming, toolCalls }: AgentTimelineProps) {
  const bottomRef = useRef<HTMLDivElement>(null);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);

  // Scroll to bottom on new history messages (smooth) or streaming chunks (instant).
  // Using "smooth" on every streaming flush causes layout thrashing and visible flicker.
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "auto" });
  }, [streamingContent]);

  // Timer that counts up while streaming.
  useEffect(() => {
    if (!isStreaming) {
      setElapsedSeconds(0);
      return;
    }
    setElapsedSeconds(0);
    const interval = setInterval(() => setElapsedSeconds((s) => s + 1), 1000);
    return () => clearInterval(interval);
  }, [isStreaming]);

  const hasContent = messages.length > 0 || isStreaming;

  return (
    <div className="flex flex-col gap-6">
      {/* Legacy timeline steps — shown when there are no real messages yet */}
      {!hasContent && steps.length === 0 && (
        <div className="flex flex-col items-center justify-center gap-4 py-32 text-center select-none">
          <div className="flex h-20 w-20 items-center justify-center rounded-3xl bg-white/[0.04] border border-white/[0.06]">
            <Bot className="h-10 w-10 text-zinc-500" />
          </div>
          <div className="flex flex-col gap-1.5">
            <p className="text-[17px] font-semibold text-zinc-300">Thread ready</p>
            <p className="text-[14px] text-zinc-500">Describe what you want to build or fix.</p>
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

      {/* Chat messages */}
      {messages.map((msg) => {
        // Tool / command output — shown as a terminal block
        if (msg.role === "tool") {
          return (
            <div key={msg.id} className="flex flex-col gap-1">
              <div className="rounded-xl overflow-hidden border border-white/[0.06] w-full">
                <div className="flex items-center gap-2 px-3 py-1.5 bg-zinc-800/80 border-b border-white/[0.06]">
                  <span className="text-[11px] font-mono text-zinc-400">output</span>
                </div>
                <pre className="p-3 text-[12px] font-mono text-zinc-300 leading-relaxed overflow-x-auto whitespace-pre-wrap break-words bg-[#18181b]">
                  {msg.content}
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
          {/* Avatar */}
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

          {/* Bubble */}
          <div className={cn(
            "flex flex-col gap-1 min-w-0",
            msg.role === "user" ? "items-end max-w-[80%]" : "items-start w-full"
          )}>
            <div className={cn(
              "rounded-2xl px-4 py-3 text-[14px] min-w-0 w-full overflow-hidden",
              msg.role === "user"
                ? "bg-purple-500/10 text-white/90 rounded-tr-sm whitespace-pre-wrap leading-relaxed"
                : "bg-white/[0.04] text-white/80 rounded-tl-sm"
            )}>
              {msg.role === "user"
                ? msg.content
                : <MessageMarkdown content={msg.content} />
              }
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

      {/* Live streaming bubble */}
      {isStreaming && (
        <div className="flex gap-4 flex-row">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border border-border/10 shadow-sm bg-white dark:bg-zinc-900 text-zinc-400">
            <Bot className="h-4 w-4" />
          </div>
          <div className="flex flex-col gap-2 items-start w-full min-w-0">
            {/* Tool call steps */}
            {toolCalls.length > 0 && (
              <div className="w-full rounded-xl border border-white/[0.05] bg-zinc-900/60 px-3 py-2.5 flex flex-col gap-1.5">
                {toolCalls.map((tc) => (
                  <ToolCallBlock key={tc.id} toolCall={tc} />
                ))}
              </div>
            )}
            {streamingContent && (
              <div className="rounded-2xl rounded-tl-sm px-4 py-3 text-[14px] bg-white/[0.04] text-white/80 w-full overflow-hidden">
                <pre className="whitespace-pre-wrap font-sans leading-relaxed">{streamingContent}</pre>
              </div>
            )}
            {!streamingContent && toolCalls.length === 0 && (
              <span className="flex items-center gap-2 px-1 text-[12px] text-zinc-500">
                <span className="relative flex h-1.5 w-1.5">
                  <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-blue-400 opacity-75" />
                  <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-blue-500" />
                </span>
                Working... {elapsedSeconds}s
              </span>
            )}
          </div>
        </div>
      )}

      <div ref={bottomRef} />
    </div>
  );
}
