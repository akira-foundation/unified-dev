import { forwardRef, useEffect, useImperativeHandle, useState } from "react";
import {
  List,
  ListOrdered,
  CheckSquare,
  Heading1,
  Heading2,
  Heading3,
  Code2,
  Quote,
  Bold,
  Italic,
  Strikethrough,
  Minus,
} from "lucide-react";
import type { SlashCommandItem } from "./slash-command-extension";

function ItemIcon({ icon }: { icon: string }) {
  const cls = "h-3.5 w-3.5 shrink-0";
  switch (icon) {
    case "H1": return <Heading1 className={cls} />;
    case "H2": return <Heading2 className={cls} />;
    case "H3": return <Heading3 className={cls} />;
    case "ul": return <List className={cls} />;
    case "ol": return <ListOrdered className={cls} />;
    case "check": return <CheckSquare className={cls} />;
    case "code": return <Code2 className={cls} />;
    case "quote": return <Quote className={cls} />;
    case "bold": return <Bold className={cls} />;
    case "italic": return <Italic className={cls} />;
    case "strike": return <Strikethrough className={cls} />;
    case "hr": return <Minus className={cls} />;
    default: return <span className="w-4 text-center font-sans text-[10px] font-semibold">{icon}</span>;
  }
}

export interface SlashCommandMenuRef {
  onKeyDown: (event: KeyboardEvent) => boolean;
}

interface SlashCommandMenuProps {
  items: SlashCommandItem[];
  command: (item: SlashCommandItem) => void;
}

const GROUP_ORDER = ["Text", "Lists", "Insert", "Format"] as const;

function formatShortcut(shortcut: string) {
  return shortcut
    .replace(/Cmd/g, "⌘")
    .replace(/Opt/g, "⌥")
    .replace(/Shift/g, "⇧")
    .replace(/Ctrl/g, "⌃")
    .replace(/\+/g, " ");
}

export const SlashCommandMenu = forwardRef<SlashCommandMenuRef, SlashCommandMenuProps>(
  ({ items, command }, ref) => {
    const [selectedIndex, setSelectedIndex] = useState(0);

    const groupedItems = GROUP_ORDER
      .map((group) => ({
        group,
        items: items.filter((item) => item.group === group),
      }))
      .filter((section) => section.items.length > 0);

    useEffect(() => {
      setSelectedIndex(0);
    }, [items]);

    useImperativeHandle(ref, () => ({
      onKeyDown(event: KeyboardEvent) {
        if (event.key === "ArrowUp") {
          setSelectedIndex((i) => (i - 1 + items.length) % items.length);
          return true;
        }
        if (event.key === "ArrowDown") {
          setSelectedIndex((i) => (i + 1) % items.length);
          return true;
        }
        if (event.key === "Enter") {
          const item = items[selectedIndex];
          if (item) command(item);
          return true;
        }
        return false;
      },
    }));

    if (items.length === 0) return null;

    return (
      <div className="z-50 w-[244px] overflow-hidden rounded-[10px] border border-white/10 bg-[#111111] p-1 font-sans shadow-2xl">
        {groupedItems.map((section, sectionIndex) => {
          const startIndex = groupedItems
            .slice(0, sectionIndex)
            .reduce((count, current) => count + current.items.length, 0);

          return (
            <div key={section.group}>
              {sectionIndex > 0 && <div className="mx-2 my-1 h-px bg-white/6" />}
              {section.items.map((item, index) => {
                const absoluteIndex = startIndex + index;

                return (
                  <button
                    key={item.id}
                    type="button"
                    className={`group flex w-full items-center gap-2 rounded-[6px] px-2 py-1.5 text-left transition-colors ${
                      absoluteIndex === selectedIndex
                        ? "bg-white/6 text-white"
                        : "text-zinc-300 hover:bg-white/4"
                    }`}
                    onMouseEnter={() => setSelectedIndex(absoluteIndex)}
                    onMouseDown={(e) => {
                      e.preventDefault();
                      command(item);
                    }}
                  >
                    <span className={`flex h-[22px] w-[22px] shrink-0 items-center justify-center text-zinc-500 ${
                      absoluteIndex === selectedIndex
                        ? "text-zinc-300"
                        : "text-zinc-500"
                    }`}>
                      <ItemIcon icon={item.icon} />
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[12.5px] font-medium leading-5 text-inherit">
                        {item.title}
                      </span>
                    </span>
                    {item.shortcut && (
                      <span className="shrink-0 text-[10px] font-medium tracking-[0.01em] text-zinc-500">
                        {formatShortcut(item.shortcut)}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
          );
        })}
      </div>
    );
  },
);

SlashCommandMenu.displayName = "SlashCommandMenu";
