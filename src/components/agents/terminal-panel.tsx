import { useEffect, useRef, useCallback, useState } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { Plus, X, TerminalSquare, ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";
import "@xterm/xterm/css/xterm.css";

interface TerminalOutputPayload {
  session_id: string;
  data: number[];
}

interface TerminalTab {
  id: string;
  sessionId: string;
  label: string;
  terminal: Terminal;
  fitAddon: FitAddon;
  container: HTMLDivElement;
}

const XTERM_THEME = {
  background: "#0c0c0c",
  foreground: "#d4d4d8",
  cursor: "#a78bfa",
  selectionBackground: "#a78bfa33",
  black: "#18181b",
  red: "#f87171",
  green: "#4ade80",
  yellow: "#fbbf24",
  blue: "#60a5fa",
  magenta: "#c084fc",
  cyan: "#22d3ee",
  white: "#e4e4e7",
  brightBlack: "#52525b",
  brightRed: "#fca5a5",
  brightGreen: "#86efac",
  brightYellow: "#fde68a",
  brightBlue: "#93c5fd",
  brightMagenta: "#d8b4fe",
  brightCyan: "#67e8f9",
  brightWhite: "#fafafa",
};

interface TerminalPanelProps {
  onClose?: () => void;
  onMinimize?: () => void;
  cwd?: string;
}

export function TerminalPanel({ onClose, onMinimize, cwd }: TerminalPanelProps) {
  const hostRef = useRef<HTMLDivElement>(null);
  const tabsRef = useRef<TerminalTab[]>([]);
  const [tabs, setTabs] = useState<{ id: string; label: string; renamed: boolean }[]>([]);
  const [activeTabId, setActiveTabId] = useState<string | null>(null);
  const counterRef = useRef(0);
  const [editingTabId, setEditingTabId] = useState<string | null>(null);
  const [editValue, setEditValue] = useState("");

  const spawnTab = useCallback(async () => {
    if (!hostRef.current) return;

    const tabId = `t${++counterRef.current}`;

    const wrapper = document.createElement("div");
    wrapper.style.cssText = "position:absolute;inset:0;display:none;";
    hostRef.current.appendChild(wrapper);

    const term = new Terminal({
      fontSize: 13,
      fontFamily: "'JetBrains Mono', 'Fira Code', 'SF Mono', Menlo, monospace",
      lineHeight: 1.4,
      cursorBlink: true,
      cursorStyle: "bar",
      theme: XTERM_THEME,
    });

    const fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    term.open(wrapper);

    wrapper.style.display = "block";
    fitAddon.fit();

    const dims = fitAddon.proposeDimensions();

    try {
      const sessionId = await invoke<string>("terminal_spawn", {
        cwd: cwd ?? null,
        cols: dims?.cols ?? 120,
        rows: dims?.rows ?? 24,
      });

      const tab: TerminalTab = {
        id: tabId,
        sessionId,
        label: "zsh",
        terminal: term,
        fitAddon,
        container: wrapper,
      };

      term.onData((data) => {
        const encoder = new TextEncoder();
        invoke("terminal_write", {
          sessionId,
          data: Array.from(encoder.encode(data)),
        });
      });

      tabsRef.current.push(tab);
      setTabs((prev) => [...prev, { id: tabId, label: "zsh", renamed: false }]);
      setActiveTabId(tabId);
    } catch (err) {
      term.writeln(`\x1b[31mFailed to spawn: ${err}\x1b[0m`);
    }
  }, []);

  const closeTab = useCallback((tabId: string) => {
    const idx = tabsRef.current.findIndex((t) => t.id === tabId);
    if (idx === -1) return;

    const tab = tabsRef.current[idx];
    if (tab.sessionId) invoke("terminal_kill", { sessionId: tab.sessionId });
    tab.terminal.dispose();
    tab.container.remove();
    tabsRef.current.splice(idx, 1);

    setTabs((prev) => prev.filter((t) => t.id !== tabId));
    setActiveTabId((prev) => {
      if (prev !== tabId) return prev;
      const remaining = tabsRef.current;
      if (remaining.length === 0) {
        onClose?.();
        return null;
      }
      return remaining[remaining.length - 1].id;
    });
  }, []);

  const switchTab = useCallback((tabId: string) => {
    setActiveTabId(tabId);
  }, []);

  const renameTab = useCallback((tabId: string, newLabel: string) => {
    const trimmed = newLabel.trim();
    if (!trimmed) return;
    const ref = tabsRef.current.find((t) => t.id === tabId);
    if (ref) ref.label = trimmed;
    setTabs((prev) => prev.map((t) => t.id === tabId ? { ...t, label: trimmed, renamed: true } : t));
    setEditingTabId(null);
  }, []);

  const startRename = useCallback((tabId: string, currentLabel: string) => {
    setEditingTabId(tabId);
    setEditValue(currentLabel.trim());
  }, []);

  useEffect(() => {
    tabsRef.current.forEach((tab) => {
      const visible = tab.id === activeTabId;
      tab.container.style.display = visible ? "block" : "none";
      if (visible) {
        requestAnimationFrame(() => {
          tab.fitAddon.fit();
          tab.terminal.focus();
        });
      }
    });
  }, [activeTabId]);

  const mountedRef = useRef(false);
  useEffect(() => {
    if (mountedRef.current) return;
    mountedRef.current = true;
    spawnTab();
    return () => {
      tabsRef.current.forEach((tab) => {
        if (tab.sessionId) invoke("terminal_kill", { sessionId: tab.sessionId });
        tab.terminal.dispose();
        tab.container.remove();
      });
      tabsRef.current = [];
    };
  }, [spawnTab]);

  useEffect(() => {
    const unlisten = listen<TerminalOutputPayload>("terminal-output", (event) => {
      const tab = tabsRef.current.find((t) => t.sessionId === event.payload.session_id);
      if (tab) {
        tab.terminal.write(new Uint8Array(event.payload.data));
      }
    });
    return () => { unlisten.then((fn) => fn()); };
  }, []);

  useEffect(() => {
    if (!hostRef.current) return;

    const observer = new ResizeObserver(() => {
      const tab = tabsRef.current.find((t) => t.id === activeTabId);
      if (tab) {
        tab.fitAddon.fit();
        const dims = tab.fitAddon.proposeDimensions();
        if (dims && tab.sessionId) {
          invoke("terminal_resize", {
            sessionId: tab.sessionId,
            cols: dims.cols,
            rows: dims.rows,
          });
        }
      }
    });

    observer.observe(hostRef.current);
    return () => observer.disconnect();
  }, [activeTabId]);

  return (
    <div className="h-full w-full flex flex-col bg-background">
      <div className="flex items-center h-8 shrink-0 bg-background border-b border-white/[0.04] px-1 gap-0.5">
        {tabs.map((tab, i) => (
          <button
            key={tab.id}
            onClick={() => switchTab(tab.id)}
            onDoubleClick={() => startRename(tab.id, `${tab.label} ${i + 1}`)}
            className={cn(
              "flex items-center gap-1.5 h-6 px-2.5 rounded text-[11px] font-medium transition-colors group",
              tab.id === activeTabId
                ? "bg-white/[0.08] text-zinc-200"
                : "text-zinc-500 hover:text-zinc-400"
            )}
          >
            <TerminalSquare className="h-3 w-3 shrink-0" />
            {editingTabId === tab.id ? (
              <input
                autoFocus
                value={editValue}
                onChange={(e) => setEditValue(e.target.value)}
                onBlur={() => renameTab(tab.id, editValue)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") renameTab(tab.id, editValue);
                  if (e.key === "Escape") setEditingTabId(null);
                  e.stopPropagation();
                }}
                onClick={(e) => e.stopPropagation()}
                className="bg-transparent border-none outline-none text-[11px] font-medium text-zinc-200 w-16 px-0"
              />
            ) : (
              <span>{tab.renamed ? tab.label : `${tab.label} ${i + 1}`}</span>
            )}
            <span
              onClick={(e) => {
                e.stopPropagation();
                closeTab(tab.id);
              }}
              className={cn(
                "ml-0.5 transition-opacity rounded hover:bg-white/[0.08]",
                tab.id === activeTabId ? "opacity-60 hover:opacity-100" : "opacity-0 group-hover:opacity-60"
              )}
            >
              <X className="h-3 w-3" />
            </span>
          </button>
        ))}
        <button
          onClick={spawnTab}
          className="flex items-center justify-center h-6 w-6 rounded text-zinc-500 hover:text-zinc-300 hover:bg-white/[0.05] transition-colors ml-0.5"
        >
          <Plus className="h-3 w-3" />
        </button>
        <div className="flex-1" />
        <button
          onClick={onMinimize}
          className="flex items-center justify-center h-6 w-6 rounded text-zinc-500 hover:text-zinc-300 hover:bg-white/[0.05] transition-colors mr-1"
          title="Minimize terminal"
        >
          <ChevronDown className="h-3 w-3" />
        </button>
      </div>
      <div ref={hostRef} className="flex-1 relative overflow-hidden" />
    </div>
  );
}
