import { useState, useEffect, useMemo, useCallback } from "react";
import { X, Loader2 } from "lucide-react";
import { useAgentsStore } from "@/stores/useAgentsStore";
import { useSettingsStore } from "@/stores/settings-store";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useI18n } from "@/i18n/i18n";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import {
  vscDarkPlus,
  atomDark,
  dracula,
  nord,
  oneDark,
  coldarkDark,
  oneLight,
  ghcolors,
  nightOwl,
  materialDark,
  materialOceanic,
  synthwave84,
  shadesOfPurple,
  duotoneDark,
  gruvboxDark,
} from "react-syntax-highlighter/dist/esm/styles/prism";

const THEMES: Record<string, any> = {
  vscDarkPlus,
  atomDark,
  dracula,
  nord,
  oneDark,
  coldarkDark,
  oneLight,
  ghcolors,
  nightOwl,
  materialDark,
  materialOceanic,
  synthwave84,
  shadesOfPurple,
  duotoneDark,
  gruvboxDark,
};

const EDITOR_FONT = 'JetBrains Mono, Menlo, Monaco, Consolas, "Courier New", monospace';

const LANG_MAP: Record<string, string> = {
  js: "javascript", ts: "typescript", tsx: "tsx", jsx: "jsx", php: "php",
  rs: "rust", py: "python", sql: "sql", json: "json", md: "markdown",
  html: "html", css: "css", yml: "yaml", yaml: "yaml",
};

function getLanguage(filename: string): string {
  return LANG_MAP[filename.split(".").pop()?.toLowerCase() ?? ""] ?? "text";
}

export function FileEditor({ hideHeader }: { hideHeader?: boolean }) {
  const { t } = useI18n();
  const { selectedFilePath, setSelectedFilePath, repositoryGroups, selectedIssueId } = useAgentsStore();
  const { editorTheme } = useSettingsStore();
  const [content, setContent] = useState<string>("");
  const [isLoading, setIsLoading] = useState(false);

  const allIssues = repositoryGroups.flatMap((g) => g.repositories.flatMap((r) => r.issues));
  const selectedIssue = allIssues.find((i) => i.id === selectedIssueId);
  const absolutePath =
    selectedIssue?.workspacePath && selectedFilePath ? `${selectedIssue.workspacePath}/${selectedFilePath}` : null;

  const loadFileContent = useCallback(async () => {
    if (!absolutePath) {
      setContent("");
      return;
    }
    try {
      setIsLoading(true);
      setContent(await invoke<string>("read_file", { path: absolutePath }));
    } catch (error) {
      setContent(`Error loading file: ${error}`);
    } finally {
      setIsLoading(false);
    }
  }, [absolutePath]);

  useEffect(() => {
    void loadFileContent();
  }, [loadFileContent]);

  useEffect(() => {
    if (!absolutePath) return;
    const unlisten = getCurrentWindow().onFocusChanged(({ payload: focused }) => {
      if (focused) void loadFileContent();
    });
    return () => { void unlisten.then((fn) => fn()); };
  }, [absolutePath, loadFileContent]);

  const isLarge = content.length > 80_000 || content.split("\n").length > 2500;

  const highlight = useMemo(
    () => (
      <SyntaxHighlighter
        language={selectedFilePath ? getLanguage(selectedFilePath) : "text"}
        style={THEMES[editorTheme] || oneDark}
        showLineNumbers
        lineNumberStyle={{ minWidth: "3.5em", paddingRight: "2em", color: "#333", textAlign: "right", fontSize: "11px", userSelect: "none" }}
        codeTagProps={{ style: { background: "none", fontFamily: EDITOR_FONT } }}
        customStyle={{ margin: 0, padding: "1.5rem 0", background: "transparent", fontSize: "13px", fontFamily: EDITOR_FONT, lineHeight: "1.6" }}
      >
        {content || " "}
      </SyntaxHighlighter>
    ),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [content, editorTheme, selectedFilePath],
  );

  if (!selectedFilePath) return null;

  return (
    <div className="flex flex-col h-full bg-background">
      {!hideHeader && (
        <div className="h-11 border-b border-white/[0.05] flex items-center justify-between px-4 bg-background">
          <span className="text-[10px] text-zinc-500 font-mono truncate">{selectedFilePath}</span>
          <button
            onClick={() => setSelectedFilePath(null)}
            className="p-1 hover:bg-red-500/10 hover:text-red-500 rounded text-zinc-500 transition-colors"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      )}

      <div className="flex-1 overflow-hidden relative">
        {isLoading && (
          <div className="absolute inset-0 flex items-center justify-center bg-background/80 backdrop-blur-sm z-10">
            <div className="flex items-center gap-2 text-zinc-500 text-[11px]">
              <Loader2 className="h-4 w-4 animate-spin text-purple-400" />
              <span>{t("agents.fileEditor.loading")}</span>
            </div>
          </div>
        )}

        <div className="h-full w-full overflow-auto custom-scrollbar pt-2 pb-6">
          {isLarge ? (
            <pre className="px-6 py-6 font-mono text-[13px] leading-[1.6] text-zinc-300 whitespace-pre">{content}</pre>
          ) : (
            highlight
          )}
        </div>
      </div>
    </div>
  );
}
