import { useEffect, useRef } from "react";
import { Terminal, Zap } from "lucide-react";

import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";

export interface SlashItem {
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

export function SlashMenu({ query, focusedIndex, onSelect, items }: SlashMenuProps) {
  const { t } = useI18n();
  const itemRefs = useRef<(HTMLButtonElement | null)[]>([]);

  useEffect(() => {
    itemRefs.current[focusedIndex]?.scrollIntoView({ block: "nearest" });
  }, [focusedIndex]);

  if (items.length === 0) {
    return (
      <div className="rounded-xl border-border border bg-popover shadow-lg p-3 text-[12px] text-zinc-500">
        {t("agents.chatInput.slash.noMatch")} <span className="text-foreground/60">/{query}</span>
      </div>
    );
  }

  const commands = items.filter((i) => i.type === "command");
  const skills = items.filter((i) => i.type === "skill");

  let globalIndex = 0;

  return (
    <div className="rounded-xl border-border border bg-popover shadow-lg overflow-hidden max-h-72 overflow-y-auto">
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
