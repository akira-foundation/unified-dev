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
  const cls = "h-4 w-4 shrink-0";
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
    default: return <span className="text-xs font-bold w-4 text-center">{icon}</span>;
  }
}

export interface SlashCommandMenuRef {
  onKeyDown: (event: KeyboardEvent) => boolean;
}

interface SlashCommandMenuProps {
  items: SlashCommandItem[];
  command: (item: SlashCommandItem) => void;
}

export const SlashCommandMenu = forwardRef<SlashCommandMenuRef, SlashCommandMenuProps>(
  ({ items, command }, ref) => {
    const [selectedIndex, setSelectedIndex] = useState(0);

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
      <div className="z-50 w-56 overflow-hidden rounded-xl border border-border bg-popover shadow-lg py-1">
        {items.map((item, index) => (
          <button
            key={item.id}
            type="button"
            className={`flex w-full items-center gap-2.5 px-3 py-1.5 text-sm transition-colors ${
              index === selectedIndex
                ? "bg-accent text-foreground [&_svg]:text-purple-400"
                : "text-muted-foreground hover:bg-accent hover:text-foreground"
            }`}
            onMouseEnter={() => setSelectedIndex(index)}
            onMouseDown={(e) => {
              e.preventDefault();
              command(item);
            }}
          >
            <span className="flex h-5 w-5 items-center justify-center text-muted-foreground">
              <ItemIcon icon={item.icon} />
            </span>
            <span>{item.title}</span>
          </button>
        ))}
      </div>
    );
  },
);

SlashCommandMenu.displayName = "SlashCommandMenu";
