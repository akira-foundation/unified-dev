import { Plus, Mic, ArrowUp, ChevronDown, AlertCircle } from "lucide-react";
import { useState, useEffect } from "react";
import { cn } from "@/lib/utils";
import { useAgentsStore } from "@/stores/useAgentsStore";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

export function AgentChatInput() {
  const [message, setMessage] = useState("");
  const { aiProviders, selectedModelId, setSelectedModelId, loadAiProviders } = useAgentsStore();

  useEffect(() => {
    loadAiProviders();
  }, [loadAiProviders]);

  const selectedModel = aiProviders
    .flatMap((p) => p.models)
    .find((m) => m.id === selectedModelId);

  const hasProviders = aiProviders.length > 0;

  return (
    <div className="px-6 pb-6 pt-2">
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

      <div className="flex flex-col p-3 rounded-2xl bg-[#1c1c1c] border border-white/[0.04] shadow-2xl transition-all duration-300">

        {/* Top Header Row */}
        <div className="flex items-center justify-between px-1">
          <div className="flex items-center gap-4 text-zinc-400">
            <button className="hover:text-white transition-colors p-1">
              <Plus className="h-4 w-4" />
            </button>

            {hasProviders ? (
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <button className="flex items-center gap-2 hover:text-white transition-colors group outline-none">
                    <span className="text-[13px] font-medium">
                      {selectedModel?.label ?? "Select model"}
                    </span>
                    <ChevronDown className="h-3 w-3 opacity-50 group-hover:opacity-100 transition-opacity" />
                  </button>
                </DropdownMenuTrigger>
                <DropdownMenuContent
                  align="start"
                  className="w-64 bg-[#0F0F0F] border-white/[0.05] p-2 shadow-2xl rounded-xl backdrop-blur-3xl"
                >
                  {aiProviders.map((provider, index) => (
                    <div key={provider.name}>
                      {index > 0 && <DropdownMenuSeparator className="bg-white/[0.03] my-1.5" />}
                      <DropdownMenuLabel className="text-[10px] font-black uppercase tracking-[0.15em] text-zinc-500 px-3 py-2">
                        {provider.name}
                      </DropdownMenuLabel>
                      {provider.models.map((model) => (
                        <DropdownMenuItem
                          key={model.id}
                          onClick={() => setSelectedModelId(model.id)}
                          className={cn(
                            "flex items-center gap-3 px-3 py-2.5 rounded-lg cursor-pointer transition-all text-[13px] font-medium",
                            selectedModelId === model.id
                              ? "bg-purple-500/10 text-purple-400"
                              : "text-zinc-300 focus:bg-white/[0.03] hover:text-white"
                          )}
                        >
                          <div className={cn(
                            "h-1.5 w-1.5 rounded-full shrink-0",
                            selectedModelId === model.id ? "bg-purple-400" : "bg-zinc-600"
                          )} />
                          {model.label}
                        </DropdownMenuItem>
                      ))}
                    </div>
                  ))}
                </DropdownMenuContent>
              </DropdownMenu>
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
            disabled={!message.trim() || !hasProviders}
            className={cn(
              "flex h-8 w-8 items-center justify-center rounded-lg transition-all duration-300 shrink-0",
              message.trim() && hasProviders
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
            placeholder={hasProviders ? "Ask to make changes..." : "Configure an AI provider to start..."}
            disabled={!hasProviders}
            className="w-full bg-transparent border-none outline-none focus:ring-0 text-[14px] font-medium text-white/90 placeholder:text-zinc-500 resize-none h-[24px] custom-scrollbar p-0 disabled:opacity-50"
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
