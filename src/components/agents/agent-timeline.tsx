import { CheckCircle2, Loader2, AlertCircle, Info, User, Bot, Copy, Check as CheckIcon } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import { oneDark } from "react-syntax-highlighter/dist/esm/styles/prism";
import { cn } from "@/lib/utils";
import type { AgentTimelineStep } from "@/types/agents";
import type { ChatMessage } from "@/stores/useAgentsStore";

interface AgentTimelineProps {
  steps: AgentTimelineStep[];
  messages: ChatMessage[];
  streamingContent: string;
  isStreaming: boolean;
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
    <div className="relative my-3 rounded-xl overflow-hidden border border-white/[0.06]">
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

export function AgentTimeline({ steps, messages, streamingContent, isStreaming }: AgentTimelineProps) {
  const bottomRef = useRef<HTMLDivElement>(null);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, streamingContent]);

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
    <div className="flex flex-col gap-6 p-8 relative">
      {/* Legacy timeline steps — shown when there are no real messages yet */}
      {!hasContent && (
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
      {messages.map((msg) => (
        <div
          key={msg.id}
          className={cn(
            "flex gap-4",
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
            "flex flex-col gap-1 max-w-[80%]",
            msg.role === "user" ? "items-end" : "items-start"
          )}>
            <div className={cn(
              "rounded-2xl px-4 py-3 text-[14px]",
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
      ))}

      {/* Live streaming bubble */}
      {isStreaming && (
        <div className="flex gap-4 flex-row">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border border-border/10 shadow-sm bg-white dark:bg-zinc-900 text-zinc-400">
            <Bot className="h-4 w-4" />
          </div>
          <div className="flex flex-col gap-2 max-w-[80%] items-start">
            {streamingContent && (
              <div className="rounded-2xl rounded-tl-sm px-4 py-3 text-[14px] bg-white/[0.04] text-white/80">
                <MessageMarkdown content={streamingContent} />
              </div>
            )}
            <span className="flex items-center gap-2 px-1 text-[12px] text-zinc-500">
              <span className="relative flex h-1.5 w-1.5">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-blue-400 opacity-75" />
                <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-blue-500" />
              </span>
              Working... {elapsedSeconds}s
            </span>
          </div>
        </div>
      )}

      <div ref={bottomRef} />
    </div>
  );
}
