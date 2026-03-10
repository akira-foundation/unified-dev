import { Plus, Mic, ArrowUp, Cpu } from "lucide-react";
import { useState } from "react";
import { cn } from "@/lib/utils";

export function AgentChatInput() {
  const [message, setMessage] = useState("");

  return (
    <div className="px-8 pb-6 pt-2">
      <div className="flex flex-col gap-1 p-4 rounded-3xl bg-[#0D0D0D] border border-white/[0.05] shadow-2xl transition-all duration-300">
        {/* Top Metadata Row */}
        <div className="flex items-center gap-4 px-2 mb-2">
          <div className="flex items-center gap-2 text-[10px] font-bold text-muted-foreground/30 uppercase tracking-[0.2em]">
            <Cpu className="h-3 w-3" />
            <span>GPT 5.3 Codex</span>
          </div>
          <button className="text-muted-foreground/30 hover:text-purple-400 transition-colors">
            <Mic className="h-3 w-3" />
          </button>

          <div className="ml-auto text-[10px] font-bold text-muted-foreground/20 uppercase tracking-widest tabular-nums">
            2281k
          </div>
        </div>

        {/* Input/Action Row */}
        <div className="flex items-center gap-3">
          <button className="flex h-10 w-10 items-center justify-center rounded-xl text-muted-foreground/40 hover:bg-white/[0.03] hover:text-foreground transition-all shrink-0">
            <Plus className="h-5 w-5" />
          </button>

          <div className="flex-1 relative flex items-center bg-transparent border border-white/[0.05] rounded-xl px-4 py-2 hover:border-white/10 focus-within:border-purple-500/50 transition-all duration-300">
            <textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder="Ask to make changes..."
              className="flex-1 bg-transparent border-none focus:ring-0 text-[14px] font-medium text-white/80 placeholder:text-muted-foreground/30 py-1 resize-none h-[32px] custom-scrollbar"
              rows={1}
              onInput={(e) => {
                const target = e.target as HTMLTextAreaElement;
                target.style.height = '32px';
                target.style.height = `${target.scrollHeight}px`;
              }}
            />
          </div>

          <button
            disabled={!message.trim()}
            className={cn(
              "flex h-10 w-10 items-center justify-center rounded-full transition-all duration-300 shrink-0",
              message.trim()
                ? "bg-purple-600 text-white shadow-[0_0_15px_rgba(168,85,247,0.3)]"
                : "bg-white/[0.03] text-muted-foreground/20 cursor-not-allowed"
            )}
          >
            <ArrowUp className="h-5 w-5" />
          </button>
        </div>
      </div>
    </div>
  );
}
