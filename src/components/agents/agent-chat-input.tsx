import { Plus, Mic, ArrowUp, GitBranch } from "lucide-react";
import { useState } from "react";
import { cn } from "@/lib/utils";

export function AgentChatInput() {
  const [message, setMessage] = useState("");

  return (
    <div className="px-6 pb-6 pt-2">
      <div className="flex flex-col p-3 rounded-2xl bg-[#1c1c1c] border border-white/[0.04] shadow-2xl transition-all duration-300">

        {/* Top Header Row */}
        <div className="flex items-center justify-between px-1">
          <div className="flex items-center gap-4 text-zinc-400">
            <button className="hover:text-white transition-colors p-1">
              <Plus className="h-4 w-4" />
            </button>
            <button className="flex items-center gap-2 hover:text-white transition-colors group">
              <GitBranch className="h-3.5 w-3.5 group-hover:text-purple-400 transition-colors" />
              <span className="text-[13px] font-medium">GPT 5.3 Codex</span>
            </button>
            <button className="hover:text-white transition-colors p-1">
              <Mic className="h-4 w-4" />
            </button>
            <span className="text-[12.5px] font-medium tracking-wide">
              2842k
            </span>
          </div>

          <button
            disabled={!message.trim()}
            className={cn(
              "flex h-8 w-8 items-center justify-center rounded-lg transition-all duration-300 shrink-0",
              message.trim()
                ? "bg-white/10 text-white hover:bg-white/20"
                : "bg-white/[0.03] text-zinc-500 cursor-not-allowed"
            )}
          >
            <ArrowUp className="h-4 w-4" />
          </button>
        </div>

        {/* Input Area */}
        <div className="mt-2.5 px-1 pb-1">
          <textarea
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            placeholder="Ask to make changes..."
            className="w-full bg-transparent border-none outline-none focus:ring-0 text-[14px] font-medium text-white/90 placeholder:text-zinc-500 resize-none h-[24px] custom-scrollbar p-0"
            rows={1}
            onInput={(e) => {
              const target = e.target as HTMLTextAreaElement;
              target.style.height = '24px';
              target.style.height = `${target.scrollHeight}px`;
            }}
          />
        </div>

      </div>
    </div>
  );
}
