import { useEffect, useRef, useCallback, useState } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import "@xterm/xterm/css/xterm.css";

interface TerminalOutputPayload {
  session_id: string;
  data: number[];
}

export function TerminalPanel() {
  const containerRef = useRef<HTMLDivElement>(null);
  const terminalRef = useRef<Terminal | null>(null);
  const fitAddonRef = useRef<FitAddon | null>(null);
  const sessionIdRef = useRef<string | null>(null);
  const [isReady, setIsReady] = useState(false);

  const initTerminal = useCallback(async () => {
    if (!containerRef.current || terminalRef.current) return;

    const term = new Terminal({
      fontSize: 13,
      fontFamily: "'JetBrains Mono', 'Fira Code', 'SF Mono', Menlo, monospace",
      lineHeight: 1.4,
      cursorBlink: true,
      cursorStyle: "bar",
      theme: {
        background: "#0A0A0A",
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
      },
    });

    const fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    term.open(containerRef.current);
    fitAddon.fit();

    terminalRef.current = term;
    fitAddonRef.current = fitAddon;

    const dims = fitAddon.proposeDimensions();
    const cols = dims?.cols ?? 120;
    const rows = dims?.rows ?? 30;

    try {
      const sessionId = await invoke<string>("terminal_spawn", {
        cwd: null,
        cols,
        rows,
      });
      sessionIdRef.current = sessionId;
      setIsReady(true);

      term.onData((data) => {
        if (sessionIdRef.current) {
          const encoder = new TextEncoder();
          const bytes = Array.from(encoder.encode(data));
          invoke("terminal_write", {
            sessionId: sessionIdRef.current,
            data: bytes,
          });
        }
      });
    } catch (err) {
      term.writeln(`\x1b[31mFailed to spawn terminal: ${err}\x1b[0m`);
    }
  }, []);

  useEffect(() => {
    initTerminal();

    return () => {
      if (sessionIdRef.current) {
        invoke("terminal_kill", { sessionId: sessionIdRef.current });
      }
      terminalRef.current?.dispose();
      terminalRef.current = null;
    };
  }, [initTerminal]);

  useEffect(() => {
    if (!isReady) return;

    const unlisten = listen<TerminalOutputPayload>("terminal-output", (event) => {
      if (event.payload.session_id === sessionIdRef.current) {
        const bytes = new Uint8Array(event.payload.data);
        terminalRef.current?.write(bytes);
      }
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, [isReady]);

  useEffect(() => {
    const handleResize = () => {
      if (fitAddonRef.current && terminalRef.current) {
        fitAddonRef.current.fit();
        const dims = fitAddonRef.current.proposeDimensions();
        if (dims && sessionIdRef.current) {
          invoke("terminal_resize", {
            sessionId: sessionIdRef.current,
            cols: dims.cols,
            rows: dims.rows,
          });
        }
      }
    };

    const observer = new ResizeObserver(handleResize);
    if (containerRef.current) {
      observer.observe(containerRef.current);
    }

    return () => observer.disconnect();
  }, []);

  return (
    <div className="h-full w-full bg-[#0A0A0A]">
      <div ref={containerRef} className="h-full w-full p-2" />
    </div>
  );
}
